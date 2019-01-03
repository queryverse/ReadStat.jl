function readstat_get_file_label(metadata::Ptr{Nothing})
    ptr = ccall((:readstat_get_file_label, libreadstat), Cstring, (Ptr{Nothing},), metadata)
    return ptr == C_NULL ? "" : unsafe_string(ptr)
end

function readstat_get_modified_time(metadata::Ptr{Nothing})
    return ccall((:readstat_get_modified_time, libreadstat), UInt, (Ptr{Nothing},), metadata)
end

function readstat_get_file_format_version(metadata::Ptr{Nothing})
    return ccall((:readstat_get_file_format_version, libreadstat), UInt, (Ptr{Nothing},), metadata)
end

function readstat_get_row_count(metadata::Ptr{Nothing})
    return ccall((:readstat_get_row_count, libreadstat), UInt, (Ptr{Nothing},), metadata)
end

function readstat_get_var_count(metadata::Ptr{Nothing})
    return ccall((:readstat_get_var_count, libreadstat), UInt, (Ptr{Nothing},), metadata)
end

function readstat_value_is_missing(value::ReadStatValue, variable::Ptr{Nothing})
    return ccall((:readstat_value_is_missing, libreadstat), Bool, (ReadStatValue,Ptr{Nothing}), value, variable)
end

function readstat_variable_get_index(variable::Ptr{Nothing})
    return ccall((:readstat_variable_get_index, libreadstat), Cint, (Ptr{Nothing},), variable)
end

function readstat_writer_init()
    return ccall((:readstat_writer_init, libreadstat), Ptr{Cvoid}, ())
end

function readstat_set_data_writer(writer, data_writer)
    return ccall((:readstat_set_data_writer, libreadstat), Cvoid, (Ptr{Cvoid},Ptr{Cvoid}), (writer, data_writer))
end

function readstat_add_variable(writer, name, typ)
    return ccall((:readstat_add_variable, libreadstat), Ptr{Cvoid}, (Ptr{Cvoid}, Cstring, UInt), writer, name, typ)
end

function readstat_begin_writing_dta(writer, user_ctx, row_count)
    return ccall((:readstat_begin_writing_dta, libreadstat), UInt, (Ptr{Cvoid}, Ptr{Cvoid}, Clong), writer, user_ctx, row_count)
end

function readstat_begin_row(writer)
    return ccall((:readstat_begin_row, libreadstat), UInt, (Ptr{Cvoid},), writer)
end

function readstat_insert_double_value(writer, variable, value)
    return ccall((:readstat_insert_double_value, libreadstat), UInt, (Ptr{Cvoid},Ptr{Cvoid},Cdouble), writer, variable, value)
end

function readstat_end_row(writer)
    return ccall((:readstat_end_row, libreadstat), UInt, (Ptr{Cvoid},), writer)
end

function readstat_end_writing(writer)
    return ccall((:readstat_end_writing, libreadstat), UInt, (Ptr{Cvoid},), writer)
end

function readstat_writer_free(writer)
    return ccall((:readstat_writer_free, libreadstat), UInt, (Ptr{Cvoid},), writer)
end