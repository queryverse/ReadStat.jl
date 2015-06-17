module DataRead

using DataArrays
using DataFrames

export read_dta, read_sav, read_por, read_sas7bdat

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

type DataReadCtx
    nrows::Int
    colnames::Vector{Symbol}
    columns::Vector{Any}
end

function handle_info(obs_count::Cint, var_count::Cint, ctx_ptr::Ptr{Void})
    nrows = convert(Int, obs_count)
    ncols = convert(Int, var_count)
    colnames = Array(Symbol, (ncols,))
    columns = Array(Any, (ncols,))

    ctx = unsafe_pointer_to_objref(ctx_ptr)::DataReadCtx
    ctx.nrows = nrows
    ctx.colnames = colnames
    ctx.columns = columns

    return convert(Cint, 0)
end

function handle_variable(index::Cint, name::Ptr{Int8}, format::Ptr{Int8}, label::Ptr{Int8},
    value_labels::Ptr{Int8}, data_type::Cint, ctx_ptr::Ptr{Void})

    ctx = unsafe_pointer_to_objref(ctx_ptr)::DataReadCtx
    name_str = bytestring(name)
    ctx.colnames[index+1] = convert(Symbol, name_str)

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
    ctx.columns[index+1] = DataArray(jtype, (ctx.nrows,))

    return convert(Cint, 0)
end

function handle_value(obs_index::Cint, var_index::Cint, value::Ptr{Void}, data_type::Cint, ctx_ptr::Ptr{Void})
    ctx = unsafe_pointer_to_objref(ctx_ptr)::DataReadCtx
    jvalue = NA
    if value != convert(Ptr{Void}, 0)
        if data_type == READSTAT_TYPE_STRING
            jvalue = bytestring(convert(Ptr{Int8}, value))
        elseif data_type == READSTAT_TYPE_CHAR
            jvalue = pointer_to_array(convert(Ptr{Int8}, value), (1,))[1]
        elseif data_type == READSTAT_TYPE_INT16
            jvalue = pointer_to_array(convert(Ptr{Int16}, value), (1,))[1]
        elseif data_type == READSTAT_TYPE_INT32
            jvalue = pointer_to_array(convert(Ptr{Int32}, value), (1,))[1]
        elseif data_type == READSTAT_TYPE_FLOAT
            jvalue = pointer_to_array(convert(Ptr{Float32}, value), (1,))[1]
            if isnan(jvalue)
                jvalue = NA
            end
        elseif data_type == READSTAT_TYPE_DOUBLE
            jvalue = pointer_to_array(convert(Ptr{Float64}, value), (1,))[1]
            if isnan(jvalue)
                jvalue = NA
            end
        end
    end
    ctx.columns[var_index+1][obs_index+1] = jvalue

    return convert(Cint, 0)
end

function handle_value_label(val_labels::Ptr{Int8}, value::Ptr{Void}, data_type::Cint, label::Ptr{Int8}, ctx_ptr::Ptr{Void})
    ctx = unsafe_pointer_to_objref(ctx_ptr)::DataReadCtx

    return convert(Cint, 0)
end

function read_data_file(filename::String, filetype::Symbol)
    ctx = DataReadCtx(0, Array(Symbol, (0,)), Array(Any, (0,)))

    info_fxn = cfunction(handle_info, Cint, (Cint, Cint, Ptr{Void}))
    var_fxn = cfunction(handle_variable, Cint, 
        (Cint, Ptr{Int8}, Ptr{Int8}, Ptr{Int8}, Ptr{Int8}, Cint, Csize_t, Ptr{Void}))
    val_fxn = cfunction(handle_value, Cint,
        (Cint, Cint, Ptr{Void}, Cint, Ptr{Void}))
    label_fxn = cfunction(handle_value_label, Cint,
        (Ptr{Int8}, Ptr{Void}, Cint, Ptr{Int8}, Ptr{Void}))

    retval = 0

    parser = ccall( (:readstat_parser_init, "libreadstat"), Ptr{Void}, ())
    ccall( (:readstat_set_info_handler, "libreadstat"), Int, (Ptr{Void}, Ptr{Void}), parser, info_fxn)
    ccall( (:readstat_set_variable_handler, "libreadstat"), Int, (Ptr{Void}, Ptr{Void}), parser, var_fxn)
    ccall( (:readstat_set_value_handler, "libreadstat"), Int, (Ptr{Void}, Ptr{Void}), parser, val_fxn)
    ccall( (:readstat_set_value_label_handler, "libreadstat"), Int, (Ptr{Void}, Ptr{Void}), parser, label_fxn)

    if filetype == :dta
        retval = ccall( (:readstat_parse_dta, "libreadstat"), Int, 
            (Ptr{Int8}, Ptr{Void}, Ptr{Void}),
            parser, bytestring(filename), pointer_from_objref(ctx))
    elseif filetype == :sav
        retval = ccall( (:readstat_parse_sav, "libreadstat"), Int, 
            (Ptr{Int8}, Ptr{Void}, Ptr{Void}),
            parser, bytestring(filename), pointer_from_objref(ctx))
    elseif filetype == :por
        retval = ccall( (:readstat_parse_por, "libreadstat"), Int, 
            (Ptr{Int8}, Ptr{Void}, Ptr{Void}),
            parser, bytestring(filename), pointer_from_objref(ctx))
    elseif filetype == :sas7bdat
        retval = ccall( (:readstat_parse_sas7bdat, "libreadstat"), Int, 
            (Ptr{Int8}, Ptr{Void}, Ptr{Void}),
            parser, bytestring(filename), pointer_from_objref(ctx))
    end

    ccall( (:readstat_parser_free, "libreadstat"), Void, (Ptr{Void},), parser)

    if retval == 0
        return DataFrame(ctx.columns, ctx.colnames)
    else
        error("Error parsing $filename: $retval")
    end
end

function read_dta(filename::String)
    return read_data_file(filename, :dta)
end

function read_por(filename::String)
    return read_data_file(filename, :por)
end

function read_sav(filename::String)
    return read_data_file(filename, :sav)
end

function read_sas7bdat(filename::String)
    return read_data_file(filename, :sas7bdat)
end

end #module DataRead
