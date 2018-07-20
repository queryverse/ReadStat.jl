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
