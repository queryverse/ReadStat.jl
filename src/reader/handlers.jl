# Parse handler bodies. All of them are top-level functions whose @cfunction
# pointers are created once in __init__ and shared by every parse — per-parse
# state lives exclusively in the ParseContext passed through user_ctx.
#
# Every handler body is wrapped in try/catch: a Julia exception must never
# unwind through the C parser, so it is captured on the context and the
# handler returns READSTAT_HANDLER_ABORT; the parse driver rethrows it once
# readstat_parse has returned (with READSTAT_ERROR_USER_ABORT).

function handle_metadata(metadata::MetadataPtr, ctx::Any)::Cint
    pc = ctx::ParseContext
    try
        m = pc.meta
        m.row_count = readstat_get_row_count(metadata)
        m.var_count = readstat_get_var_count(metadata)
        m.creation_time = Dates.unix2datetime(readstat_get_creation_time(metadata))
        m.modified_time = Dates.unix2datetime(readstat_get_modified_time(metadata))
        m.file_format_version = readstat_get_file_format_version(metadata)
        m.is_64bit = readstat_get_file_format_is_64bit(metadata)
        m.compression = readstat_get_compression(metadata)
        m.endianness = readstat_get_endianness(metadata)
        m.table_name = readstat_get_table_name(metadata)
        m.file_label = readstat_get_file_label(metadata)
        m.file_encoding = readstat_get_file_encoding(metadata)
        return READSTAT_HANDLER_OK
    catch e
        pc.err = (e, catch_backtrace())
        return READSTAT_HANDLER_ABORT
    end
end

function _missing_ranges(variable::VariablePtr)
    n = readstat_variable_get_missing_ranges_count(variable)
    ranges = Vector{Tuple{Any,Any}}(undef, n)
    for i in 0:(n - 1)
        lo = readstat_variable_get_missing_range_lo(variable, i)
        hi = readstat_variable_get_missing_range_hi(variable, i)
        ranges[i + 1] = (_native_value(lo), _native_value(hi))
    end
    return ranges
end

function _native_value(value::ReadStatValue)
    t = readstat_value_type(value)
    if t == READSTAT_TYPE_INT8
        readstat_int8_value(value)
    elseif t == READSTAT_TYPE_INT16
        readstat_int16_value(value)
    elseif t == READSTAT_TYPE_INT32
        readstat_int32_value(value)
    elseif t == READSTAT_TYPE_FLOAT
        readstat_float_value(value)
    elseif t == READSTAT_TYPE_DOUBLE
        readstat_double_value(value)
    else
        ptr = readstat_string_value(value)
        ptr == C_NULL ? "" : unsafe_string(ptr)
    end
end

function handle_variable(index::Cint, variable::VariablePtr, val_labels::Cstring, ctx::Any)::Cint
    pc = ctx::ParseContext
    try
        name = Symbol(readstat_variable_get_name(variable))
        sel = pc.usecols
        if sel !== nothing && !(sel(name, Int(index) + 1)::Bool)
            return READSTAT_HANDLER_SKIP_VARIABLE
        end
        # Chunk contexts of a multi-task read come with shared, fully
        # prepared columns; only the skip decision above matters here.
        pc.preassigned_cols && return READSTAT_HANDLER_OK
        t = readstat_variable_get_type(variable)
        vm = ReadStatVarMeta(
            name,
            readstat_variable_get_label(variable),
            readstat_variable_get_format(variable),
            t,
            readstat_variable_get_type_class(variable),
            val_labels == C_NULL ? Symbol("") : Symbol(unsafe_string(val_labels)),
            Int(readstat_variable_get_storage_width(variable)),
            Int(readstat_variable_get_display_width(variable)),
            readstat_variable_get_measure(variable),
            readstat_variable_get_alignment(variable),
            _missing_ranges(variable))
        push!(pc.varmeta, vm)
        push!(pc.names, vm.name)
        addcolumn!(pc.cols, jltype(t), alloc_rows(pc))
        return READSTAT_HANDLER_OK
    catch e
        pc.err = (e, catch_backtrace())
        return READSTAT_HANDLER_ABORT
    end
end

function handle_value(obs_index::Cint, variable::VariablePtr, value::ReadStatValue, ctx::Any)::Cint
    pc = ctx::ParseContext
    try
        idx = readstat_variable_get_index_after_skipping(variable) + 1
        row = pc.row_base + Int(obs_index) + 1
        # A negative row base emulates a row offset for parsers that ignore
        # readstat_set_row_offset (the fixed-width text parser).
        row < 1 && return READSTAT_HANDLER_OK
        cols = pc.cols
        code, slot = @inbounds cols.slots[idx]

        # Three kinds of missing values (readstat.h): system missing and
        # tagged missing (Stata/SAS .a-.z) always become NA, the latter with
        # its tag recorded; SPSS user-defined missing values become NA by
        # default but stay data under `user_missing=:keep`.
        local miss::Bool, tag::Char
        if readstat_value_is_tagged_missing(value)
            miss = true
            tag = readstat_value_tag(value)
        else
            tag = '\0'
            miss = pc.keep_user_missing ? readstat_value_is_system_missing(value) :
                readstat_value_is_missing(value, variable)
        end

        if code == CODE_STRING
            buf = @inbounds cols.strings[slot]
            if miss
                setmissing!(buf, row, tag)
            else
                ptr = readstat_string_value(value)
                setvalue!(buf, row, ptr == C_NULL ? "" : unsafe_string(ptr))
            end
        elseif code == CODE_INT8
            buf = @inbounds cols.int8s[slot]
            miss ? setmissing!(buf, row, tag) : setvalue!(buf, row, readstat_int8_value(value))
        elseif code == CODE_INT16
            buf = @inbounds cols.int16s[slot]
            miss ? setmissing!(buf, row, tag) : setvalue!(buf, row, readstat_int16_value(value))
        elseif code == CODE_INT32
            buf = @inbounds cols.int32s[slot]
            miss ? setmissing!(buf, row, tag) : setvalue!(buf, row, readstat_int32_value(value))
        elseif code == CODE_FLOAT
            buf = @inbounds cols.floats[slot]
            miss ? setmissing!(buf, row, tag) : setvalue!(buf, row, readstat_float_value(value))
        else
            buf = @inbounds cols.doubles[slot]
            miss ? setmissing!(buf, row, tag) : setvalue!(buf, row, readstat_double_value(value))
        end
        # Track the last fully delivered row so a parse stopped early (by the
        # progress callback) can be trimmed to complete rows; in chunked
        # streaming mode a completed chunk is flushed to its channel here.
        if idx == length(cols.slots)
            pc.rows_complete = row
            sink = pc.chunk_sink
            sink === nothing || _maybe_flush!(pc, sink, row)
        end
        return READSTAT_HANDLER_OK
    catch e
        pc.err = (e, catch_backtrace())
        return READSTAT_HANDLER_ABORT
    end
