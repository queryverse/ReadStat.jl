module ReadStat

if isfile(joinpath(dirname(@__FILE__),"..","deps","deps.jl"))
    include("../deps/deps.jl")
else
    error("ReadStat not properly installed. Please run Pkg.build(\"ReadStat\")")
end

##############################################################################
##
## Import
##
##############################################################################

using DataValues.DataValueVector

export ReadStatDataFrame, read_dta, read_sav, read_por, read_sas7bdat

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
    @static if is_windows()
        bits::Cuint
    else
        bits::UInt8
    end
end

mutable struct ReadStatDataFrame
    data::Vector{Any}
    headers::Vector{Symbol}
    types::Vector{DataType}
    labels::Vector{String}
    formats::Vector{String}
    storagewidths::Vector{Csize_t}
    measures::Vector{Cint}
    alignments::Vector{Cint}
    value_labels::Vector{Dict{Any,String}}
    rows::Int
    columns::Int
    filelabel::String
    timestamp::DateTime
    format::Clong

    ReadStatDataFrame() = 
        new(Any[], Symbol[], DataType[], String[], String[], Csize_t[], Cint[], Cint[],
        Dict{Any,String}[], 0, 0, "", Dates.unix2datetime(0), 0)
end

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

function handle_metadata!(file_label::Cstring, timestamp::Int, format::Clong, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)
    ds.filelabel = unsafe_string(file_label)
    ds.timestamp = Dates.unix2datetime(timestamp)
    ds.format = format
    return Cint(0)
end

get_name(var::Ptr{Void}) = Symbol(unsafe_string(ccall((:readstat_variable_get_name, libreadstat),
                                  Cstring, (Ptr{Void},), var)))

function get_label(var::Ptr{Void})
    ptr = ccall((:readstat_variable_get_label, libreadstat), Cstring, (Ptr{Void},), var)
    ptr == C_NULL ? "" : unsafe_string(ptr)
end

function get_format(var::Ptr{Void})
    ptr = ccall((:readstat_variable_get_format, libreadstat), Cstring, (Ptr{Void},), var)
    ptr == C_NULL ? "" : unsafe_string(ptr)
end

function get_type(var::Ptr{Void})
    data_type = ccall((:readstat_variable_get_type, libreadstat), Cint, (Ptr{Void},), var)
   
    if data_type == READSTAT_TYPE_STRING
        String
    elseif data_type == READSTAT_TYPE_CHAR
        Int8
    elseif data_type == READSTAT_TYPE_INT16
        Int16
    elseif data_type == READSTAT_TYPE_INT32
        Int32
    elseif data_type == READSTAT_TYPE_FLOAT
        Float32
    elseif data_type == READSTAT_TYPE_DOUBLE
        Float64
    elseif data_type == READSTAT_TYPE_LONG_STRING
        Void
    else
        Void
    end
end

get_storagewidth(var::Ptr{Void}) = ccall((:readstat_variable_get_storage_width, libreadstat),
                                         Csize_t, (Ptr{Void},), var)

get_measure(var::Ptr{Void}) = ccall((:readstat_variable_get_measure, libreadstat), Cint, (Ptr{Void},), var)

get_alignment(var::Ptr{Void}) = ccall((:readstat_variable_get_alignment, libreadstat), Cint, (Ptr{Void},), var)

function handle_variable!(var_index::Cint, variable::Ptr{Void}, 
                         variable_label::Cstring,  ds_ptr::Ptr{ReadStatDataFrame})
    col = var_index + 1
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame

    push!(ds.headers, get_name(variable))
    push!(ds.labels, get_label(variable))
    push!(ds.formats, get_format(variable))
    jtype = get_type(variable)
    push!(ds.types, jtype)
    push!(ds.data, DataValueVector{jtype}(ds.rows))
    push!(ds.storagewidths, get_storagewidth(variable))
    push!(ds.measures, get_measure(variable))
    push!(ds.alignments, get_alignment(variable))
    
    return Cint(0)
end

const Value = ReadStatValue

val_ismissing(val::Value) = ccall((:readstat_value_is_missing, libreadstat), Bool, (Value,), val)
function handle_value!(obs_index::Cint, var_index::Cint, 
                       value::Value, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)
    if !val_ismissing(value)
        readfield!(ds.data[var_index + 1], obs_index + 1, value)
    end
    
    return Cint(0)
end

function readfield!(dest::DataValueVector{String}, row, val::Value)
    ptr = ccall((:readstat_string_value, libreadstat), Cstring, (Value,), val)
    if ptr ≠ C_NULL
        @inbounds dest[row] = unsafe_string(ptr)
    end
end

function readfield!(dest::DataValueVector{Int8}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_int8_value, libreadstat), Int8, (Value,), val)
end

function readfield!(dest::DataValueVector{Int16}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_int16_value, libreadstat), Int16, (Value,), val)
end

function readfield!(dest::DataValueVector{Int32}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_int32_value, libreadstat), Int32, (Value,), val)
end

function readfield!(dest::DataValueVector{Float64}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_double_value, libreadstat), Float64, (Value,), val)
end

function readfield!(dest::DataValueVector{Float32}, row, val::Value)
    @inbounds dest[row] = ccall((:readstat_float_value, libreadstat), Float32, (Value,), val)
end

function handle_value_label!(val_labels::Cstring, value::Value, label::Cstring, ds_ptr::Ptr{ReadStatDataFrame})
    return Cint(0)
end

function read_data_file(filename::AbstractString, filetype::Type)
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
    parser = ccall((:readstat_parser_init, libreadstat), Ptr{Void}, ())
    const info_fxn = cfunction(handle_info!, Cint, (Cint, Cint, Ptr{ReadStatDataFrame}))
    const var_fxn = cfunction(handle_variable!, Cint, (Cint, Ptr{Void}, Cstring,  Ptr{ReadStatDataFrame}))
    const val_fxn = cfunction(handle_value!, Cint, (Cint, Cint, Value, Ptr{ReadStatDataFrame}))
    const label_fxn = cfunction(handle_value_label!, Cint, (Cstring, Value, Cstring, Ptr{ReadStatDataFrame}))
    ccall((:readstat_set_info_handler, libreadstat), Int, (Ptr{Void}, Ptr{Void}), parser, info_fxn)
    ccall((:readstat_set_variable_handler, libreadstat), Int, (Ptr{Void}, Ptr{Void}), parser, var_fxn)
    ccall((:readstat_set_value_handler, libreadstat), Int, (Ptr{Void}, Ptr{Void}), parser, val_fxn)
    ccall((:readstat_set_value_label_handler, libreadstat), Int, (Ptr{Void}, Ptr{Void}), parser, label_fxn)
    return parser
end  

for f in (:dta, :sav, :por, :sas7bdat) 
    valtype = Val{f}
    # call respective parser
    @eval begin
        function parse_data_file!(ds::ReadStatDataFrame, parser, 
            filename::AbstractString, filetype::Type{$valtype})
            retval = ccall(($(string(:readstat_parse_, f)), libreadstat), 
                        Int, (Ptr{Void}, Cstring, Any),
                        parser, string(filename), ds)
            ccall((:readstat_parser_free, libreadstat), Void, (Ptr{Void},), parser)
            retval == 0 ||  error("Error parsing $filename: $retval")
        end
    end
end

for f in (:dta, :sav, :por, :sas7bdat) 
    valtype = Val{f}
    # define read_dta that calls read(.., val{:dta}))
    @eval $(Symbol(:read_, f))(filename::AbstractString) = read_data_file(filename, $valtype)
end


end #module ReadStat
