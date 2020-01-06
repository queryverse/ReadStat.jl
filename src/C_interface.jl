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

function readstat_variable_get_name(variable::Ptr{Nothing})
    return unsafe_string(ccall((:readstat_variable_get_name, libreadstat), Cstring, (Ptr{Nothing},), variable))
end

function readstat_variable_get_type(variable::Ptr{Nothing})
    return ccall((:readstat_variable_get_type, libreadstat), Cint, (Ptr{Nothing},), variable)
end

function readstat_variable_get_storage_width(variable::Ptr{Nothing})
    return ccall((:readstat_variable_get_storage_width, libreadstat), Csize_t, (Ptr{Nothing},), variable)
end

function readstat_variable_get_measure(variable::Ptr{Nothing})
    return ccall((:readstat_variable_get_measure, libreadstat), Cint, (Ptr{Nothing},), variable)
end

function readstat_variable_get_alignment(variable::Ptr{Nothing})
    return ccall((:readstat_variable_get_alignment, libreadstat), Cint, (Ptr{Nothing},), variable)
end

function readstat_parser_free(parser::Ptr{Nothing})
    return ccall((:readstat_parser_free, libreadstat), Nothing, (Ptr{Nothing},), parser)
end

function readstat_value_type(val::Value)
    return ccall((:readstat_value_type, libreadstat), Cint, (Value,), val)
end

function readstat_parse(filename::String, type::Val{:dta}, parser::Ptr{Nothing}, ds::ReadStatDataFrame)
    return ccall((:readstat_parse_dta, libreadstat), Int, (Ptr{Nothing}, Cstring, Any), parser, string(filename), ds)
end

function readstat_parse(filename::String, type::Val{:sav}, parser::Ptr{Nothing}, ds::ReadStatDataFrame)
    return ccall((:readstat_parse_sav, libreadstat), Int, (Ptr{Nothing}, Cstring, Any), parser, string(filename), ds)
end

function readstat_parse(filename::String, type::Val{:por}, parser::Ptr{Nothing}, ds::ReadStatDataFrame)
    return ccall((:readstat_parse_por, libreadstat), Int, (Ptr{Nothing}, Cstring, Any), parser, string(filename), ds)
end

function readstat_parse(filename::String, type::Val{:sas7bdat}, parser::Ptr{Nothing}, ds::ReadStatDataFrame)
    return ccall((:readstat_parse_sas7bdat, libreadstat), Int, (Ptr{Nothing}, Cstring, Any), parser, string(filename), ds)
end

function readstat_variable_get_missing_ranges_count(variable::Ptr{Nothing})
    return ccall((:readstat_variable_get_missing_ranges_count, libreadstat), Cint, (Ptr{Nothing},), variable)
end
