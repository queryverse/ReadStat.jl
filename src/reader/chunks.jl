# Streaming chunked reads: a single pass over the file that hands finished
# ReadStatTables of `chunksize` rows through a bounded Channel. This is O(n)
# for a full scan — deliberately not one re-parse per chunk, which would be
# quadratic on compressed formats — and it works for formats that do not
# record a row count.

# State threaded through the value handler while a chunked parse runs. The
# schema and metadata come from a pre-pass so every chunk (and the labels on
# it) is complete from the first chunk on, regardless of where the file
# stores its label sets.
mutable struct ChunkSink
    channel::Channel{ReadStatTable}
    chunksize::Int
    names::Vector{Symbol}
    varmeta::Vector{ReadStatVarMeta}
    meta::ReadStatMeta
    convert_datetime::Bool
    apply_value_labels::Bool
    file_format::Symbol
end

_maybe_flush!(pc::ParseContext, sink::ChunkSink, row::Int) =
    (row == sink.chunksize && _flush_chunk!(pc, sink, row); nothing)

function _flush_chunk!(pc::ParseContext, sink::ChunkSink, nrows::Int)
    trimcolumns!(pc.cols, nrows)
    bt = ParseContext()
    bt.names = sink.names
    bt.varmeta = sink.varmeta
    bt.meta = sink.meta
    bt.cols = pc.cols
    bt.convert_datetime = sink.convert_datetime
    bt.apply_value_labels = sink.apply_value_labels
    bt.file_format = sink.file_format
    put!(sink.channel, build_table(bt))
    # Fresh buffers for the next chunk; rows keep arriving with absolute
    # observation indices, so the base shifts back by what was emitted.
    cols = TypedColumns()
    for vm in sink.varmeta
        addcolumn!(cols, jltype(vm.type), sink.chunksize)
    end
    pc.cols = cols
    pc.row_base -= nrows
    pc.rows_complete = 0
    return
end

"""
    ReadStatChunks

Iterator over the chunks of a [`chunks`](@ref) read. Each element is a
complete [`ReadStatTable`](@ref) of up to `chunksize` rows sharing the
file's metadata. Iteration is single-pass and backed by a bounded channel:
the parse runs on its own task and blocks once two chunks are waiting.
Call `close(it)` if iteration stops early, so the parse task is released.
"""
struct ReadStatChunks
    channel::Channel{ReadStatTable}
end

Base.IteratorSize(::Type{ReadStatChunks}) = Base.SizeUnknown()
Base.eltype(::Type{ReadStatChunks}) = ReadStatTable
Base.close(it::ReadStatChunks) = close(it.channel)

function Base.iterate(it::ReadStatChunks, state=nothing)
    try
        return (take!(it.channel), nothing)
    catch e
        e isa InvalidStateException && return nothing
        rethrow()
    end
end

"""
    chunks(src::ReadStatSource; chunksize=65_536, usecols=nothing, rows=nothing)
        -> ReadStatChunks

Stream the source as [`ReadStatTable`](@ref)s of up to `chunksize` rows, in
one pass over the file. `usecols` and `rows` push a projection and a 1-based
row range into the parse, exactly as in `read(src; ...)`. The chunks carry
the file's complete metadata (from a metadata pre-pass), so value labels and
date/time conversion apply from the first chunk on.

Iterate the result with `for chunk in chunks(src) ... end`; when stopping
early, `close` the iterator to release the parse task.
"""
function chunks(src::ReadStatSource; chunksize::Integer=65_536, usecols=nothing,
                rows::Union{Nothing,AbstractUnitRange{<:Integer}}=nothing)
    chunksize >= 1 || throw(ArgumentError("chunksize must be at least 1"))
    rows === nothing || first(rows) >= 1 ||
        throw(ArgumentError("rows must be a 1-based range"))

    # Pre-pass with the same projection, so schema and chunks line up.
    pre = _source_meta(src, usecols)

    chunksize = Int(chunksize)
    channel = Channel{ReadStatTable}(2; spawn=true) do ch
        pc = ParseContext()
        pc.usecols = _colselector(usecols)
        pc.file_encoding = src.file_encoding
        pc.handler_encoding = src.handler_encoding
        pc.keep_user_missing = src.user_missing === :keep
        if rows !== nothing
            pc.row_offset = first(rows) - 1
            pc.row_limit = length(rows)
        end
        pc.preassigned_cols = true
        cols = TypedColumns()
        for vm in pre.varmeta
            addcolumn!(cols, jltype(vm.type), chunksize)
        end
        pc.cols = cols
        sink = ChunkSink(ch, chunksize, pre.names, pre.varmeta, pre.meta,
            src.convert_datetime, src.apply_value_labels, src.format)
        pc.chunk_sink = sink
        parse_file!(pc, src.source, src.format)
        pc.rows_complete > 0 && _flush_chunk!(pc, sink, pc.rows_complete)
        return
    end
    return ReadStatChunks(channel)
end
