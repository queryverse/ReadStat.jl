# Parse driver and the public read entry points.

const FORMAT_BY_EXT = Dict(
    ".dta" => :dta,
    ".sav" => :sav,
    ".zsav" => :sav,
    ".por" => :por,
    ".sas7bdat" => :sas7bdat,
    ".xpt" => :xport,
    ".xport" => :xport,
)

function _sniff_format(path::AbstractString, format::Symbol)
    format === :auto || return format
    ext = lowercase(splitext(path)[2])
    fmt = get(FORMAT_BY_EXT, ext, nothing)
    fmt === nothing &&
        throw(ArgumentError("cannot infer the file format from extension \"$ext\"; pass `format=...`"))
    return fmt
end

function _sniff_format(io::IO, format::Symbol)
    format === :auto &&
        throw(ArgumentError("the file format cannot be inferred from an IO stream; pass `format=...`"))
    return format
end

function _parse_format(parser::ParserPtr, path::AbstractString, format::Symbol, ctx)
    if format === :dta
        CAPI.readstat_parse_dta(parser, path, ctx)
    elseif format === :sav
        CAPI.readstat_parse_sav(parser, path, ctx)
    elseif format === :por
        CAPI.readstat_parse_por(parser, path, ctx)
    elseif format === :sas7bdat
        CAPI.readstat_parse_sas7bdat(parser, path, ctx)
    elseif format === :xport
        CAPI.readstat_parse_xport(parser, path, ctx)
    elseif format === :sas7bcat
        CAPI.readstat_parse_sas7bcat(parser, path, ctx)
    else
        throw(ArgumentError("unknown format $format"))
    end
end

# Normalize the `usecols` kwarg into a `(name, index) -> Bool` predicate.
_colselector(::Nothing) = nothing
_colselector(s::Symbol) = (name, i) -> name === s
_colselector(idx::Integer) = let idx = Int(idx); (name, i) -> i == idx; end
_colselector(v::AbstractVector{Symbol}) = let s = Set(v); (name, i) -> name in s; end
_colselector(v::AbstractVector{<:Integer}) = let s = Set{Int}(v); (name, i) -> i in s; end
_colselector(r::Regex) = (name, i) -> occursin(r, String(name))
_colselector(f::Function) = (name, i) -> f(name)::Bool

function _set_handlers!(parser::ParserPtr, pc::ParseContext)
    readstat_set_metadata_handler(parser, CF_METADATA[])
    readstat_set_variable_handler(parser, CF_VARIABLE[])
    readstat_set_value_label_handler(parser, CF_VALUE_LABEL[])
    readstat_set_note_handler(parser, CF_NOTE[])
    readstat_set_fweight_handler(parser, CF_FWEIGHT[])
    readstat_set_error_handler(parser, CF_ERROR[])
    pc.collect_values && readstat_set_value_handler(parser, CF_VALUE[])
    pc.progress === nothing || readstat_set_progress_handler(parser, CF_PROGRESS[])
    pc.row_offset > 0 && readstat_set_row_offset(parser, pc.row_offset)
    pc.row_limit >= 0 && readstat_set_row_limit(parser, pc.row_limit)
    pc.file_encoding === nothing ||
        readstat_set_file_character_encoding(parser, pc.file_encoding)
    pc.handler_encoding === nothing ||
        readstat_set_handler_character_encoding(parser, pc.handler_encoding)
    return parser
end

function _finish_parse(pc::ParseContext, retval::ReadStatError, what::AbstractString)
    if pc.err !== nothing
        e, _ = pc.err
        throw(e)
    end
    for w in pc.warnings
        @warn "readstat: $w" _module = ReadStat _file = what
    end
    if retval == READSTAT_ERROR_USER_ABORT && pc.aborted
        # The progress callback stopped the parse; the caller gets the rows
        # delivered so far.
    elseif retval != READSTAT_OK
        error("Error parsing $what: $(readstat_error_message(retval))")
    end
    return pc
end

function parse_file!(pc::ParseContext, path::AbstractString, format::Symbol)
    isfile(path) || throw(ArgumentError("file not found: $path"))
    parser = readstat_parser_init()
    local retval
    try
        _set_handlers!(parser, pc)
        retval = _parse_format(parser, path, format, pc)
    finally
        readstat_parser_free(parser)
    end
    return _finish_parse(pc, retval, path)
end

function parse_file!(pc::ParseContext, io::IO, format::Symbol)
    src = IOSource(io)
    parser = readstat_parser_init()
    local retval
    try
        _set_handlers!(parser, pc)
        readstat_set_open_handler(parser, CF_IO_OPEN[])
        readstat_set_close_handler(parser, CF_IO_CLOSE[])
        readstat_set_seek_handler(parser, CF_IO_SEEK[])
        readstat_set_read_handler(parser, CF_IO_READ[])
        GC.@preserve src begin
            readstat_set_io_ctx(parser, pointer_from_objref(src))
            retval = _parse_format(parser, "", format, pc)
        end
    finally
        readstat_parser_free(parser)
    end
    if src.err !== nothing
        e, _ = src.err
        throw(e)
    end
    return _finish_parse(pc, retval, "IO stream")