end

function handle_value_label(val_labels::Cstring, value::ReadStatValue, label::Cstring, ctx::Any)::Cint
    pc = ctx::ParseContext
    try
        val_labels == C_NULL && return READSTAT_HANDLER_OK
        name = Symbol(unsafe_string(val_labels))
        dict = get!(ValueLabelDict, pc.meta.value_labels, name)
        key = if readstat_value_is_tagged_missing(value)
            readstat_value_tag(value)
        else
            t = readstat_value_type(value)
            if t == READSTAT_TYPE_INT8
                Int32(readstat_int8_value(value))
            elseif t == READSTAT_TYPE_INT16
                Int32(readstat_int16_value(value))
            elseif t == READSTAT_TYPE_INT32
                readstat_int32_value(value)
            elseif t == READSTAT_TYPE_FLOAT
                Float64(readstat_float_value(value))
            elseif t == READSTAT_TYPE_DOUBLE
                readstat_double_value(value)
            else
                ptr = readstat_string_value(value)
                ptr == C_NULL ? "" : unsafe_string(ptr)
            end
        end
        dict[key] = label == C_NULL ? "" : unsafe_string(label)
        return READSTAT_HANDLER_OK
    catch e
        pc.err = (e, catch_backtrace())
        return READSTAT_HANDLER_ABORT
    end
end

function handle_note(note_index::Cint, note::Cstring, ctx::Any)::Cint
    pc = ctx::ParseContext
    try
        note == C_NULL || push!(pc.meta.notes, unsafe_string(note))
        return READSTAT_HANDLER_OK
    catch e
        pc.err = (e, catch_backtrace())
        return READSTAT_HANDLER_ABORT
    end
end

function handle_fweight(variable::VariablePtr, ctx::Any)::Cint
    pc = ctx::ParseContext
    try
        pc.meta.fweight = Symbol(readstat_variable_get_name(variable))
        return READSTAT_HANDLER_OK
    catch e
        pc.err = (e, catch_backtrace())
        return READSTAT_HANDLER_ABORT
    end
end

# The C error handler reports warnings the parse survives; it returns void,
# so exceptions can neither abort nor propagate — swallow them.
function handle_error(message::Cstring, ctx::Any)::Cvoid
    pc = ctx::ParseContext
    try
        message == C_NULL || push!(pc.warnings, unsafe_string(message))
    catch
    end
    return nothing
end

function handle_progress(progress::Cdouble, ctx::Any)::Cint
    pc = ctx::ParseContext
    try
        f = pc.progress
        if f !== nothing && f(Float64(progress)) === false
            pc.aborted = true
            return READSTAT_HANDLER_ABORT
        end
        return READSTAT_HANDLER_OK
    catch e
        pc.err = (e, catch_backtrace())
        return READSTAT_HANDLER_ABORT
    end
end

# @cfunction pointers are runtime values, so they are created in __init__ and
# cached here rather than serialized into the precompile image.
const CF_METADATA = Ref(C_NULL)
const CF_VARIABLE = Ref(C_NULL)
const CF_VALUE = Ref(C_NULL)
const CF_VALUE_LABEL = Ref(C_NULL)
const CF_NOTE = Ref(C_NULL)
const CF_FWEIGHT = Ref(C_NULL)
const CF_ERROR = Ref(C_NULL)
const CF_PROGRESS = Ref(C_NULL)

function _init_cfunctions()
    CF_METADATA[] = @cfunction(handle_metadata, Cint, (MetadataPtr, Any))
    CF_VARIABLE[] = @cfunction(handle_variable, Cint, (Cint, VariablePtr, Cstring, Any))
    CF_VALUE[] = @cfunction(handle_value, Cint, (Cint, VariablePtr, ReadStatValue, Any))
    CF_VALUE_LABEL[] = @cfunction(handle_value_label, Cint, (Cstring, ReadStatValue, Cstring, Any))
    CF_NOTE[] = @cfunction(handle_note, Cint, (Cint, Cstring, Any))
    CF_FWEIGHT[] = @cfunction(handle_fweight, Cint, (VariablePtr, Any))
    CF_ERROR[] = @cfunction(handle_error, Cvoid, (Cstring, Any))
    CF_PROGRESS[] = @cfunction(handle_progress, Cint, (Cdouble, Any))
    return nothing
end
