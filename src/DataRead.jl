module DataRead

using DataArrays
import DataFrames: DataFrame

export read_dta, read_sav, read_por, read_sas7bdat


##############################################################################
##
## Julia types that mirror C types
##
##############################################################################

const READSTAT_TYPE_STRING      = 0
const READSTAT_TYPE_CHAR        = 1
const READSTAT_TYPE_INT16       = 2
const READSTAT_TYPE_INT32       = 3
const READSTAT_TYPE_FLOAT       = 4
const READSTAT_TYPE_DOUBLE      = 5
const READSTAT_TYPE_LONG_STRING = 6

const READSTAT_ERROR_OPEN       = 1
const READSTAT_ERROR_READ       = 2
const READSTAT_ERROR_MALLOC     = 3
const READSTAT_ERROR_USER_ABORT = 4
const READSTAT_ERROR_PARSE      = 5

immutable DataReadValue
    v::Cdouble
    readstat_types_t::Cint
    is_system_missing::Cint  
    is_considered_missing::Cint       
end

function get_type(value::DataReadValue)
    ccall((:readstat_value_type, "libreadstat"), Cint, (DataReadValue,), value)
end
function get_ismissing(value::DataReadValue)
    ccall((:readstat_value_is_missing, "libreadstat"), Cint, (DataReadValue,), value)
end


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
    ccall((:readstat_variable_get_type, "libreadstat"), Cint, (Ptr{DataReadVariable},), variable)
end


##############################################################################
##
## Pure Julia type
##
## Note: ctx.colnames[index+1] is not type stable
## Performance wise, use something like in https://github.com/quinnj/CSV.jl
##
##############################################################################

type DataReadCtx
    nrows::Int
    colnames::Vector{Symbol}
    columns::Vector{Any}
end
DataReadCtx() = DataReadCtx(0, Array(Symbol, (0,)), Array(Any, (0,)))
DataFrame(ctx::DataReadCtx) = DataFrame(ctx.columns, ctx.colnames)

##############################################################################
##
## Pure Julia functions
##
##############################################################################

function handle_info!(obs_count::Cint, var_count::Cint, ctx_ptr::Ptr{DataReadCtx})
    nrows = convert(Int, obs_count)
    ncols = convert(Int, var_count)
    colnames = Array(Symbol, (ncols,))
    columns = Array(Any, (ncols,))

    ctx = unsafe_pointer_to_objref(ctx_ptr)
    ctx.nrows = nrows
    ctx.colnames = colnames
    ctx.columns = columns

    return convert(Cint, 0)
end

function handle_variable!(index::Cint, variable::Ptr{DataReadVariable}, variable_label::Cstring,  ctx_ptr::Ptr{DataReadCtx})

    name_str = get_name(variable)
    data_type = get_type(variable)

    ctx = unsafe_pointer_to_objref(ctx_ptr)::DataReadCtx
    ctx.colnames[index+1] = convert(Symbol, name_str)

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
    ctx.columns[index+1] = DataArray(jtype, (ctx.nrows,))
    return convert(Cint, 0)
end

function handle_value!(obs_index::Cint, var_index::Cint, value::DataReadValue, ctx_ptr::Ptr{DataReadCtx})
 
    jvalue = NA
    data_type = get_type(value)
    vmissing = get_ismissing(value)
    # starts to goes wrong here
    @show data_type
    @show vmissing
    @show value
    @show reinterpret(Float64, value.v)

    # this produces segault
    #  unsafe_pointer_to_objref(ctx_ptr)::DataReadCtx
    if vmissing != 0
        if data_type == READSTAT_TYPE_STRING
            jvalue = reinterpret(Ptr{UInt8}, value.v)
        elseif data_type == READSTAT_TYPE_CHAR
            jvalue = reinterpret(UInt8, value.v)
        elseif data_type == READSTAT_TYPE_INT16
            jvalue = reinterpret(Int16, value.v)
        elseif data_type == READSTAT_TYPE_INT32
            jvalue = reinterpret(Int32, value.v)
        elseif data_type == READSTAT_TYPE_FLOAT
            jvalue = reinterpret(Float32, value.v)
        elseif data_type == READSTAT_TYPE_DOUBLE
            jvalue =  reinterpret(Float64, value.v)
        end
    end
    return convert(Cint, 0)
end

function handle_value_label!(val_labels::Cstring, value::DataReadValue, label::Cstring, ctx_ptr::Ptr{DataReadCtx})
    ctx = unsafe_pointer_to_objref(ctx_ptr)
    return convert(Cint, 0)
end

function read_data_file(filename::ASCIIString, filetype::Type)
    # initialize ctx
    ctx = DataReadCtx()
    # initialize parser
    parser = Parser()
    # parse
    parse_data_file!(ctx, parser, filename, filetype)
    # return dataframe
    return DataFrame(ctx)
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
    const info_fxn = cfunction(handle_info!, Cint, (Cint, Cint, Ptr{DataReadCtx}))
    const var_fxn = cfunction(handle_variable!, Cint, (Cint, Ptr{DataReadVariable}, Cstring,  Ptr{DataReadCtx}))
    const val_fxn = cfunction(handle_value!, Cint, (Cint, Cint, DataReadValue, Ptr{DataReadCtx}))
    const label_fxn = cfunction(handle_value_label!, Cint, (Cstring, DataReadValue, Cstring, Ptr{DataReadCtx}))
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
        function parse_data_file!(ctx::DataReadCtx, parser, 
            filename::ASCIIString, filetype::Type{$valtype})
            retval = ccall(($(string(:readstat_parse_, f)), "libreadstat"), 
                        Int, (Ptr{Void}, Ptr{UInt8}, Ptr{DataReadCtx}),
                        parser, bytestring(filename), pointer_from_objref(ctx))
            ccall( (:readstat_parser_free, "libreadstat"), Void, (Ptr{Void},), parser)
            retval == 0 ||  error("Error parsing $filename: $retval")
        end
    end
end


end #module DataRead
