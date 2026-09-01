# Parser lifecycle, handler registration, parser configuration, metadata and
# variable accessors, and the parse entry points from readstat.h (v1.1.9).

export readstat_parser_init, readstat_parser_free,
    readstat_set_metadata_handler, readstat_set_note_handler, readstat_set_variable_handler,
    readstat_set_fweight_handler, readstat_set_value_handler, readstat_set_value_label_handler,
    readstat_set_error_handler, readstat_set_progress_handler,
    readstat_set_open_handler, readstat_set_close_handler, readstat_set_seek_handler,
    readstat_set_read_handler, readstat_set_update_handler, readstat_set_io_ctx,
    readstat_set_file_character_encoding, readstat_set_handler_character_encoding,
    readstat_set_row_limit, readstat_set_row_offset,
    readstat_parse_dta, readstat_parse_sav, readstat_parse_por,
    readstat_parse_sas7bdat, readstat_parse_sas7bcat, readstat_parse_xport,
    readstat_get_row_count, readstat_get_var_count, readstat_get_creation_time,
    readstat_get_modified_time, readstat_get_file_format_version,
    readstat_get_file_format_is_64bit, readstat_get_compression, readstat_get_endianness,
    readstat_get_table_name, readstat_get_file_label, readstat_get_file_encoding,
    readstat_variable_get_index, readstat_variable_get_index_after_skipping,
    readstat_variable_get_name, readstat_variable_get_label, readstat_variable_get_format,
    readstat_variable_get_type, readstat_variable_get_type_class,
    readstat_variable_get_storage_width, readstat_variable_get_display_width,
    readstat_variable_get_measure, readstat_variable_get_alignment,
    readstat_variable_get_missing_ranges_count,
    readstat_variable_get_missing_range_lo, readstat_variable_get_missing_range_hi

_string_or_empty(ptr::Cstring) = ptr == C_NULL ? "" : unsafe_string(ptr)
_string_or_empty(ptr::Ptr{Cchar}) = ptr == C_NULL ? "" : unsafe_string(ptr)

# ---------------------------------------------------------------------------
# Parser lifecycle

readstat_parser_init() = @ccall libreadstat.readstat_parser_init()::ParserPtr

function readstat_parser_free(parser::ParserPtr)
    @ccall libreadstat.readstat_parser_free(parser::ParserPtr)::Cvoid
end

# ---------------------------------------------------------------------------
# Handler registration. Each takes a C function pointer (from @cfunction).

for setter in (:readstat_set_metadata_handler, :readstat_set_note_handler,
               :readstat_set_variable_handler, :readstat_set_fweight_handler,
               :readstat_set_value_handler, :readstat_set_value_label_handler,
               :readstat_set_error_handler, :readstat_set_progress_handler,
               :readstat_set_open_handler, :readstat_set_close_handler,
               :readstat_set_seek_handler, :readstat_set_read_handler,
               :readstat_set_update_handler)
    @eval function $setter(parser::ParserPtr, handler::Ptr{Cvoid})
        @ccall libreadstat.$setter(parser::ParserPtr, handler::Ptr{Cvoid})::ReadStatError
    end
end

function readstat_set_io_ctx(parser::ParserPtr, io_ctx::Ptr{Cvoid})
    @ccall libreadstat.readstat_set_io_ctx(parser::ParserPtr, io_ctx::Ptr{Cvoid})::ReadStatError
end

# ---------------------------------------------------------------------------
# Parser configuration

# Override the encoding declared in the file (iconv-compatible name); useful
# e.g. for pre-14 Stata files written in a system codepage.
function readstat_set_file_character_encoding(parser::ParserPtr, encoding::AbstractString)
    @ccall libreadstat.readstat_set_file_character_encoding(parser::ParserPtr, encoding::Cstring)::ReadStatError
end

# Encoding delivered to the handlers; defaults to UTF-8. C_NULL disables
# transliteration entirely.
function readstat_set_handler_character_encoding(parser::ParserPtr, encoding::Union{AbstractString,Ptr{Nothing}})
    @ccall libreadstat.readstat_set_handler_character_encoding(parser::ParserPtr, encoding::Cstring)::ReadStatError
end

function readstat_set_row_limit(parser::ParserPtr, row_limit::Integer)
    @ccall libreadstat.readstat_set_row_limit(parser::ParserPtr, row_limit::Clong)::ReadStatError
end

function readstat_set_row_offset(parser::ParserPtr, row_offset::Integer)
    @ccall libreadstat.readstat_set_row_offset(parser::ParserPtr, row_offset::Clong)::ReadStatError
end

# ---------------------------------------------------------------------------
# Parse entry points. `user_ctx` is passed as `Any` so the ccall roots the
# context object for the duration of the parse.

for parse_fn in (:readstat_parse_dta, :readstat_parse_sav, :readstat_parse_por,
                 :readstat_parse_sas7bdat, :readstat_parse_sas7bcat, :readstat_parse_xport)
    @eval function $parse_fn(parser::ParserPtr, path::AbstractString, user_ctx)
        @ccall libreadstat.$parse_fn(parser::ParserPtr, path::Cstring, user_ctx::Any)::ReadStatError
    end
