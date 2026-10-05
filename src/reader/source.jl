# A lazy handle over a stat-package file, designed for consumers that push
# work down into the reader — a display layer that wants ten rows, or a
# query engine that plans against the schema and then reads a projection of
# a row range, possibly in chunks.

"""
    ReadStatSource(path_or_io; format=:auto, kwargs...)

A cheap, lazy handle over a stat-package data file: constructing one parses
nothing. [`schema`](@ref) returns (and caches) the metadata-only table;
[`colnames`](@ref), [`coltypes`](@ref), and [`nrows`](@ref) answer planning
questions from it; `read(src; usecols=..., rows=...)` reads a projection of
a row range; and [`chunks`](@ref) streams the data in table-sized pieces.
[`supports`](@ref) reports which pushdowns the underlying format can honor.

The keyword arguments (`convert_datetime`, `apply_value_labels`,
`user_missing`, `file_encoding`, `handler_encoding`, `catalog`) fix how this
source presents its data; every read through the source applies them. For
`IO` input the stream must contain the complete file and `format` is
required; a non-seekable stream is buffered in memory once.
"""
mutable struct ReadStatSource
    source::Union{String,IO}
    format::Symbol
    convert_datetime::Bool
    apply_value_labels::Bool
    user_missing::Symbol
    file_encoding::Union{Nothing,String}
    handler_encoding::Union{Nothing,String}
    catalog::Union{Nothing,String}
    schema::Union{Nothing,ReadStatTable}
end

function ReadStatSource(source::Union{AbstractString,IO}; format::Symbol=:auto,
                        convert_datetime::Bool=true, apply_value_labels::Bool=false,
                        user_missing::Symbol=:na,
                        file_encoding::Union{Nothing,AbstractString}=nothing,
                        handler_encoding::Union{Nothing,AbstractString}=nothing,
                        catalog::Union{Nothing,AbstractString}=nothing)
    fmt = _sniff_format(source, format)
    user_missing in (:na, :keep) ||
        throw(ArgumentError("user_missing must be :na or :keep"))
    src = source isa AbstractString ? String(source) : _ensure_seekable(source)
    return ReadStatSource(src, fmt, convert_datetime, apply_value_labels, user_missing,
        file_encoding === nothing ? nothing : String(file_encoding),
        handler_encoding === nothing ? nothing : String(handler_encoding),
        catalog === nothing ? nothing : String(catalog),
        nothing)
end

# Metadata-only parse honoring the source's presentation options (and an
# optional projection, used by `chunks` so its schema matches its chunks).
function _source_meta(src::ReadStatSource, usecols)
    pc = ParseContext()
    pc.collect_values = false
    pc.usecols = _colselector(usecols)
    pc.file_encoding = src.file_encoding
    pc.handler_encoding = src.handler_encoding
    pc.convert_datetime = src.convert_datetime
    pc.apply_value_labels = src.apply_value_labels
    pc.file_format = src.format
    parse_file!(pc, src.source, src.format)
    src.catalog === nothing || merge!(pc.meta.value_labels, read_sas7bcat(src.catalog))
    return pc
end

"""
    schema(src::ReadStatSource) -> ReadStatTable

The metadata of the source as a zero-row table (cached after the first
call): column names and types, file- and variable-level metadata, value
labels, and notes — everything a consumer needs to plan a read without
touching the data.
"""
function schema(src::ReadStatSource)
    if src.schema === nothing
        src.schema = build_table(_source_meta(src, nothing))
    end
    return src.schema::ReadStatTable
end

"""
    colnames(src::ReadStatSource) -> Vector{Symbol}

The column names of the source (from the cached [`schema`](@ref)).
"""
colnames(src::ReadStatSource) = names(schema(src))

"""
    coltypes(src::ReadStatSource) -> Vector{Type}

The element types the source's columns will have when read — after date/time
conversion and value-label application per the source's options (e.g.
`DataValue{Float64}`, `DataValue{Date}`).
"""
coltypes(src::ReadStatSource) = Type[eltype(schema(src)[i]) for i in 1:size(schema(src), 2)]

"""
    nrows(src::ReadStatSource) -> Union{Int, Missing}

The number of rows recorded in the file, or `missing` when the format does
not record one (XPORT, POR, some non-conforming SAV files).
"""
function nrows(src::ReadStatSource)
    rc = filemetadata(schema(src)).row_count
    return rc < 0 ? missing : rc
end

"""
    supports(src::ReadStatSource, feature::Symbol) -> Bool

Whether the source can honor a pushdown feature:

- `:projection`: column selection during the parse (always true).
- `:row_range`: `rows=` ranges via the C row offset/limit (always true).
- `:row_count`: a row count known without reading the data.
- `:parallel`: multi-task reading (path input to a format that records its
  row count).
"""
function supports(src::ReadStatSource, feature::Symbol)
    feature === :projection && return true
    feature === :row_range && return true
    feature === :row_count && return !ismissing(nrows(src))
    feature === :parallel &&
        return src.source isa String && src.format in _THREADED_FORMATS
    return false
end

"""
    read(src::ReadStatSource; usecols=nothing, rows=nothing, ntasks=nothing,
         progress=nothing) -> ReadStatTable

Read the source, optionally pushing down a column projection (`usecols`, as
in the readers) and a 1-based row range (`rows`, a `UnitRange`); both are
applied inside the C parse. All other behavior follows the options fixed at
[`ReadStatSource`](@ref) construction.
"""
function Base.read(src::ReadStatSource; usecols=nothing,
                   rows::Union{Nothing,AbstractUnitRange{<:Integer}}=nothing,
                   ntasks::Union{Nothing,Integer}=nothing, progress=nothing)
    row_offset = 0
    row_limit = nothing
    if rows !== nothing
        first(rows) >= 1 || throw(ArgumentError("rows must be a 1-based range"))
        row_offset = first(rows) - 1
        row_limit = length(rows)
    end
    return read_data_file(src.source, src.format; usecols, row_limit, row_offset,
        file_encoding=src.file_encoding, handler_encoding=src.handler_encoding,
        user_missing=src.user_missing, convert_datetime=src.convert_datetime,
        apply_value_labels=src.apply_value_labels, catalog=src.catalog, ntasks, progress)
end

function Base.show(io::IO, src::ReadStatSource)
    what = src.source isa String ? repr(src.source) : "<IO>"
    print(io, "ReadStatSource(", what, ", ", src.format, ")")
end
