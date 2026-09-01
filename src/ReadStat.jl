module ReadStat

using DataValues: DataValues, DataValueVector
using Dates

export ReadStatTable, ReadStatMeta, ReadStatVarMeta, ReadStatDataFrame,
    read_dta, read_sav, read_por, read_sas7bdat, read_xport, read_sas7bcat,
    readstat, read_meta,
    filemetadata, varmetadata, valuelabels, missingtags,
    LabeledValue, LabeledArray, labeled, unwrap, valuelabel, rawvalues, getvaluelabels,
    HMS,
    ReadStatSource, ReadStatChunks, schema, colnames, coltypes, nrows, supports, chunks,
    write_dta, write_sav, write_por, write_sas7bdat, write_xport, write_sas7bcat,
    read_txt

public CAPI

# The low-level writer layer: public, not exported.
public Writer, WriterVariable, LabelSet, StringRef,
    add_label_set!, label!, add_variable!, add_note!, add_string_ref!,
    file_label!, timestamp!, fweight!, format_version!, table_name!, is_64bit!,
    compression!, begin_writing!, validate_metadata, validate_variable,
    begin_row!, end_row!, insert_value!, insert_missing!, insert_tagged_missing!,
    insert_string_ref!, end_writing!

"""
    ReadStat.CAPI

Thin wrappers around the public C API of the readstat library (readstat.h,
v1.1.9). Function names, argument order, and semantics follow the C header
one-to-one; C structs are handled as opaque pointers except `ReadStatValue`,
which the C API passes by value. Higher-level functionality lives in the
parent `ReadStat` module — reach for `CAPI` only when the high-level API does
not expose what you need.
"""
module CAPI

using ReadStat_jll: libreadstat

include("capi/enums.jl")
include("capi/value.jl")
include("capi/parser.jl")
include("capi/schema.jl")
include("capi/writer.jl")

end # module CAPI

using .CAPI

# Julia type corresponding to each ReadStatType, indexed by the enum value
# plus one. STRING_REF is a reference into a string table, so it surfaces as
# a String just like STRING does.
const READSTAT_TYPES = (String, Int8, Int16, Int32, Float32, Float64, String)

jltype(t::ReadStatType) = READSTAT_TYPES[Int(t) + 1]

include("reader/metadata.jl")
include("values/labeled.jl")
include("values/datetime.jl")
include("reader/columns.jl")
include("reader/context.jl")
include("reader/handlers.jl")
include("reader/table.jl")
include("reader/io.jl")
include("reader/threaded.jl")
include("reader/read.jl")
include("reader/source.jl")
include("reader/chunks.jl")
include("writer/writer.jl")
include("writer/write.jl")
include("deprecated.jl")

function __init__()
    _init_cfunctions()
    _init_io_cfunctions()
    _init_writer_cfunctions()
    return nothing
end

end # module ReadStat
