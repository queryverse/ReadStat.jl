# Low-level writer: a thin, safe Julia layer over the C writer API. It
# mirrors the C call sequence one-to-one — define label sets, define
# variables, begin writing, insert rows, end — and streams all output bytes
# into any Julia IO through the C data-writer callback. The high-level
# write_dta/write_sav/... functions in writer/write.jl are built on top;
# reach for this layer directly to control every detail the C API exposes.

"""
    Writer(io::IO)
    Writer(path::AbstractString)

A handle for writing a stat-package file through the C writer API. Follow
the C call order: [`add_label_set!`](@ref)/[`label!`](@ref) for value
labels, [`add_variable!`](@ref) for each column, the file-level setters
([`file_label!`](@ref), [`timestamp!`](@ref), [`compression!`](@ref), ...),
then [`begin_writing!`](@ref), one [`begin_row!`](@ref)/`insert_*`/
[`end_row!`](@ref) cycle per observation, and finally `close`. Output
bytes stream into the given IO (a path is opened for writing and closed
again by `close`).
"""
mutable struct Writer
    ptr::WriterPtr
    io::IO
    owns_io::Bool
    err::Union{Nothing,Tuple{Any,Any}}
    began::Bool
    ended::Bool
end

struct WriterVariable
    ptr::VariablePtr
end

struct LabelSet
    ptr::LabelSetPtr
    type::ReadStatType
end

struct StringRef
    ptr::StringRefPtr
end

function Writer(io::IO)
    ptr = readstat_writer_init()
    ptr == C_NULL && error("readstat_writer_init failed")
    w = Writer(ptr, io, false, nothing, false, false)
    _writer_check(w, readstat_set_data_writer(ptr, CF_DATA_WRITER[]))
    finalizer(_writer_finalize, w)
    return w
end

Writer(path::AbstractString) = (w = Writer(open(path, "w")); w.owns_io = true; w)

function _writer_finalize(w::Writer)
    if w.ptr != C_NULL
        readstat_writer_free(w.ptr)
        w.ptr = C_NULL
    end
    return
end

function handle_data_write(data::Ptr{Cvoid}, len::Csize_t, ctx::Ptr{Cvoid})::Cssize_t
    w = unsafe_pointer_to_objref(ctx)::Writer
    try
        unsafe_write(w.io, Ptr{UInt8}(data), UInt(len))
        return Cssize_t(len)
    catch e
        w.err = (e, catch_backtrace())
        return Cssize_t(-1)
    end
end

const CF_DATA_WRITER = Ref(C_NULL)

function _init_writer_cfunctions()
    CF_DATA_WRITER[] = @cfunction(handle_data_write, Cssize_t, (Ptr{Cvoid}, Csize_t, Ptr{Cvoid}))
    return nothing
end

function _writer_check(w::Writer, err::ReadStatError)
    if w.err !== nothing
        e, _ = w.err
        throw(e)
    end
    err == READSTAT_OK || error("readstat writer error: $(readstat_error_message(err))")
    return w
end

_ptr(w::Writer) = (w.ptr == C_NULL && error("Writer is closed"); w.ptr)

# The Julia storage type used for each writable ReadStatType.
function rstype(::Type{T}) where {T}
    T === Int8 || T === Bool ? READSTAT_TYPE_INT8 :
    T === Int16 ? READSTAT_TYPE_INT16 :
    T <: Integer ? READSTAT_TYPE_INT32 :
    T === Float32 ? READSTAT_TYPE_FLOAT :
    T <: Real ? READSTAT_TYPE_DOUBLE :
    T <: Union{AbstractString,Char} ? READSTAT_TYPE_STRING :
    throw(ArgumentError("no readstat storage type for $T"))
end

"""
    add_label_set!(w::Writer, type, name) -> LabelSet

Create a named value-label set. `type` is a `ReadStatType` or a Julia type
(`Int32`, `Float64`, `String`); add entries with [`label!`](@ref) and attach
the set to variables via `add_variable!(...; label_set=...)`.
"""
add_label_set!(w::Writer, type::ReadStatType, name::Union{Symbol,AbstractString}) =
    LabelSet(readstat_add_label_set(_ptr(w), type, string(name)), type)
add_label_set!(w::Writer, ::Type{T}, name::Union{Symbol,AbstractString}) where {T} =
    add_label_set!(w, rstype(T), name)

