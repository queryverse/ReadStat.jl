# The full writer API from readstat.h (v1.1.9).

export readstat_writer_init, readstat_writer_free, readstat_set_data_writer,
    readstat_add_label_set, readstat_label_double_value, readstat_label_int32_value,
    readstat_label_string_value, readstat_label_tagged_value,
    readstat_add_variable, readstat_variable_set_label, readstat_variable_set_format,
    readstat_variable_set_label_set, readstat_variable_set_measure,
    readstat_variable_set_alignment, readstat_variable_set_display_width,
    readstat_variable_add_missing_double_value, readstat_variable_add_missing_double_range,
    readstat_variable_add_missing_string_value, readstat_variable_add_missing_string_range,
    readstat_get_variable, readstat_add_note, readstat_add_string_ref,
    readstat_get_string_ref,
    readstat_writer_set_file_label, readstat_writer_set_file_timestamp,
    readstat_writer_set_fweight_variable, readstat_writer_set_file_format_version,
    readstat_writer_set_table_name, readstat_writer_set_file_format_is_64bit,
    readstat_writer_set_compression, readstat_writer_set_error_handler,
    readstat_begin_writing_dta, readstat_begin_writing_por, readstat_begin_writing_sas7bcat,
    readstat_begin_writing_sas7bdat, readstat_begin_writing_sav, readstat_begin_writing_xport,
    readstat_validate_metadata, readstat_validate_variable,
    readstat_begin_row, readstat_insert_int8_value, readstat_insert_int16_value,
    readstat_insert_int32_value, readstat_insert_float_value, readstat_insert_double_value,
    readstat_insert_string_value, readstat_insert_string_ref, readstat_insert_missing_value,
    readstat_insert_tagged_missing_value, readstat_end_row, readstat_end_writing

readstat_writer_init() = @ccall libreadstat.readstat_writer_init()::WriterPtr

function readstat_writer_free(writer::WriterPtr)
    @ccall libreadstat.readstat_writer_free(writer::WriterPtr)::Cvoid
end

function readstat_set_data_writer(writer::WriterPtr, data_writer::Ptr{Cvoid})
    @ccall libreadstat.readstat_set_data_writer(writer::WriterPtr, data_writer::Ptr{Cvoid})::ReadStatError
end

# ---------------------------------------------------------------------------
# Label sets

function readstat_add_label_set(writer::WriterPtr, type::ReadStatType, name::AbstractString)
    @ccall libreadstat.readstat_add_label_set(writer::WriterPtr, type::ReadStatType,
        name::Cstring)::LabelSetPtr
end

function readstat_label_double_value(label_set::LabelSetPtr, value::Real, label::AbstractString)
    @ccall libreadstat.readstat_label_double_value(label_set::LabelSetPtr, value::Cdouble,
        label::Cstring)::Cvoid
end

function readstat_label_int32_value(label_set::LabelSetPtr, value::Integer, label::AbstractString)
    @ccall libreadstat.readstat_label_int32_value(label_set::LabelSetPtr, value::Int32,
        label::Cstring)::Cvoid
end

function readstat_label_string_value(label_set::LabelSetPtr, value::AbstractString, label::AbstractString)
    @ccall libreadstat.readstat_label_string_value(label_set::LabelSetPtr, value::Cstring,
        label::Cstring)::Cvoid
end

function readstat_label_tagged_value(label_set::LabelSetPtr, tag::Char, label::AbstractString)
    @ccall libreadstat.readstat_label_tagged_value(label_set::LabelSetPtr, tag::Cchar,
        label::Cstring)::Cvoid
end

# ---------------------------------------------------------------------------
# Variables

function readstat_add_variable(writer::WriterPtr, name::AbstractString, type::ReadStatType,
                               storage_width::Integer)
    @ccall libreadstat.readstat_add_variable(writer::WriterPtr, name::Cstring,
        type::ReadStatType, storage_width::Csize_t)::VariablePtr
end

function readstat_variable_set_label(variable::VariablePtr, label::AbstractString)
    @ccall libreadstat.readstat_variable_set_label(variable::VariablePtr, label::Cstring)::Cvoid
