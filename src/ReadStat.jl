module ReadStat

using ReadStat_jll

##############################################################################
##
## Import
##
##############################################################################

using DataValues: DataValueVector
import DataValues
using Dates
import Tables

export ReadStatDataFrame, read_dta, read_sav, read_por, read_sas7bdat, read_xport, write_dta, write_sav, write_por, write_sas7bdat, write_xport

##############################################################################
##
## Julia types that mirror C types
##
##############################################################################

const READSTAT_TYPE_STRING      = Cint(0)
const READSTAT_TYPE_CHAR        = Cint(1)
const READSTAT_TYPE_INT16       = Cint(2)
const READSTAT_TYPE_INT32       = Cint(3)
const READSTAT_TYPE_FLOAT       = Cint(4)
const READSTAT_TYPE_DOUBLE      = Cint(5)
const READSTAT_TYPE_LONG_STRING = Cint(6)

const READSTAT_ERROR_OPEN       = Cint(1)
const READSTAT_ERROR_READ       = Cint(2)
const READSTAT_ERROR_MALLOC     = Cint(3)
const READSTAT_ERROR_USER_ABORT = Cint(4)
const READSTAT_ERROR_PARSE      = Cint(5)

##############################################################################
##
## Pure Julia types
##
##############################################################################

struct ReadStatValue
    union::Int64
    readstat_types_t::Cint
    tag::Cchar
    @static if Sys.iswindows()
        bits::Cuint
    else
        bits::UInt8
    end
end

const Value = ReadStatValue

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

include("C_interface.jl")

##############################################################################
##
## Julia functions
##
##############################################################################

function handle_info!(obs_count::Cint, var_count::Cint, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)
    ds.rows = obs_count
    ds.columns = var_count
    return Cint(0)
end

function handle_metadata!(metadata::Ptr{Nothing}, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)
    ds.filelabel = readstat_get_file_label(metadata)
    ds.timestamp = Dates.unix2datetime(readstat_get_modified_time(metadata))
    ds.format = readstat_get_file_format_version(metadata)
    ds.rows = readstat_get_row_count(metadata)
    ds.columns = readstat_get_var_count(metadata)
    return Cint(0)
end

get_name(variable::Ptr{Nothing}) = Symbol(readstat_variable_get_name(variable))

function get_label(var::Ptr{Nothing})
    ptr = ccall((:readstat_variable_get_label, libreadstat), Cstring, (Ptr{Nothing},), var)
    ptr == C_NULL ? "" : unsafe_string(ptr)
end

function get_format(var::Ptr{Nothing})
    ptr = ccall((:readstat_variable_get_format, libreadstat), Cstring, (Ptr{Nothing},), var)
    ptr == C_NULL ? "" : unsafe_string(ptr)
end

function get_type(data_type::Cint)
    if data_type == READSTAT_TYPE_STRING
        return String
    elseif data_type == READSTAT_TYPE_CHAR
        return Int8
    elseif data_type == READSTAT_TYPE_INT16
        return Int16
    elseif data_type == READSTAT_TYPE_INT32
        return Int32
    elseif data_type == READSTAT_TYPE_FLOAT
        return Float32
    elseif data_type == READSTAT_TYPE_DOUBLE
        return Float64
    end
    return Nothing
end
get_type(variable::Ptr{Nothing}) = get_type(readstat_variable_get_type(variable))

get_storagewidth(variable::Ptr{Nothing}) = readstat_variable_get_storage_width(variable)

get_measure(variable::Ptr{Nothing}) = readstat_variable_get_measure(variable)

get_alignment(variable::Ptr{Nothing}) = readstat_variable_get_measure(variable)