"""
    label!(ls::LabelSet, value, label::AbstractString)

Add one entry to a value-label set. Numeric values go to the set's numeric
key type, strings to string keys, and a `Char` labels a tagged missing value
(`.a`-`.z`, Stata/SAS only).
"""
function label!(ls::LabelSet, value::Real, label::AbstractString)
    if ls.type == READSTAT_TYPE_DOUBLE || ls.type == READSTAT_TYPE_FLOAT
        readstat_label_double_value(ls.ptr, Float64(value), label)
    else
        readstat_label_int32_value(ls.ptr, Int32(value), label)
    end
    return ls
end
label!(ls::LabelSet, value::AbstractString, label::AbstractString) =
    (readstat_label_string_value(ls.ptr, value, label); ls)
label!(ls::LabelSet, tag::Char, label::AbstractString) =
    (readstat_label_tagged_value(ls.ptr, tag, label); ls)

"""
    add_variable!(w::Writer, name, type; storage_width=0, label="", format="",
                  label_set=nothing, measure=READSTAT_MEASURE_UNKNOWN,
                  alignment=READSTAT_ALIGNMENT_UNKNOWN, display_width=0,
                  missing_values=(), missing_ranges=()) -> WriterVariable

Define the next variable. `type` is a `ReadStatType` or a Julia type;
`storage_width` matters for strings (all formats) and doubles (XPORT).
`missing_values`/`missing_ranges` declare SPSS user-defined missing values
(numbers or strings; ranges as 2-tuples).
"""
function add_variable!(w::Writer, name::Union{Symbol,AbstractString}, type::ReadStatType;
                       storage_width::Integer=0, label::AbstractString="",
                       format::AbstractString="", label_set::Union{Nothing,LabelSet}=nothing,
                       measure::ReadStatMeasure=READSTAT_MEASURE_UNKNOWN,
                       alignment::ReadStatAlignment=READSTAT_ALIGNMENT_UNKNOWN,
                       display_width::Integer=0, missing_values=(), missing_ranges=())
    ptr = readstat_add_variable(_ptr(w), string(name), type, storage_width)
    ptr == C_NULL && error("readstat_add_variable failed for $name")
    isempty(label) || readstat_variable_set_label(ptr, label)
    isempty(format) || readstat_variable_set_format(ptr, format)
    label_set === nothing || readstat_variable_set_label_set(ptr, label_set.ptr)
    measure == READSTAT_MEASURE_UNKNOWN || readstat_variable_set_measure(ptr, measure)
    alignment == READSTAT_ALIGNMENT_UNKNOWN || readstat_variable_set_alignment(ptr, alignment)
    display_width == 0 || readstat_variable_set_display_width(ptr, display_width)
    for v in missing_values
        _writer_check(w, v isa AbstractString ?
            readstat_variable_add_missing_string_value(ptr, v) :
            readstat_variable_add_missing_double_value(ptr, Float64(v)))
    end
    for (lo, hi) in missing_ranges
        _writer_check(w, lo isa AbstractString ?
            readstat_variable_add_missing_string_range(ptr, lo, hi) :
            readstat_variable_add_missing_double_range(ptr, Float64(lo), Float64(hi)))
    end
    return WriterVariable(ptr)
end
add_variable!(w::Writer, name::Union{Symbol,AbstractString}, ::Type{T}; kwargs...) where {T} =
    add_variable!(w, name, rstype(T); kwargs...)

"""
    add_note!(w::Writer, note)

Add a file note (SPSS Document Record line — at most 80 characters there —
or a Stata note).
"""
add_note!(w::Writer, note::AbstractString) = (readstat_add_note(_ptr(w), note); w)

"""
    add_string_ref!(w::Writer, s) -> StringRef

Intern a string for a `READSTAT_TYPE_STRING_REF` (Stata strL) column;
insert it into rows with [`insert_string_ref!`](@ref). Refs can be shared
across columns and rows.
"""
add_string_ref!(w::Writer, s::AbstractString) = StringRef(readstat_add_string_ref(_ptr(w), s))

file_label!(w::Writer, s::AbstractString) =
    _writer_check(w, readstat_writer_set_file_label(_ptr(w), s))
timestamp!(w::Writer, t::DateTime) =
    _writer_check(w, readstat_writer_set_file_timestamp(_ptr(w),
        round(Int64, Dates.datetime2unix(t))))
fweight!(w::Writer, var::WriterVariable) =
    _writer_check(w, readstat_writer_set_fweight_variable(_ptr(w), var.ptr))
format_version!(w::Writer, v::Integer) =
    _writer_check(w, readstat_writer_set_file_format_version(_ptr(w), v))
table_name!(w::Writer, s::AbstractString) =
    _writer_check(w, readstat_writer_set_table_name(_ptr(w), s))