end

function readstat_variable_set_format(variable::VariablePtr, format::AbstractString)
    @ccall libreadstat.readstat_variable_set_format(variable::VariablePtr, format::Cstring)::Cvoid
end

function readstat_variable_set_label_set(variable::VariablePtr, label_set::LabelSetPtr)
    @ccall libreadstat.readstat_variable_set_label_set(variable::VariablePtr,
        label_set::LabelSetPtr)::Cvoid
end

function readstat_variable_set_measure(variable::VariablePtr, measure::ReadStatMeasure)
    @ccall libreadstat.readstat_variable_set_measure(variable::VariablePtr,
        measure::ReadStatMeasure)::Cvoid
end

function readstat_variable_set_alignment(variable::VariablePtr, alignment::ReadStatAlignment)
    @ccall libreadstat.readstat_variable_set_alignment(variable::VariablePtr,
        alignment::ReadStatAlignment)::Cvoid
end

function readstat_variable_set_display_width(variable::VariablePtr, display_width::Integer)
    @ccall libreadstat.readstat_variable_set_display_width(variable::VariablePtr,
        display_width::Cint)::Cvoid
end

function readstat_variable_add_missing_double_value(variable::VariablePtr, value::Real)
    @ccall libreadstat.readstat_variable_add_missing_double_value(variable::VariablePtr,
        value::Cdouble)::ReadStatError
end

function readstat_variable_add_missing_double_range(variable::VariablePtr, lo::Real, hi::Real)
    @ccall libreadstat.readstat_variable_add_missing_double_range(variable::VariablePtr,
        lo::Cdouble, hi::Cdouble)::ReadStatError
end

function readstat_variable_add_missing_string_value(variable::VariablePtr, value::AbstractString)
    @ccall libreadstat.readstat_variable_add_missing_string_value(variable::VariablePtr,
        value::Cstring)::ReadStatError
end

function readstat_variable_add_missing_string_range(variable::VariablePtr,
                                                    lo::AbstractString, hi::AbstractString)
    @ccall libreadstat.readstat_variable_add_missing_string_range(variable::VariablePtr,
        lo::Cstring, hi::Cstring)::ReadStatError
end

function readstat_get_variable(writer::WriterPtr, index::Integer)
    @ccall libreadstat.readstat_get_variable(writer::WriterPtr, index::Cint)::VariablePtr
end

# ---------------------------------------------------------------------------
# Notes, string refs, file-level metadata

function readstat_add_note(writer::WriterPtr, note::AbstractString)
    @ccall libreadstat.readstat_add_note(writer::WriterPtr, note::Cstring)::Cvoid
end

function readstat_add_string_ref(writer::WriterPtr, string::AbstractString)
    @ccall libreadstat.readstat_add_string_ref(writer::WriterPtr, string::Cstring)::StringRefPtr
end

function readstat_get_string_ref(writer::WriterPtr, index::Integer)
    @ccall libreadstat.readstat_get_string_ref(writer::WriterPtr, index::Cint)::StringRefPtr
end

function readstat_writer_set_file_label(writer::WriterPtr, file_label::AbstractString)
    @ccall libreadstat.readstat_writer_set_file_label(writer::WriterPtr,
        file_label::Cstring)::ReadStatError
end

function readstat_writer_set_file_timestamp(writer::WriterPtr, timestamp::Integer)
    @ccall libreadstat.readstat_writer_set_file_timestamp(writer::WriterPtr,
        timestamp::Int64)::ReadStatError
end

function readstat_writer_set_fweight_variable(writer::WriterPtr, variable::VariablePtr)
    @ccall libreadstat.readstat_writer_set_fweight_variable(writer::WriterPtr,
        variable::VariablePtr)::ReadStatError
end

function readstat_writer_set_file_format_version(writer::WriterPtr, version::Integer)
    @ccall libreadstat.readstat_writer_set_file_format_version(writer::WriterPtr,
        version::UInt8)::ReadStatError
end

function readstat_writer_set_table_name(writer::WriterPtr, table_name::AbstractString)
    @ccall libreadstat.readstat_writer_set_table_name(writer::WriterPtr,
        table_name::Cstring)::ReadStatError
