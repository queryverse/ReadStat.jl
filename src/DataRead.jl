module DataRead
using NullableArrays
using DataStreams
using DataFrames

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

immutable DataReadValue
    union::Int64
    readstat_types_t::Cint
    tag::Cchar
    bits::UInt8
end

# actually not used
function get_type(value::DataReadValue)
    ccall((:readstat_value_type, "libreadstat"), Cint, (DataReadValue,), value)
end
function get_ismissing(value::DataReadValue)
    ccall((:readstat_value_is_missing, "libreadstat"), Cint, (DataReadValue,), value)
end


# Define DataReadVariable to dispatch on get_type.
# Define the type while we're at it
immutable DataReadMissingness
    missing_ranges::DataReadValue
    missing_ranges_count::Clong
end

immutable DataReadVariable
    readstat_types_t::Cint
    index::Cint
    name::Ptr{UInt8}
    format::Ptr{UInt8}
    label::Ptr{UInt8}
    label_set::Ptr{Void}
    offset::Coff_t
    width::Csize_t
    user_width::Csize_t
    missingness::DataReadMissingness 
end

function get_name(variable::Ptr{DataReadVariable})
    name = ccall((:readstat_variable_get_name, "libreadstat"), Ptr{UInt8}, (Ptr{DataReadVariable},), variable)
    return bytestring(name)
end

function get_type(variable::Ptr{DataReadVariable})
    ccall((:readstat_variable_get_type, "libreadstat"), Cint, (Ptr{DataReadVariable},), variable)::Cint
end

##############################################################################
##
## Pure Julia functions
##
##############################################################################

function handle_info!(obs_count::Cint, var_count::Cint, ds_ptr::Ptr{DataStream})
    ds = unsafe_pointer_to_objref(ds_ptr)
    ds.schema.rows = convert(Int, obs_count)
    ds.schema.cols = convert(Int, var_count)
    ds.schema.header = Array(UTF8String, var_count)
    ds.schema.types = Array(DataType, var_count)
    return Cint(0)
end

function handle_variable!(var_index::Cint, variable::Ptr{DataReadVariable}, 
                        variable_label::Cstring,  ds_ptr::Ptr{DataStream})
    col = var_index + 1
    ds = unsafe_pointer_to_objref(ds_ptr)::DataStream

    name_str = get_name(variable)
    data_type = get_type(variable)
    ds.schema.header[col] = convert(UTF8String, name_str)

    jtype = Float64
    if data_type == READSTAT_TYPE_STRING
        jtype = ASCIIString
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
    ds.schema.types[col] = jtype
    push!(ds.data, NullableArray(jtype, ds.schema.rows))
    return Cint(0)
end

function handle_value!(obs_index::Cint, var_index::Cint, 
                        value::DataReadValue, ds_ptr::Ptr{DataStream})
    col = var_index + 1
    row = obs_index + 1
    ds = unsafe_pointer_to_objref(ds_ptr)::DataStream

    if get_ismissing(value) == 1
        readfield!(ds.data[col], row, col)
    else
        readfield!(ds.data[col], row, col, value.union)
    end
    return Cint(0)
end

function readfield!(dest::NullableVector, row, col)
    @inbounds dest.values[row] = true
end

function readfield!(dest::NullableVector{ASCIIString}, row, col, val)
    val = bytestring(reinterpret(Ptr{Int8}, val))
    @inbounds dest.values[row], dest.isnull[row] = val, false
end

function readfield!{T <: Integer}(dest::NullableVector{T}, row, col, val)
    @inbounds dest.values[row], dest.isnull[row] = val, false
end

function readfield!{T <: AbstractFloat}(dest::NullableVector{T}, row, col, val)
    @inbounds dest.values[row], dest.isnull[row] = reinterpret(Float64, val), false
end

function handle_value_label!(val_labels::Cstring, value::DataReadValue, label::Cstring, ds_ptr::Ptr{DataStream})
    return Cint(0)
end

function read_data_file(filename::ASCIIString, filetype::Type)
    # initialize ds
    ds = DataStream(Schema(DataType[]))
    # initialize parser
    parser = Parser()
    # parse
    parse_data_file!(ds, parser, filename, filetype)
    # return dataframe instead of DataStream
    return DataFrame(convert(Vector{Any},ds.data), Symbol[symbol(x) for x in ds.schema.header])
end

for f in (:dta, :sav, :por, :sas7bdat) 
    valtype = Val{f}
    # define read_dta that calls read(.., val{:dta}))
    @eval $(symbol(:read_, f))(filename::ASCIIString) = read_data_file(filename, $valtype)
end

##############################################################################
##
## Link to C functions
##
##############################################################################

function Parser()
    parser = ccall( (:readstat_parser_init, "libreadstat"), Ptr{Void}, ())
    const info_fxn = cfunction(handle_info!, Cint, (Cint, Cint, Ptr{DataStream}))
    const var_fxn = cfunction(handle_variable!, Cint, (Cint, Ptr{DataReadVariable}, Cstring,  Ptr{DataStream}))
    const val_fxn = cfunction(handle_value!, Cint, (Cint, Cint, DataReadValue, Ptr{DataStream}))
    const label_fxn = cfunction(handle_value_label!, Cint, (Cstring, DataReadValue, Cstring, Ptr{DataStream}))
    ccall( (:readstat_set_info_handler, "libreadstat"), Int, (Ptr{Void}, Ptr{Void}), parser, info_fxn)
    ccall( (:readstat_set_variable_handler, "libreadstat"), Int, (Ptr{Void}, Ptr{Void}), parser, var_fxn)
    ccall( (:readstat_set_value_handler, "libreadstat"), Int, (Ptr{Void}, Ptr{Void}), parser, val_fxn)
    ccall( (:readstat_set_value_label_handler, "libreadstat"), Int, (Ptr{Void}, Ptr{Void}), parser, label_fxn)
    return parser
end  

for f in (:dta, :sav, :por, :sas7bdat) 
    valtype = Val{f}
    # call respective parser
    @eval begin
        function parse_data_file!(ds::DataStream, parser, 
            filename::ASCIIString, filetype::Type{$valtype})
            retval = ccall(($(string(:readstat_parse_, f)), "libreadstat"), 
                        Int, (Ptr{Void}, Ptr{UInt8}, Any),
                        parser, bytestring(filename), ds)
            ccall( (:readstat_parser_free, "libreadstat"), Void, (Ptr{Void},), parser)
            retval == 0 ||  error("Error parsing $filename: $retval")
        end
    end
end


end #module DataRead