is_64bit!(w::Writer, b::Bool) =
    _writer_check(w, readstat_writer_set_file_format_is_64bit(_ptr(w), b))

const COMPRESSION_BY_NAME = Dict(:none => READSTAT_COMPRESS_NONE,
    :rows => READSTAT_COMPRESS_ROWS, :binary => READSTAT_COMPRESS_BINARY)

"""
    compression!(w::Writer, c)

Set the output compression: `:none`, `:rows` (sas7bdat and sav), or
`:binary` (sav only — produces a zsav file).
"""
function compression!(w::Writer, c::Symbol)
    haskey(COMPRESSION_BY_NAME, c) ||
        throw(ArgumentError("compression must be :none, :rows, or :binary"))
    _writer_check(w, readstat_writer_set_compression(_ptr(w), COMPRESSION_BY_NAME[c]))
end

"""
    begin_writing!(w::Writer, format::Symbol, row_count)

Start writing the file body for `format` (`:dta`, `:sav`, `:por`,
`:sas7bdat`, `:xport`, or `:sas7bcat`, which takes no rows). All label
sets, variables, and file-level metadata must be defined beforehand.
"""
function begin_writing!(w::Writer, format::Symbol, row_count::Integer=0)
    ptr = _ptr(w)
    ctx = pointer_from_objref(w)
    err = if format === :dta
        readstat_begin_writing_dta(ptr, ctx, row_count)
    elseif format === :sav
        readstat_begin_writing_sav(ptr, ctx, row_count)
    elseif format === :por
        readstat_begin_writing_por(ptr, ctx, row_count)
    elseif format === :sas7bdat
        readstat_begin_writing_sas7bdat(ptr, ctx, row_count)
    elseif format === :xport
        readstat_begin_writing_xport(ptr, ctx, row_count)
    elseif format === :sas7bcat
        readstat_begin_writing_sas7bcat(ptr, ctx)
    else
        throw(ArgumentError("unknown format $format"))
    end
    _writer_check(w, err)
    w.began = true
    return w
end

validate_metadata(w::Writer) = _writer_check(w, readstat_validate_metadata(_ptr(w)))
validate_variable(w::Writer, var::WriterVariable) =
    _writer_check(w, readstat_validate_variable(_ptr(w), var.ptr))

begin_row!(w::Writer) = _writer_check(w, readstat_begin_row(_ptr(w)))
end_row!(w::Writer) = _writer_check(w, readstat_end_row(_ptr(w)))

insert_value!(w::Writer, var::WriterVariable, v::Int8) =
    _writer_check(w, readstat_insert_int8_value(_ptr(w), var.ptr, v))
insert_value!(w::Writer, var::WriterVariable, v::Int16) =
    _writer_check(w, readstat_insert_int16_value(_ptr(w), var.ptr, v))
insert_value!(w::Writer, var::WriterVariable, v::Int32) =
    _writer_check(w, readstat_insert_int32_value(_ptr(w), var.ptr, v))
insert_value!(w::Writer, var::WriterVariable, v::Float32) =
    _writer_check(w, readstat_insert_float_value(_ptr(w), var.ptr, v))
insert_value!(w::Writer, var::WriterVariable, v::Float64) =
    _writer_check(w, readstat_insert_double_value(_ptr(w), var.ptr, v))
insert_value!(w::Writer, var::WriterVariable, v::AbstractString) =
    _writer_check(w, readstat_insert_string_value(_ptr(w), var.ptr, v))
insert_missing!(w::Writer, var::WriterVariable) =
    _writer_check(w, readstat_insert_missing_value(_ptr(w), var.ptr))
insert_tagged_missing!(w::Writer, var::WriterVariable, tag::Char) =
    _writer_check(w, readstat_insert_tagged_missing_value(_ptr(w), var.ptr, tag))
insert_string_ref!(w::Writer, var::WriterVariable, ref::StringRef) =
    _writer_check(w, readstat_insert_string_ref(_ptr(w), var.ptr, ref.ptr))

"""
    end_writing!(w::Writer)

Finish the file body. Called automatically by `close(w)` when writing has
begun and not yet ended.
"""
function end_writing!(w::Writer)
    w.ended && return w
    GC.@preserve w _writer_check(w, readstat_end_writing(_ptr(w)))
    w.ended = true
    return w
end

function Base.close(w::Writer)
    if w.ptr != C_NULL
        w.began && !w.ended && end_writing!(w)
        readstat_writer_free(w.ptr)
        w.ptr = C_NULL
    end
    w.owns_io && close(w.io)
    return nothing
end