end

function readstat_writer_set_file_format_is_64bit(writer::WriterPtr, is_64bit::Bool)
    @ccall libreadstat.readstat_writer_set_file_format_is_64bit(writer::WriterPtr,
        is_64bit::Cint)::ReadStatError
end

function readstat_writer_set_compression(writer::WriterPtr, compression::ReadStatCompress)
    @ccall libreadstat.readstat_writer_set_compression(writer::WriterPtr,
        compression::ReadStatCompress)::ReadStatError
end

function readstat_writer_set_error_handler(writer::WriterPtr, error_handler::Ptr{Cvoid})
    @ccall libreadstat.readstat_writer_set_error_handler(writer::WriterPtr,
        error_handler::Ptr{Cvoid})::ReadStatError
end

# ---------------------------------------------------------------------------
# Writing

for begin_fn in (:readstat_begin_writing_dta, :readstat_begin_writing_por,
                 :readstat_begin_writing_sas7bdat, :readstat_begin_writing_sav,
                 :readstat_begin_writing_xport)
    @eval function $begin_fn(writer::WriterPtr, user_ctx::Ptr{Cvoid}, row_count::Integer)
        @ccall libreadstat.$begin_fn(writer::WriterPtr, user_ctx::Ptr{Cvoid},
            row_count::Clong)::ReadStatError
    end
end

function readstat_begin_writing_sas7bcat(writer::WriterPtr, user_ctx::Ptr{Cvoid})
    @ccall libreadstat.readstat_begin_writing_sas7bcat(writer::WriterPtr,
        user_ctx::Ptr{Cvoid})::ReadStatError
end

function readstat_validate_metadata(writer::WriterPtr)
    @ccall libreadstat.readstat_validate_metadata(writer::WriterPtr)::ReadStatError
end

function readstat_validate_variable(writer::WriterPtr, variable::VariablePtr)
    @ccall libreadstat.readstat_validate_variable(writer::WriterPtr,
        variable::VariablePtr)::ReadStatError
end

function readstat_begin_row(writer::WriterPtr)
    @ccall libreadstat.readstat_begin_row(writer::WriterPtr)::ReadStatError
end

for (insert_fn, T) in ((:readstat_insert_int8_value, Int8),
                       (:readstat_insert_int16_value, Int16),
                       (:readstat_insert_int32_value, Int32),
                       (:readstat_insert_float_value, Float32),
                       (:readstat_insert_double_value, Float64))
    @eval function $insert_fn(writer::WriterPtr, variable::VariablePtr, value::$T)
        @ccall libreadstat.$insert_fn(writer::WriterPtr, variable::VariablePtr,
            value::$T)::ReadStatError
    end
end

function readstat_insert_string_value(writer::WriterPtr, variable::VariablePtr,
                                      value::AbstractString)
    @ccall libreadstat.readstat_insert_string_value(writer::WriterPtr,
        variable::VariablePtr, value::Cstring)::ReadStatError
end

function readstat_insert_string_ref(writer::WriterPtr, variable::VariablePtr,
                                    ref::StringRefPtr)
    @ccall libreadstat.readstat_insert_string_ref(writer::WriterPtr,
        variable::VariablePtr, ref::StringRefPtr)::ReadStatError
end

function readstat_insert_missing_value(writer::WriterPtr, variable::VariablePtr)
    @ccall libreadstat.readstat_insert_missing_value(writer::WriterPtr,
        variable::VariablePtr)::ReadStatError
end

function readstat_insert_tagged_missing_value(writer::WriterPtr, variable::VariablePtr,
                                              tag::Char)
    @ccall libreadstat.readstat_insert_tagged_missing_value(writer::WriterPtr,
        variable::VariablePtr, tag::Cchar)::ReadStatError
end

function readstat_end_row(writer::WriterPtr)
    @ccall libreadstat.readstat_end_row(writer::WriterPtr)::ReadStatError
end

function readstat_end_writing(writer::WriterPtr)
    @ccall libreadstat.readstat_end_writing(writer::WriterPtr)::ReadStatError
end