end

# ---------------------------------------------------------------------------
# Metadata accessors (valid inside the metadata handler)

function readstat_get_row_count(metadata::MetadataPtr)
    @ccall libreadstat.readstat_get_row_count(metadata::MetadataPtr)::Cint
end

function readstat_get_var_count(metadata::MetadataPtr)
    @ccall libreadstat.readstat_get_var_count(metadata::MetadataPtr)::Cint
end

function readstat_get_creation_time(metadata::MetadataPtr)
    Int64(@ccall libreadstat.readstat_get_creation_time(metadata::MetadataPtr)::Ctime_t)
end

function readstat_get_modified_time(metadata::MetadataPtr)
    Int64(@ccall libreadstat.readstat_get_modified_time(metadata::MetadataPtr)::Ctime_t)
end

function readstat_get_file_format_version(metadata::MetadataPtr)
    @ccall libreadstat.readstat_get_file_format_version(metadata::MetadataPtr)::Cint
end

function readstat_get_file_format_is_64bit(metadata::MetadataPtr)
    (@ccall libreadstat.readstat_get_file_format_is_64bit(metadata::MetadataPtr)::Cint) != 0
end

function readstat_get_compression(metadata::MetadataPtr)
    @ccall libreadstat.readstat_get_compression(metadata::MetadataPtr)::ReadStatCompress
end

function readstat_get_endianness(metadata::MetadataPtr)
    @ccall libreadstat.readstat_get_endianness(metadata::MetadataPtr)::ReadStatEndian
end

function readstat_get_table_name(metadata::MetadataPtr)
    _string_or_empty(@ccall libreadstat.readstat_get_table_name(metadata::MetadataPtr)::Cstring)
end

function readstat_get_file_label(metadata::MetadataPtr)
    _string_or_empty(@ccall libreadstat.readstat_get_file_label(metadata::MetadataPtr)::Cstring)
end

function readstat_get_file_encoding(metadata::MetadataPtr)
    _string_or_empty(@ccall libreadstat.readstat_get_file_encoding(metadata::MetadataPtr)::Cstring)
end

# ---------------------------------------------------------------------------
# Variable accessors (valid inside the variable/value handlers)

function readstat_variable_get_index(variable::VariablePtr)
    @ccall libreadstat.readstat_variable_get_index(variable::VariablePtr)::Cint
end

function readstat_variable_get_index_after_skipping(variable::VariablePtr)
    @ccall libreadstat.readstat_variable_get_index_after_skipping(variable::VariablePtr)::Cint
end

function readstat_variable_get_name(variable::VariablePtr)
    _string_or_empty(@ccall libreadstat.readstat_variable_get_name(variable::VariablePtr)::Cstring)
end

function readstat_variable_get_label(variable::VariablePtr)
    _string_or_empty(@ccall libreadstat.readstat_variable_get_label(variable::VariablePtr)::Cstring)
end

function readstat_variable_get_format(variable::VariablePtr)
    _string_or_empty(@ccall libreadstat.readstat_variable_get_format(variable::VariablePtr)::Cstring)
end

function readstat_variable_get_type(variable::VariablePtr)
    @ccall libreadstat.readstat_variable_get_type(variable::VariablePtr)::ReadStatType
end

function readstat_variable_get_type_class(variable::VariablePtr)
    @ccall libreadstat.readstat_variable_get_type_class(variable::VariablePtr)::ReadStatTypeClass
end

function readstat_variable_get_storage_width(variable::VariablePtr)
    @ccall libreadstat.readstat_variable_get_storage_width(variable::VariablePtr)::Csize_t
end

function readstat_variable_get_display_width(variable::VariablePtr)
    @ccall libreadstat.readstat_variable_get_display_width(variable::VariablePtr)::Cint
end

function readstat_variable_get_measure(variable::VariablePtr)
    @ccall libreadstat.readstat_variable_get_measure(variable::VariablePtr)::ReadStatMeasure
end

function readstat_variable_get_alignment(variable::VariablePtr)
    @ccall libreadstat.readstat_variable_get_alignment(variable::VariablePtr)::ReadStatAlignment
end

function readstat_variable_get_missing_ranges_count(variable::VariablePtr)
    @ccall libreadstat.readstat_variable_get_missing_ranges_count(variable::VariablePtr)::Cint
end

function readstat_variable_get_missing_range_lo(variable::VariablePtr, i::Integer)
    @ccall libreadstat.readstat_variable_get_missing_range_lo(variable::VariablePtr, i::Cint)::ReadStatValue
end

function readstat_variable_get_missing_range_hi(variable::VariablePtr, i::Integer)
    @ccall libreadstat.readstat_variable_get_missing_range_hi(variable::VariablePtr, i::Cint)::ReadStatValue
end
