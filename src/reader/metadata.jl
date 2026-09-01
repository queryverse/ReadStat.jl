# File-level and per-variable metadata captured during a parse.

"""
    ValueLabelDict

One value-label set: a dictionary mapping raw values to their display
labels. Keys are normalized to `Int32` (all integer types), `Float64` (all
floats), `String`, or — for labeled tagged missing values like Stata's
`.a` — the tag `Char`.
"""
const ValueLabelDict = Dict{Union{Char,Int32,Float64,String},String}

"""
    ReadStatVarMeta

Per-variable metadata from a stat-package file: `name`, `label`, `format`
(the producer's display format string), `type`/`type_class` (the raw C
storage type), `vallabel` (name of the value-label set, `Symbol("")` when
none), `storage_width`, `display_width`, `measure`, `alignment`, and
`missing_ranges` (SPSS user-defined missing values as `(lo, hi)` pairs, where
a single missing value has `lo == hi`).
"""
struct ReadStatVarMeta
    name::Symbol
    label::String
    format::String
    type::ReadStatType
    type_class::ReadStatTypeClass
    vallabel::Symbol
    storage_width::Int
    display_width::Int
    measure::ReadStatMeasure
    alignment::ReadStatAlignment
    missing_ranges::Vector{Tuple{Any,Any}}
end

"""
    ReadStatMeta

File-level metadata: `row_count` (`-1` when the format does not record it —
XPORT, POR, and some non-conforming SAV files; when a read used a
`row_limit`, the C library caps the reported count at that limit — use
[`read_meta`](@ref) for the true count), `var_count`, `creation_time`
and `modified_time`, `file_format_version`, `is_64bit` (SAS), `compression`,
`endianness`, `table_name` (XPORT), `file_label`, `file_encoding`, `notes`,
`fweight` (frequency-weight variable, `Symbol("")` when none), and
`value_labels` (label-set name => [`ValueLabelDict`](@ref)).
"""
mutable struct ReadStatMeta
    row_count::Int
    var_count::Int
    creation_time::DateTime
    modified_time::DateTime
    file_format_version::Int
    is_64bit::Bool
    compression::ReadStatCompress
    endianness::ReadStatEndian
    table_name::String
    file_label::String
    file_encoding::String
    notes::Vector{String}
    fweight::Symbol
    value_labels::Dict{Symbol,ValueLabelDict}
end

ReadStatMeta() = ReadStatMeta(-1, 0, Dates.unix2datetime(0), Dates.unix2datetime(0), 0,
    false, READSTAT_COMPRESS_NONE, READSTAT_ENDIAN_NONE, "", "", "", String[],
    Symbol(""), Dict{Symbol,ValueLabelDict}())
