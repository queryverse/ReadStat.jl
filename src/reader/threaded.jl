# Multi-task reading: split the row range into contiguous chunks, one C
# parser per task, all writing directly into shared preallocated column
# buffers (disjoint row regions of plain Vectors, which is thread-safe).
# There are no per-task buffers to merge and no chained columns afterwards;
# the only post-join work is combining the rare tagged-missing tag vectors.
#
# A metadata pre-pass (no value handler, no row limit) supplies the true row
# count, the schema for preallocation, and the value labels and notes — the
# C parsers do not reliably deliver value labels under a row limit, so the
# chunk parses cannot be trusted for metadata.

const _THREADED_FORMATS = (:dta, :sav, :sas7bdat)

function _auto_ntasks(path::AbstractString)
    Threads.nthreads() == 1 && return 1
    sz = try
        filesize(path)
    catch
        0
    end
    # Small files are not worth the metadata pre-pass and task setup.
    return sz < 4_000_000 ? 1 : min(Threads.nthreads(), 8)
end

# Parse `path` into `pc` using `ntasks` chunk parsers. Returns false when a
# multi-task read is not possible (unknown row count, too few rows), in
# which case the caller falls back to a serial parse.
function threaded_parse!(pc::ParseContext, path::AbstractString, format::Symbol, ntasks::Int)
    pre = ParseContext()
    pre.usecols = pc.usecols
    pre.file_encoding = pc.file_encoding
    pre.handler_encoding = pc.handler_encoding
    pre.collect_values = false
    parse_file!(pre, path, format)

    total = pre.meta.row_count
    total < 0 && return false
    nrows = max(total - pc.row_offset, 0)
    pc.row_limit >= 0 && (nrows = min(nrows, pc.row_limit))
    if nrows == 0
        # Nothing to read; keep the pre-pass metadata over empty columns.
        empty = TypedColumns()
        for vm in pre.varmeta
            addcolumn!(empty, jltype(vm.type), 0)
        end
        _adopt!(pc, pre, empty)
        return true
    end
    ntasks = min(ntasks, nrows)
    if ntasks <= 1
        # Not worth splitting, but the pre-pass already paid for the
        # metadata; run the single data parse and keep the pre-pass results.
        chunk = _chunk_context(pc, pre, 0, nrows)
        parse_file!(chunk, path, format)
        _adopt!(pc, pre, chunk.cols)
        return true
    end

    shared = TypedColumns()
    for vm in pre.varmeta
        addcolumn!(shared, jltype(vm.type), nrows)
    end

    bounds = [round(Int, i * nrows / ntasks) for i in 0:ntasks]
    ctxs = Vector{ParseContext}(undef, ntasks)
    tasks = Vector{Task}(undef, ntasks)
    for i in 1:ntasks
        chunk = _chunk_context(pc, pre, bounds[i], bounds[i + 1] - bounds[i])
        chunk.cols = share_buffers(shared)
        chunk.preassigned_cols = true
        ctxs[i] = chunk
        tasks[i] = Threads.@spawn parse_file!($chunk, $path, $format)
    end
    firsterr = nothing
    for t in tasks
        try
            wait(t)
        catch e
            firsterr === nothing && (firsterr = e)
        end
    end
    if firsterr !== nothing
        throw(firsterr isa TaskFailedException ? firsterr.task.exception : firsterr)
    end

    # Merge the per-task tag vectors (each full-length, '\0' where untagged).
    for i in 1:length(shared.slots)
        buf = getbuf(shared, i)
        for chunk in ctxs
            t = column_tags(chunk.cols, i)
            t === nothing && continue
            dest = buf.tags
            dest === nothing && (buf.tags = dest = fill('\0', nrows))
            @inbounds for j in eachindex(t)
                t[j] != '\0' && (dest[j] = t[j])
            end
        end
    end

    _adopt!(pc, pre, shared)
    return true
end

function _chunk_context(pc::ParseContext, pre::ParseContext, base::Int, len::Int)
    chunk = ParseContext()
    chunk.usecols = pc.usecols
    chunk.file_encoding = pc.file_encoding
    chunk.handler_encoding = pc.handler_encoding
    chunk.keep_user_missing = pc.keep_user_missing
    chunk.row_offset = pc.row_offset + base
    chunk.row_limit = len
    chunk.row_base = base
    return chunk
end

# Take over the pre-pass metadata and the filled buffers as this context's
# parse result, so the ordinary build_table path applies.
function _adopt!(pc::ParseContext, pre::ParseContext, cols::TypedColumns)
    pc.meta = pre.meta
    pc.names = pre.names
    pc.varmeta = pre.varmeta
    pc.cols = cols
    return pc
end
