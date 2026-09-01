# Parse driver and the public read entry points.

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
    else
        throw(ArgumentError("unknown format $format"))
    end
end

function parse_file!(pc::ParseContext, path::AbstractString, format::Symbol)
    isfile(path) || throw(ArgumentError("file not found: $path"))
    parser = readstat_parser_init()
    local retval
    try
        readstat_set_metadata_handler(parser, CF_METADATA[])
        readstat_set_variable_handler(parser, CF_VARIABLE[])
        readstat_set_value_handler(parser, CF_VALUE[])
        readstat_set_value_label_handler(parser, CF_VALUE_LABEL[])
        retval = _parse_format(parser, path, format, pc)
    finally
        readstat_parser_free(parser)
    end
    if pc.err !== nothing
        e, _ = pc.err
        throw(e)
    end
    retval == READSTAT_OK ||
        error("Error parsing $path: $(readstat_error_message(retval))")
    return pc
end

function build_table(pc::ParseContext)
    n = length(pc.names)
    columns = Vector{AbstractVector}(undef, n)
    for i in 1:n
        columns[i] = finalize_column(pc.cols, i)
    end
    return ReadStatTable(columns, pc.names, pc.meta, pc.varmeta)
end

function read_data_file(path::AbstractString, format::Symbol)
    pc = ParseContext()
    parse_file!(pc, path, format)
    return build_table(pc)
end

"""
    read_dta(path) -> ReadStatTable

Read a Stata `.dta` file. See [`ReadStatTable`](@ref) for how to access the
data and metadata.
"""
read_dta(path::AbstractString) = read_data_file(path, :dta)

"""
    read_sav(path) -> ReadStatTable

Read an SPSS `.sav` (or `.zsav`) file.
"""
read_sav(path::AbstractString) = read_data_file(path, :sav)

"""
    read_por(path) -> ReadStatTable

Read an SPSS portable `.por` file. The format does not record a row count,
so `filemetadata(tbl).row_count` is `-1`.
"""
read_por(path::AbstractString) = read_data_file(path, :por)

"""
    read_sas7bdat(path) -> ReadStatTable

Read a SAS `.sas7bdat` data file.
"""
read_sas7bdat(path::AbstractString) = read_data_file(path, :sas7bdat)

"""
    read_xport(path) -> ReadStatTable

Read a SAS transport (XPORT) `.xpt` file. The format does not record a row
count, so `filemetadata(tbl).row_count` is `-1`.
"""
read_xport(path::AbstractString) = read_data_file(path, :xport)
