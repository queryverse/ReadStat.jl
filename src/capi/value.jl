# The readstat_value_t mirror and its accessors.
#
# readstat_value_t is the only C struct this package mirrors: the C API passes
# and returns it by value, so an opaque pointer is not an option. Every other
# C struct is handled through an opaque pointer plus the C getter functions.

export ReadStatValue, Coff_t, Ctime_t,
    ParserPtr, MetadataPtr, VariablePtr, LabelSetPtr, SchemaPtr, WriterPtr, StringRefPtr,
    readstat_value_type, readstat_value_type_class, readstat_type_class,
    readstat_value_is_missing, readstat_value_is_system_missing,
    readstat_value_is_tagged_missing, readstat_value_is_defined_missing,
    readstat_value_tag, readstat_int8_value, readstat_int16_value, readstat_int32_value,
    readstat_float_value, readstat_double_value, readstat_string_value

# readstat_off_t and time_t as the C library was compiled. readstat.h
# typedefs readstat_off_t to _off64_t on Windows, so it is 64-bit on both
# Windows architectures; elsewhere it is off_t, which is 32-bit on 32-bit
# unix (no large-file opt-in in the jll build). time_t follows the word
# size everywhere: 32-bit on i686 for both MinGW (no _USE_32BIT_TIME_T
# opt-out) and glibc (no time64 opt-in). Getting these wrong shifts the
# seek callback's argument stack (segfaults) or fills the high half of
# timestamps with register garbage.
const Coff_t = (Sys.iswindows() || Sys.WORD_SIZE == 64) ? Int64 : Int32
const Ctime_t = Sys.WORD_SIZE == 64 ? Int64 : Int32

# Opaque C struct tags; only ever used as Ptr{...} type parameters.
abstract type readstat_parser_s end
abstract type readstat_metadata_s end
abstract type readstat_variable_s end
abstract type readstat_label_set_s end
abstract type readstat_schema_s end
abstract type readstat_writer_s end
abstract type readstat_string_ref_s end

const ParserPtr = Ptr{readstat_parser_s}
const MetadataPtr = Ptr{readstat_metadata_s}
const VariablePtr = Ptr{readstat_variable_s}
const LabelSetPtr = Ptr{readstat_label_set_s}
const SchemaPtr = Ptr{readstat_schema_s}
const WriterPtr = Ptr{readstat_writer_s}
const StringRefPtr = Ptr{readstat_string_ref_s}

# Layout must match readstat.h's readstat_value_t under the jll's compiler:
# 8-byte value union, Cint type at offset 8, char tag at 12, then two
# `unsigned int:1` bitfields. Where the bitfields land depends on the
# platform's bitfield ABI: Itanium/SysV GCC packs them into byte 13 (struct
# size 16), while MinGW GCC defaults to MS-compatible bitfield layout, which
# starts a fresh 4-byte-aligned unsigned int unit at offset 16 (struct size
# 24). The `bits` field is never decoded in Julia — the is_missing/tag
# accessors below are the only sanctioned way in. test/test_abi.jl checks
# this layout behaviorally against the C library.
struct ReadStatValue
    v::Int64
    type::ReadStatType
    tag::Cchar
    @static if Sys.iswindows()
        bits::Cuint
    else
        bits::UInt8
    end
end

function readstat_value_type(value::ReadStatValue)
    @ccall libreadstat.readstat_value_type(value::ReadStatValue)::ReadStatType
end

function readstat_value_type_class(value::ReadStatValue)
    @ccall libreadstat.readstat_value_type_class(value::ReadStatValue)::ReadStatTypeClass
end

function readstat_type_class(type::ReadStatType)
    @ccall libreadstat.readstat_type_class(type::ReadStatType)::ReadStatTypeClass
end

# `variable` may be a VariablePtr or C_NULL; with C_NULL only system/tagged
# missingness is considered.
function readstat_value_is_missing(value::ReadStatValue, variable::Ptr)
    (@ccall libreadstat.readstat_value_is_missing(value::ReadStatValue, variable::VariablePtr)::Cint) != 0
end

function readstat_value_is_system_missing(value::ReadStatValue)
    (@ccall libreadstat.readstat_value_is_system_missing(value::ReadStatValue)::Cint) != 0
end

function readstat_value_is_tagged_missing(value::ReadStatValue)
    (@ccall libreadstat.readstat_value_is_tagged_missing(value::ReadStatValue)::Cint) != 0
end

function readstat_value_is_defined_missing(value::ReadStatValue, variable::Ptr)
    (@ccall libreadstat.readstat_value_is_defined_missing(value::ReadStatValue, variable::VariablePtr)::Cint) != 0
end

function readstat_value_tag(value::ReadStatValue)
    Char(@ccall libreadstat.readstat_value_tag(value::ReadStatValue)::Cchar)
end

function readstat_int8_value(value::ReadStatValue)
    @ccall libreadstat.readstat_int8_value(value::ReadStatValue)::Int8
end

function readstat_int16_value(value::ReadStatValue)
    @ccall libreadstat.readstat_int16_value(value::ReadStatValue)::Int16
end

function readstat_int32_value(value::ReadStatValue)
    @ccall libreadstat.readstat_int32_value(value::ReadStatValue)::Int32
end

function readstat_float_value(value::ReadStatValue)
    @ccall libreadstat.readstat_float_value(value::ReadStatValue)::Float32
end

function readstat_double_value(value::ReadStatValue)
    @ccall libreadstat.readstat_double_value(value::ReadStatValue)::Float64
end

# Returns C_NULL-able pointer; callers decide how to treat NULL vs "".
function readstat_string_value(value::ReadStatValue)
    @ccall libreadstat.readstat_string_value(value::ReadStatValue)::Cstring
end
