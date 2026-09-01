module ReadStat

using DataValues: DataValueVector
import DataValues
using Dates

export ReadStatDataFrame, read_dta, read_sav, read_por, read_sas7bdat, read_xport

public CAPI

"""
    ReadStat.CAPI

Thin wrappers around the public C API of the readstat library (readstat.h,
v1.1.9). Function names, argument order, and semantics follow the C header
one-to-one; C structs are handled as opaque pointers except `ReadStatValue`,
which the C API passes by value. Higher-level functionality lives in the
parent `ReadStat` module — reach for `CAPI` only when the high-level API does
not expose what you need.
"""
module CAPI

using ReadStat_jll: libreadstat

include("capi/enums.jl")
include("capi/value.jl")
include("capi/parser.jl")

end # module CAPI

using .CAPI

# Julia type corresponding to each ReadStatType, indexed by the enum value
# plus one. STRING_REF is a reference into a string table, so it surfaces as
# a String just like STRING does.
const READSTAT_TYPES = (String, Int8, Int16, Int32, Float32, Float64, String)

jltype(t::ReadStatType) = READSTAT_TYPES[Int(t) + 1]

##############################################################################
##
## Result type
##
##############################################################################

mutable struct ReadStatDataFrame
    data::Vector{Any}
    headers::Vector{Symbol}
    types::Vector{DataType}
    labels::Vector{String}
    formats::Vector{String}
    storagewidths::Vector{Csize_t}
    measures::Vector{Cint}
    alignments::Vector{Cint}
    val_label_keys::Vector{String}
    val_label_dict::Dict{String, Dict{Any,String}}
    rows::Int
    columns::Int
    filelabel::String
    timestamp::DateTime
    format::Clong
    types_as_int::Vector{Cint}
    hasmissings::Vector{Bool}

    ReadStatDataFrame() =
        new(Any[], Symbol[], DataType[], String[], String[], Csize_t[], Cint[], Cint[],
        String[], Dict{String, Dict{Any,String}}(), 0, 0, "", Dates.unix2datetime(0), 0, Cint[], Bool[])
end

##############################################################################
##
## Parse handlers
##
##############################################################################

