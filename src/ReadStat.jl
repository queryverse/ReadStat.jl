module ReadStat

# Load libreadstat from our deps.jl
const depsjl_path = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if !isfile(depsjl_path)
    error("ReadStat not installed properly, run Pkg.build(\"ReadStat\"), restart Julia and try again.")
end
include(depsjl_path)

function __init__()
    check_deps()
end


##############################################################################
##
## Import
##
##############################################################################

import DataValues: DataValueVector, DataValueArray

export read_dta, read_sav, read_por, read_sas7bdat

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

# actually not used
function get_type(value::ReadStatValue)
    ccall((:readstat_value_type, libreadstat), Cint, (ReadStatValue,), value)
end
function get_ismissing(value::ReadStatValue)
    ccall((:readstat_value_is_missing, libreadstat), Cint, (ReadStatValue,), value)
end


# Define ReadStatVariable to dispatch on get_type.
# Define the type while we're at it
struct ReadStatMissingness
    missing_ranges::ReadStatValue
    missing_ranges_count::Clong
end

struct ReadStatVariable
    readstat_types_t::Cint
    index::Cint
    name::Ptr{UInt8}
    format::Ptr{UInt8}
    label::Ptr{UInt8}
    label_set::Ptr{Void}
    offset::Int64
    width::Csize_t
    user_width::Csize_t
    missingness::ReadStatMissingness 
end

function get_name(variable::Ptr{ReadStatVariable})
    name = ccall((:readstat_variable_get_name, libreadstat), Ptr{UInt8}, (Ptr{ReadStatVariable},), variable)
    return unsafe_string(name)
end

function get_type(variable::Ptr{ReadStatVariable})
    ccall((:readstat_variable_get_type, libreadstat), Cint, (Ptr{ReadStatVariable},), variable)::Cint
end

##############################################################################
##
## Pure Julia types
##
##############################################################################

mutable struct ReadStatDataFrame
    data::Vector{Any}
    header::Vector{Symbol}
    types::Vector{DataType}
    rows::Int

    ReadStatDataFrame() = new(Any[], Symbol[], DataType[], 0)
end

##############################################################################
##
## Julia functions
##
##############################################################################

function handle_info!(obs_count::Cint, var_count::Cint, ds_ptr::Ptr{ReadStatDataFrame})
    ds = unsafe_pointer_to_objref(ds_ptr)
    ds.rows = convert(Int, obs_count)
    return Cint(0)
end

function handle_variable!(var_index::Cint, variable::Ptr{ReadStatVariable}, 
                        variable_label::Cstring,  ds_ptr::Ptr{ReadStatDataFrame})
    col = var_index + 1
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame

    name_str = get_name(variable)
    push!(ds.header, convert(Symbol, name_str))

    data_type = get_type(variable)
    jtype = Float64
    if data_type == READSTAT_TYPE_STRING
        jtype = String
    elseif data_type == READSTAT_TYPE_CHAR
        jtype = Int8
    elseif data_type == READSTAT_TYPE_INT16
        jtype = Int16
    elseif data_type == READSTAT_TYPE_INT32
        jtype = Int32
    elseif data_type == READSTAT_TYPE_FLOAT
        jtype = Float32
    elseif data_type == READSTAT_TYPE_DOUBLE
        jtype = Float64
    end
    push!(ds.types, jtype)

    push!(ds.data, DataValueVector{jtype}(ds.rows))
    
    return Cint(0)
end

function handle_value!(obs_index::Cint, var_index::Cint, 
                        value::ReadStatValue, ds_ptr::Ptr{ReadStatDataFrame})
    col = var_index + 1
    row = obs_index + 1
    ds = unsafe_pointer_to_objref(ds_ptr)::ReadStatDataFrame

    if get_ismissing(value) == 0
        readfield!(ds.data[col], row, col, value.union)
    end
    
    return Cint(0)
end

function readfield!(dest::DataValueVector{String}, row, col, val)
    val = unsafe_string(reinterpret(Ptr{Int8}, val % Csize_t))
    @inbounds dest[row] = val
end

function readfield!(dest::DataValueVector{T}, row, col, val) where {T <: Integer}
    @inbounds dest[row] = val
end

function readfield!(dest::DataValueVector{Float64}, row, col, val)
    @inbounds dest[row] = reinterpret(Float64, val)
end

function readfield!(dest::DataValueVector{Float32}, row, col, val)
    @inbounds dest[row] = reinterpret(Float32, val % Int32)
end

function handle_value_label!(val_labels::Cstring, value::ReadStatValue, label::Cstring, ds_ptr::Ptr{ReadStatDataFrame})
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
    return ds.data, ds.header
end

function Parser()
    parser = ccall((:readstat_parser_init, libreadstat), Ptr{Void}, ())
    const info_fxn = cfunction(handle_info!, Cint, (Cint, Cint, Ptr{ReadStatDataFrame}))
    const var_fxn = cfunction(handle_variable!, Cint, (Cint, Ptr{ReadStatVariable}, Cstring,  Ptr{ReadStatDataFrame}))
    const val_fxn = cfunction(handle_value!, Cint, (Cint, Cint, ReadStatValue, Ptr{ReadStatDataFrame}))
    const label_fxn = cfunction(handle_value_label!, Cint, (Cstring, ReadStatValue, Cstring, Ptr{ReadStatDataFrame}))
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
                        Int, (Ptr{Void}, Ptr{UInt8}, Any),
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