end

function build_table(pc::ParseContext)
    pc.aborted && trimcolumns!(pc.cols, pc.rows_complete)
    n = length(pc.names)
    columns = Vector{AbstractVector}(undef, n)
    tags = Vector{Union{Nothing,Vector{Char}}}(undef, n)
    for i in 1:n
        col = finalize_column(pc.cols, i)
        vm = pc.varmeta[i]
        labels = vm.vallabel === Symbol("") ? nothing :
            get(pc.meta.value_labels, vm.vallabel, nothing)
        # Value labels take precedence over a date/time display format: a
        # labeled column holds codes, not calendar values.
        if labels === nothing && pc.convert_datetime && eltype(eltype(col)) <: Number
            rule = datetime_rule(vm.format, pc.file_format)
            if rule !== nothing
                f, target = rule
                col = convert_datetime_column(col, f, target)
            end
        end
        if pc.apply_value_labels && labels !== nothing
            col = LabeledArray(col, labels)
        end
        columns[i] = col
        tags[i] = column_tags(pc.cols, i)
    end
    return ReadStatTable(columns, pc.names, pc.meta, pc.varmeta, tags)
end

function read_data_file(source::Union{AbstractString,IO}, format::Symbol;
                        usecols=nothing,
                        row_limit::Union{Nothing,Integer}=nothing,
                        row_offset::Integer=0,
                        file_encoding::Union{Nothing,AbstractString}=nothing,
                        handler_encoding::Union{Nothing,AbstractString}=nothing,
                        user_missing::Symbol=:na,
                        convert_datetime::Bool=true,
                        apply_value_labels::Bool=false,
                        catalog::Union{Nothing,AbstractString}=nothing,
                        ntasks::Union{Nothing,Integer}=nothing,
                        progress=nothing)
    user_missing in (:na, :keep) ||
        throw(ArgumentError("user_missing must be :na or :keep"))
    row_offset >= 0 || throw(ArgumentError("row_offset must be non-negative"))
    row_limit === nothing || row_limit >= 0 ||
        throw(ArgumentError("row_limit must be non-negative"))
    pc = ParseContext()
    pc.usecols = _colselector(usecols)
    pc.progress = progress
    pc.row_offset = Int(row_offset)
    if row_limit == 0
        # The C library treats a row limit of 0 as "no limit", so a zero-row
        # read is done by not collecting values at all. No C row limit is set
        # either: the sav parser does not reliably deliver value labels when
        # one is in effect.
        pc.collect_values = false
    else
        pc.row_limit = row_limit === nothing ? -1 : Int(row_limit)
    end
    pc.file_encoding = file_encoding === nothing ? nothing : String(file_encoding)
    pc.handler_encoding = handler_encoding === nothing ? nothing : String(handler_encoding)
    pc.keep_user_missing = user_missing === :keep
    pc.apply_value_labels = apply_value_labels
    pc.convert_datetime = convert_datetime
    pc.file_format = format
    catalog === nothing || format === :sas7bdat ||
        throw(ArgumentError("`catalog` is only supported when reading sas7bdat files"))

    parsed = false
    if source isa AbstractString && pc.collect_values && progress === nothing &&
       format in _THREADED_FORMATS
        T = ntasks === nothing ? _auto_ntasks(source) : max(Int(ntasks), 1)
        T > 1 && (parsed = threaded_parse!(pc, source, format, T))
    end
    parsed || parse_file!(pc, source, format)
    catalog === nothing || merge!(pc.meta.value_labels, read_sas7bcat(catalog))
    return build_table(pc)
end

const _READ_KWARGS_DOC = """
Instead of a path, every reader also accepts an `IO` containing the complete
file (a non-seekable stream is buffered in memory first). The `progress`
callback only fires for path input.

All readers accept the same keyword arguments:

- `usecols`: read only these columns — a `Symbol`, column index, vector of
  either, `Regex`, or a predicate called with each column name. Skipped
  columns are never parsed (the C library skips them).
- `row_limit`: read at most this many rows.
- `row_offset`: skip this many rows from the start.
- `file_encoding`: override the character encoding declared in the file
  (an iconv-compatible name such as `"WINDOWS-1252"`).
- `handler_encoding`: the encoding delivered to Julia; defaults to UTF-8.
- `user_missing`: `:na` (default) collapses SPSS user-defined missing values
  to NA; `:keep` keeps them as data (the rules stay available in
  `varmetadata(tbl, col).missing_ranges`). System missing and tagged missing
  values are always NA; see [`missingtags`](@ref) for the tags.
- `convert_datetime`: decode columns whose display format is a date/time
  format into `Date`/`DateTime`/[`HMS`](@ref) columns (default `true`);
  `false` keeps the raw numbers. Value-labeled columns are never converted.
- `apply_value_labels`: when `true`, every value-labeled column is wrapped
  in a [`LabeledArray`](@ref) (labels for display, codes for computation).
  The raw label dictionaries are always available via [`valuelabels`](@ref)
  regardless.
- `catalog` (sas7bdat only): path to the `.sas7bcat` catalog holding the
  file's value labels; they are merged into the table's value labels.
- `ntasks`: number of parallel parsers for path input to formats that record
  a row count (`.dta`, `.sav`, `.sas7bdat`): the row range is split into
  contiguous chunks that parse concurrently into shared buffers. By default
  large files use up to 8 threads and small files parse serially; pass an
  integer to force a task count, or `1` to disable.
- `progress`: a function called with the parse fraction (0.0-1.0); return
  `false` to stop the parse and get the rows read so far (disables
  `ntasks`).
"""