function handle_metadata!(metadata::MetadataPtr, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame
    ds.filelabel = readstat_get_file_label(metadata)
    ds.timestamp = Dates.unix2datetime(readstat_get_modified_time(metadata))
    ds.format = readstat_get_file_format_version(metadata)
    ds.rows = readstat_get_row_count(metadata)
    ds.columns = readstat_get_var_count(metadata)
    return READSTAT_HANDLER_OK
end

function handle_variable!(var_index::Cint, variable::VariablePtr,
                          val_label::Cstring, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame
    missing_count = readstat_variable_get_missing_ranges_count(variable)

    push!(ds.val_label_keys, val_label == C_NULL ? "" : unsafe_string(val_label))
    push!(ds.headers, Symbol(readstat_variable_get_name(variable)))
    push!(ds.labels, readstat_variable_get_label(variable))
    push!(ds.formats, readstat_variable_get_format(variable))
    ctype = readstat_variable_get_type(variable)
    T = jltype(ctype)
    push!(ds.types, T)
    push!(ds.types_as_int, Cint(Int(ctype)))
    push!(ds.hasmissings, missing_count > 0)
    # XPORT and POR report an unknown row count as -1.
    if ds.rows >= 0
        push!(ds.data, DataValueVector{T}(Vector{T}(undef, ds.rows), fill(false, ds.rows)))
    else
        push!(ds.data, DataValueVector{T}(Vector{T}(undef, 0), fill(false, 0)))
    end
    push!(ds.storagewidths, readstat_variable_get_storage_width(variable))
    push!(ds.measures, Cint(Int(readstat_variable_get_measure(variable))))
    push!(ds.alignments, Cint(Int(readstat_variable_get_alignment(variable))))

    return READSTAT_HANDLER_OK
end

function as_native(val::ReadStatValue)
    t = readstat_value_type(val)
    if t == READSTAT_TYPE_INT8
        return readstat_int8_value(val)
    elseif t == READSTAT_TYPE_INT16
        return readstat_int16_value(val)
    elseif t == READSTAT_TYPE_INT32
        return readstat_int32_value(val)
    elseif t == READSTAT_TYPE_FLOAT
        return readstat_float_value(val)
    elseif t == READSTAT_TYPE_DOUBLE
        return readstat_double_value(val)
    else
        ptr = readstat_string_value(val)
        return ptr == C_NULL ? "" : unsafe_string(ptr)
    end
end

function handle_value!(obs_index::Cint, variable::VariablePtr,
                       value::ReadStatValue, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame
    var_index = readstat_variable_get_index(variable) + 1
    data = ds.data

    ismissing = if @inbounds(ds.hasmissings[var_index])
        readstat_value_is_missing(value, variable)
    else
        readstat_value_is_missing(value, C_NULL)
    end

    col = data[var_index]

    if ismissing
        if obs_index < length(col)
            DataValues.unsafe_setindex_isna!(col, true, obs_index + 1)
        else
            push!(col, DataValues.NA)
        end
    else
        readfield!(col, obs_index + 1, value)
    end

    return READSTAT_HANDLER_OK
end

function readfield!(dest::DataValueVector{String}, row, val::ReadStatValue)
    ptr = readstat_string_value(val)

    if row <= length(dest)
        if ptr != C_NULL
            @inbounds DataValues.unsafe_setindex_value!(dest, unsafe_string(ptr), row)
        end
    elseif row == length(dest) + 1
        push!(dest, ptr != C_NULL ? unsafe_string(ptr) : "")
    else
        throw(ArgumentError("illegal row index: $row"))
    end
end

for (T, value_fn) in ((Int8, :readstat_int8_value),
                      (Int16, :readstat_int16_value),
                      (Int32, :readstat_int32_value),
                      (Float32, :readstat_float_value),
                      (Float64, :readstat_double_value))
    @eval function readfield!(dest::DataValueVector{$T}, row, val::ReadStatValue)
        _val = $value_fn(val)
        if row <= length(dest)
            @inbounds DataValues.unsafe_setindex_value!(dest, _val, row)
        elseif row == length(dest) + 1
            push!(dest, _val)
        else
            throw(ArgumentError("illegal row index: $row"))
        end
    end
end

function handle_value_label!(val_labels::Cstring, value::ReadStatValue, label::Cstring,
                             ds_ptr::Ptr{ReadStatDataFrame})
    val_labels != C_NULL || return READSTAT_HANDLER_OK
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame
    dict = get!(ds.val_label_dict, unsafe_string(val_labels), Dict{Any,String}())
    dict[as_native(value)] = unsafe_string(label)

    return READSTAT_HANDLER_OK
end

##############################################################################
##
## Parse driver
##
##############################################################################

function Parser()
    parser = readstat_parser_init()
    meta_fxn = @cfunction(handle_metadata!, Cint, (MetadataPtr, Ptr{ReadStatDataFrame}))
    var_fxn = @cfunction(handle_variable!, Cint, (Cint, VariablePtr, Cstring, Ptr{ReadStatDataFrame}))
    val_fxn = @cfunction(handle_value!, Cint, (Cint, VariablePtr, ReadStatValue, Ptr{ReadStatDataFrame}))
    label_fxn = @cfunction(handle_value_label!, Cint, (Cstring, ReadStatValue, Cstring, Ptr{ReadStatDataFrame}))
    readstat_set_metadata_handler(parser, meta_fxn)
    readstat_set_variable_handler(parser, var_fxn)
    readstat_set_value_handler(parser, val_fxn)
    readstat_set_value_label_handler(parser, label_fxn)
    return parser
end

readstat_parse(parser, path, ::Val{:dta}, ctx) = CAPI.readstat_parse_dta(parser, path, ctx)
readstat_parse(parser, path, ::Val{:sav}, ctx) = CAPI.readstat_parse_sav(parser, path, ctx)
readstat_parse(parser, path, ::Val{:por}, ctx) = CAPI.readstat_parse_por(parser, path, ctx)
readstat_parse(parser, path, ::Val{:sas7bdat}, ctx) = CAPI.readstat_parse_sas7bdat(parser, path, ctx)
readstat_parse(parser, path, ::Val{:xport}, ctx) = CAPI.readstat_parse_xport(parser, path, ctx)

function read_data_file(filename::AbstractString, filetype::Val)
    ds = ReadStatDataFrame()
    parser = Parser()
    local retval
    try
        retval = readstat_parse(parser, filename, filetype, ds)
    finally
        readstat_parser_free(parser)
    end
    retval == READSTAT_OK || error("Error parsing $filename: $(readstat_error_message(retval))")
    return ds
end

read_dta(filename::AbstractString) = read_data_file(filename, Val(:dta))
read_sav(filename::AbstractString) = read_data_file(filename, Val(:sav))
read_por(filename::AbstractString) = read_data_file(filename, Val(:por))
read_sas7bdat(filename::AbstractString) = read_data_file(filename, Val(:sas7bdat))
read_xport(filename::AbstractString) = read_data_file(filename, Val(:xport))

end # module ReadStat