function handle_variable!(var_index::Cint, variable::Ptr{Nothing},
                         val_label::Cstring,  ds_ptr::Ptr{ReadStatDataFrame})
    col = var_index + 1
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame
    missing_count = readstat_variable_get_missing_ranges_count(variable)

    push!(ds.val_label_keys, (val_label == C_NULL ? "" : unsafe_string(val_label)))
    push!(ds.headers, get_name(variable))
    push!(ds.labels, get_label(variable))
    push!(ds.formats, get_format(variable))
    jtype = get_type(variable)
    push!(ds.types, jtype)
    push!(ds.types_as_int, readstat_variable_get_type(variable))
    push!(ds.hasmissings, missing_count > 0)
    # SAS XPORT sets ds.rows == -1
    if ds.rows >= 0
        push!(ds.data, DataValueVector{jtype}(Vector{jtype}(undef, ds.rows), fill(false, ds.rows)))
    else
        push!(ds.data, DataValueVector{jtype}(Vector{jtype}(undef, 0), fill(false, 0)))
    end
    push!(ds.storagewidths, get_storagewidth(variable))
    push!(ds.measures, get_measure(variable))
    push!(ds.alignments, get_alignment(variable))

    return Cint(0)
end

function get_type(val::Value)
    data_type = readstat_value_type(val)
    return [String, Int8, Int16, Int32, Float32, Float64, String][data_type + 1]
end

Base.convert(::Type{Int8}, val::Value) = ccall((:readstat_int8_value, libreadstat), Int8, (Value,), val)
Base.convert(::Type{Int16}, val::Value) = ccall((:readstat_int16_value, libreadstat), Int16, (Value,), val)
Base.convert(::Type{Int32}, val::Value) = ccall((:readstat_int32_value, libreadstat), Int32, (Value,), val)
Base.convert(::Type{Float32}, val::Value) = ccall((:readstat_float_value, libreadstat), Float32, (Value,), val)
Base.convert(::Type{Float64}, val::Value) = ccall((:readstat_double_value, libreadstat), Float64, (Value,), val)
function Base.convert(::Type{String}, val::Value)
    ptr = ccall((:readstat_string_value, libreadstat), Cstring, (Value,), val)
    ptr ≠ C_NULL ? unsafe_string(ptr) : ""
end
as_native(val::Value) = convert(get_type(val), val)