"""
    read_dta(path; kwargs...) -> ReadStatTable

Read a Stata `.dta` file. See [`ReadStatTable`](@ref) for how to access the
data and metadata.

$_READ_KWARGS_DOC
"""
read_dta(source::Union{AbstractString,IO}; kwargs...) = read_data_file(source, :dta; kwargs...)

"""
    read_sav(path; kwargs...) -> ReadStatTable

Read an SPSS `.sav` (or `.zsav`) file.

$_READ_KWARGS_DOC
"""
read_sav(source::Union{AbstractString,IO}; kwargs...) = read_data_file(source, :sav; kwargs...)

"""
    read_por(path; kwargs...) -> ReadStatTable

Read an SPSS portable `.por` file. The format does not record a row count,
so `filemetadata(tbl).row_count` is `-1`.

$_READ_KWARGS_DOC
"""
read_por(source::Union{AbstractString,IO}; kwargs...) = read_data_file(source, :por; kwargs...)

"""
    read_sas7bdat(path; kwargs...) -> ReadStatTable

Read a SAS `.sas7bdat` data file.

$_READ_KWARGS_DOC
"""
read_sas7bdat(source::Union{AbstractString,IO}; kwargs...) =
    read_data_file(source, :sas7bdat; kwargs...)

"""
    read_xport(path; kwargs...) -> ReadStatTable

Read a SAS transport (XPORT) `.xpt` file. The format does not record a row
count, so `filemetadata(tbl).row_count` is `-1`.

$_READ_KWARGS_DOC
"""
read_xport(source::Union{AbstractString,IO}; kwargs...) =
    read_data_file(source, :xport; kwargs...)

"""
    readstat(path; format=:auto, kwargs...) -> ReadStatTable

Read a stat-package data file, inferring the format from the file extension
(`.dta`, `.sav`/`.zsav`, `.por`, `.sas7bdat`, `.xpt`/`.xport`) unless
`format` is given explicitly (`:dta`, `:sav`, `:por`, `:sas7bdat`,
`:xport`). For `IO` input the format cannot be inferred, so `format` is
required.

$_READ_KWARGS_DOC
"""
readstat(source::Union{AbstractString,IO}; format::Symbol=:auto, kwargs...) =
    read_data_file(source, _sniff_format(source, format); kwargs...)

"""
    read_sas7bcat(path) -> Dict{Symbol, ValueLabelDict}

Read the value-label sets from a SAS `.sas7bcat` catalog file, keyed by
format name. Usually not called directly — pass the catalog path to
`read_sas7bdat(...; catalog=...)` to attach the labels to a data file.
"""
function read_sas7bcat(path::AbstractString)
    pc = ParseContext()
    pc.collect_values = false
    parse_file!(pc, path, :sas7bcat)
    return pc.meta.value_labels
end

"""
    read_meta(path; format=:auto, file_encoding=nothing, handler_encoding=nothing)
        -> ReadStatTable

Read only the metadata of a stat-package data file: the returned table has
zero rows, but its [`filemetadata`](@ref), [`varmetadata`](@ref), and
[`valuelabels`](@ref) are fully populated, including the row count recorded
in the file (`filemetadata(tbl).row_count`). This is much cheaper than
reading the data.
"""
function read_meta(source::Union{AbstractString,IO}; format::Symbol=:auto,
                   file_encoding::Union{Nothing,AbstractString}=nothing,
                   handler_encoding::Union{Nothing,AbstractString}=nothing)
    pc = ParseContext()
    pc.collect_values = false
    # No row limit here: the C library caps the row count it reports at any
    # row limit in effect, and read_meta must report the true count.
    pc.file_encoding = file_encoding === nothing ? nothing : String(file_encoding)
    pc.handler_encoding = handler_encoding === nothing ? nothing : String(handler_encoding)
    fmt = _sniff_format(source, format)
    pc.file_format = fmt
    parse_file!(pc, source, fmt)
    return build_table(pc)
end
