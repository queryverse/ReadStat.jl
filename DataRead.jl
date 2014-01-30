module DataRead

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
    colnames::Vector{String}
    columns::Vector{DataVector{Any}}
end

function handle_info(obs_count::Cint, var_count::Cint, ctx_ptr::Ptr{Void})
    nrows = convert(Int, obs_count)
    ncols = convert(Int, var_count)
    colnames = Array(String, (ncols,))
    columns = Array(DataVector{Any}, (ncols,))

    ctx = unsafe_pointer_to_objref(ctx_ptr)::DataReadCtx
    ctx.nrows = nrows
    ctx.colnames = colnames
    ctx.columns = columns

    return convert(Cint, 0)
end

function handle_variable(index::Cint, name::Ptr{Int8}, format::Ptr{Int8}, label::Ptr{Int8},
    value_labels::Ptr{Int8}, data_type::Cint, max_len::Csize_t, ctx_ptr::Ptr{Void})

    ctx = unsafe_pointer_to_objref(ctx_ptr)::DataReadCtx
    name_str = bytestring(name)
    ctx.colnames[index+1] = name_str

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
    value_array = DataArray(jtype, (ctx.nrows,))
    if jtype == String
        for i in 1:ctx.nrows
            value_array[i] = ""
        end
    end
    for i in 1:ctx.nrows
        value_array[i] = NA
    end
    ctx.columns[index+1] = value_array

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

function read_data_file(filename::String, func::Symbol)
    ctx = DataReadCtx(0, Array(String, (0,)), Array(DataVector{Any}, (0,)))

    info_fxn = cfunction(handle_info, Cint, (Cint, Cint, Ptr{Void}))
    var_fxn = cfunction(handle_variable, Cint, 
        (Cint, Ptr{Int8}, Ptr{Int8}, Ptr{Int8}, Ptr{Int8}, Cint, Csize_t, Ptr{Void}))
    val_fxn = cfunction(handle_value, Cint,
        (Cint, Cint, Ptr{Void}, Cint, Ptr{Void}))
    label_fxn = cfunction(handle_value_label, Cint,
        (Ptr{Int8}, Ptr{Void}, Cint, Ptr{Int8}, Ptr{Void}))

    retval = 0

    if func == :parse_dta
        retval = ccall( (:parse_dta, "libreadstat"), Int, 
            (Ptr{Int8}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}),
            bytestring(filename), pointer_from_objref(ctx), info_fxn, var_fxn, val_fxn, label_fxn)
    elseif func == :parse_sav
        retval = ccall( (:parse_sav, "libreadstat"), Int, 
            (Ptr{Int8}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}),
            bytestring(filename), pointer_from_objref(ctx), info_fxn, var_fxn, val_fxn, label_fxn)
    elseif func == :parse_por
        retval = ccall( (:parse_por, "libreadstat"), Int, 
            (Ptr{Int8}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}),
            bytestring(filename), pointer_from_objref(ctx), info_fxn, var_fxn, val_fxn, label_fxn)
    elseif func == :parse_sas7bdat
        retval = ccall( (:parse_sas7bdat, "libreadstat"), Int, 
            (Ptr{Int8}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}),
            bytestring(filename), pointer_from_objref(ctx), info_fxn, var_fxn, val_fxn)
    end

    if retval == 0
        dict = Dict{String,DataVector{Any}}()
        for i in 1:length(ctx.colnames)
            dict[ctx.colnames[i]] = ctx.columns[i]
        end
        return DataFrame(dict)
    else
        error("Error parsing $filename: $retval")
    end
end

function read_dta(filename::String)
    return read_data_file(filename, :parse_dta)
end

function read_por(filename::String)
    return read_data_file(filename, :parse_por)
end

function read_sav(filename::String)
    return read_data_file(filename, :parse_sav)
end

function read_sas7bdat(filename::String)
    return read_data_file(filename, :parse_sas7bdat)
end

end #module DataRead