function handle_value!(obs_index::Cint, variable::Ptr{Nothing},
                       value::ReadStatValue, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame
    var_index = readstat_variable_get_index(variable) + 1
    data = ds.data
    @inbounds type_as_int = ds.types_as_int[var_index]

    ismissing = if @inbounds(ds.hasmissings[var_index])
        readstat_value_is_missing(value, variable)
    else
        readstat_value_is_missing(value, C_NULL)
    end

    col = data[var_index]
    @assert eltype(eltype(col)) == get_type(type_as_int)

    if ismissing
        if obs_index < length(col)
            DataValues.unsafe_setindex_isna!(col, true, obs_index + 1)
        else
            push!(col, DataValues.NA)
        end
    else
        readfield!(col, obs_index + 1, value)
    end

    return Cint(0)
end

function readfield!(dest::DataValueVector{String}, row, val::ReadStatValue)
    ptr = ccall((:readstat_string_value, libreadstat), Cstring, (ReadStatValue,), val)

    if row <= length(dest)
        if ptr ≠ C_NULL
            @inbounds DataValues.unsafe_setindex_value!(dest, unsafe_string(ptr), row)
        end
    elseif row == length(dest) + 1
        _val = ptr ≠ C_NULL ? unsafe_string(ptr) : ""
        DataValues.push!(dest, _val)
    else
        throw(ArgumentError("illegal row index: $row"))
    end
end

for (j_type, rs_name) in (
    (Int8,    :readstat_int8_value),
    (Int16,   :readstat_int16_value),
    (Int32,   :readstat_int32_value),
    (Float32, :readstat_float_value),
    (Float64, :readstat_double_value))
    @eval function readfield!(dest::DataValueVector{$j_type}, row, val::ReadStatValue)
        _val = ccall(($(QuoteNode(rs_name)), libreadstat), $j_type, (ReadStatValue,), val)
        if row <= length(dest)
            @inbounds DataValues.unsafe_setindex_value!(dest, _val, row)
        elseif row == length(dest) + 1
            DataValues.push!(dest, _val)
        else
            throw(ArgumentError("illegal row index: $row"))
        end
    end
end

function handle_value_label!(val_labels::Cstring, value::Value, label::Cstring, ds_ptr::Ptr{ReadStatDataFrame})
    val_labels ≠ C_NULL || return Cint(0)
    ds = unsafe_pointer_to_objref(ds_ptr)
    dict = get!(ds.val_label_dict, unsafe_string(val_labels), Dict{Any,String}())
    dict[as_native(value)] = unsafe_string(label)

    return Cint(0)
end

function read_data_file(filename::AbstractString, filetype::Val)
    # initialize ds
    ds = ReadStatDataFrame()
    # initialize parser
    parser = Parser()
    # parse
    parse_data_file!(ds, parser, filename, filetype)
    # return dataframe instead of ReadStatDataFrame
    return ds
end

function Parser()
    parser = ccall((:readstat_parser_init, libreadstat), Ptr{Nothing}, ())
    info_fxn = @cfunction(handle_info!, Cint, (Cint, Cint, Ptr{ReadStatDataFrame}))
    meta_fxn = @cfunction(handle_metadata!, Cint, (Ptr{Nothing}, Ptr{ReadStatDataFrame}))
    var_fxn = @cfunction(handle_variable!, Cint, (Cint, Ptr{Nothing}, Cstring,  Ptr{ReadStatDataFrame}))
    val_fxn = @cfunction(handle_value!, Cint, (Cint, Ptr{Nothing}, ReadStatValue, Ptr{ReadStatDataFrame}))
    label_fxn = @cfunction(handle_value_label!, Cint, (Cstring, Value, Cstring, Ptr{ReadStatDataFrame}))
    ccall((:readstat_set_metadata_handler, libreadstat), Int, (Ptr{Nothing}, Ptr{Nothing}), parser, meta_fxn)
    ccall((:readstat_set_variable_handler, libreadstat), Int, (Ptr{Nothing}, Ptr{Nothing}), parser, var_fxn)
    ccall((:readstat_set_value_handler, libreadstat), Int, (Ptr{Nothing}, Ptr{Nothing}), parser, val_fxn)
    ccall((:readstat_set_value_label_handler, libreadstat), Int, (Ptr{Nothing}, Ptr{Nothing}), parser, label_fxn)
    return parser
end

function error_message(retval::Integer)
    unsafe_string(ccall((:readstat_error_message, libreadstat), Ptr{Cchar}, (Cint,), retval))
end

function parse_data_file!(ds::ReadStatDataFrame, parser::Ptr{Nothing}, filename::AbstractString, filetype::Val)
    retval = readstat_parse(filename, filetype, parser, ds)
    readstat_parser_free(parser)
    retval == 0 ||  error("Error parsing $filename: $(error_message(retval))")
end

function handle_write!(data::Ptr{UInt8}, len::Cint, ctx::Ptr)
    io = unsafe_pointer_to_objref(ctx) # restore io
    actual_data = unsafe_wrap(Array{UInt8}, data, (len, )) # we may want to specify the type later
    write(io, actual_data)
    return len
 end

function Writer(source; file_label="File Label")
    writer = ccall((:readstat_writer_init, libreadstat), Ptr{Nothing}, ())
    write_bytes = @cfunction(handle_write!, Cint, (Ptr{UInt8}, Cint, Ptr{Nothing}))
    ccall((:readstat_set_data_writer, libreadstat), Int, (Ptr{Nothing}, Ptr{Nothing}), writer, write_bytes)
    ccall((:readstat_writer_set_file_label, libreadstat), Cvoid, (Ptr{Nothing}, Cstring), writer, file_label)
    return writer
end

function write_data_file(filename::AbstractString, filetype::Val, source) 
    io = open(filename, "w")
    write_data_file(filetype::Val, io, source)
    close(io)
end


function write_data_file(filetype::Val, io::IO, source)
    writer = Writer(source)

    rows = Tables.rows(source)
    schema = Tables.schema(rows)
    variables_array = []

    variables_array = map(schema.names, schema.types) do column_name, column_type
        readstat_type, storage_width = readstat_column_type_and_width(source, column_name, nonmissingtype(column_type))
        return add_variable!(writer, column_name, readstat_type, storage_width)
        # readstat_variable_set_label(variable, String(field)) TODO: label for a variable
    end


    
    readstat_begin_writing(writer, filetype, io, length(rows))

    for row in rows
        readstat_begin_row(writer)
        Tables.eachcolumn(schema, row) do val, i, name
            insert_value!(writer, variables_array[i], val)
        end
        readstat_end_row(writer);
    end

    ccall((:readstat_end_writing, libreadstat), Int, (Ptr{Nothing},), writer)
    ccall((:readstat_writer_free, libreadstat), Cvoid, (Ptr{Nothing},), writer)
end

readstat_column_type_and_width(_, _, other_type) = error("Cannot handle column with element type $other_type. Is this type supported by ReadStat?")
readstat_column_type_and_width(_, _, ::Type{Float64}) = READSTAT_TYPE_DOUBLE, 0
readstat_column_type_and_width(_, _, ::Type{Float32}) = READSTAT_TYPE_FLOAT, 0
readstat_column_type_and_width(_, _, ::Type{Int32}) = READSTAT_TYPE_INT32, 0
readstat_column_type_and_width(_, _, ::Type{Int16}) = READSTAT_TYPE_INT16, 0
readstat_column_type_and_width(_, _, ::Type{Int8}) = READSTAT_TYPE_CHAR, 0
function readstat_column_type_and_width(source, colname, ::Type{String})
    col = Tables.getcolumn(source, colname)
    maxlen = maximum(col) do str
        str === missing ? 0 : ncodeunits(str)
    end
    if maxlen >= 2045 # maximum length of normal strings
        return READSTAT_TYPE_LONG_STRING, 0
    else
        return READSTAT_TYPE_STRING, maxlen
    end
end

add_variable!(writer, name, type, width = 0) = readstat_add_variable(writer, name, type, width)

insert_value!(writer, variable, value::Float64) = readstat_insert_double_value(writer, variable, value)
insert_value!(writer, variable, value::Float32) = readstat_insert_float_value(writer, variable, value)
insert_value!(writer, variable, ::Missing) = readstat_insert_missing_value(writer, variable)
insert_value!(writer, variable, value::Int8) = readstat_insert_int8_value(writer, variable, value)
insert_value!(writer, variable, value::Int16) = readstat_insert_int16_value(writer, variable, value)
insert_value!(writer, variable, value::Int32) = readstat_insert_int32_value(writer, variable, value)
insert_value!(writer, variable, value::AbstractString) = readstat_insert_string_value(writer, variable, value)

read_dta(filename::AbstractString) = read_data_file(filename, Val(:dta))
read_sav(filename::AbstractString) = read_data_file(filename, Val(:sav))
read_por(filename::AbstractString) = read_data_file(filename, Val(:por))
read_sas7bdat(filename::AbstractString) = read_data_file(filename, Val(:sas7bdat))
read_xport(filename::AbstractString) = read_data_file(filename, Val(:xport))

write_dta(filename::AbstractString, source) = write_data_file(filename, Val(:dta), source)
write_sav(filename::AbstractString, source) = write_data_file(filename, Val(:sav), source)
write_por(filename::AbstractString, source) = write_data_file(filename, Val(:por), source)
write_sas7bdat(filename::AbstractString, source) = write_data_file(filename, Val(:sas7bdat), source)
write_xport(filename::AbstractString, source) = write_data_file(filename, Val(:xport), source)

end #module ReadStat
