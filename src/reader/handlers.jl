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
        t = readstat_variable_get_type(variable)
        vm = ReadStatVarMeta(
            Symbol(readstat_variable_get_name(variable)),
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
        addcolumn!(pc.cols, jltype(t), max(pc.meta.row_count, 0))
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
        row = Int(obs_index) + 1
        cols = pc.cols
        code, slot = @inbounds cols.slots[idx]
        miss = readstat_value_is_missing(value, variable)

        if code == CODE_STRING
            buf = @inbounds cols.strings[slot]
            if miss
                setmissing!(buf, row)
            else
                ptr = readstat_string_value(value)
                setvalue!(buf, row, ptr == C_NULL ? "" : unsafe_string(ptr))
            end
        elseif code == CODE_INT8
            buf = @inbounds cols.int8s[slot]
            miss ? setmissing!(buf, row) : setvalue!(buf, row, readstat_int8_value(value))
        elseif code == CODE_INT16
            buf = @inbounds cols.int16s[slot]
            miss ? setmissing!(buf, row) : setvalue!(buf, row, readstat_int16_value(value))
        elseif code == CODE_INT32
            buf = @inbounds cols.int32s[slot]
            miss ? setmissing!(buf, row) : setvalue!(buf, row, readstat_int32_value(value))
        elseif code == CODE_FLOAT
            buf = @inbounds cols.floats[slot]
            miss ? setmissing!(buf, row) : setvalue!(buf, row, readstat_float_value(value))
        else
            buf = @inbounds cols.doubles[slot]
            miss ? setmissing!(buf, row) : setvalue!(buf, row, readstat_double_value(value))
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

# @cfunction pointers are runtime values, so they are created in __init__ and
# cached here rather than serialized into the precompile image.
const CF_METADATA = Ref(C_NULL)
const CF_VARIABLE = Ref(C_NULL)
const CF_VALUE = Ref(C_NULL)
const CF_VALUE_LABEL = Ref(C_NULL)

function _init_cfunctions()
    CF_METADATA[] = @cfunction(handle_metadata, Cint, (MetadataPtr, Any))
    CF_VARIABLE[] = @cfunction(handle_variable, Cint, (Cint, VariablePtr, Cstring, Any))
    CF_VALUE[] = @cfunction(handle_value, Cint, (Cint, VariablePtr, ReadStatValue, Any))
    CF_VALUE_LABEL[] = @cfunction(handle_value_label, Cint, (Cstring, ReadStatValue, Cstring, Any))
    return nothing
end
