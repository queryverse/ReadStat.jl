# Per-parse state. One ParseContext per parser; nothing here is shared, so a
# future multi-parser run needs no synchronization beyond disjoint buffers.

mutable struct ParseContext
    meta::ReadStatMeta
    names::Vector{Symbol}
    varmeta::Vector{ReadStatVarMeta}
    cols::TypedColumns
    # Exception thrown by a handler, captured so it never unwinds through C;
    # rethrown by the parse driver after readstat_parse returns.
    err::Union{Nothing,Tuple{Any,Any}}
    # Messages the C library reports through its error handler; surfaced as
    # Julia warnings after the parse.
    warnings::Vector{String}

    # Configuration for this parse:
    usecols::Union{Nothing,Function}      # (name::Symbol, index::Int) -> Bool
    progress::Union{Nothing,Function}     # (fraction::Float64) -> Bool (false aborts)
    row_offset::Int                       # 0 = from the start
    row_limit::Int                        # -1 = no limit
    file_encoding::Union{Nothing,String}
    handler_encoding::Union{Nothing,String}
    collect_values::Bool
    # true: SPSS user-defined missing values are kept as data (only system
    # and tagged missings become NA); false: they collapse to NA.
    keep_user_missing::Bool                  # false for metadata-only parses

    # Progress-abort bookkeeping: the last fully delivered row, so a
    # partially parsed table can be trimmed to complete rows.
    aborted::Bool
    rows_complete::Int
end

ParseContext() = ParseContext(ReadStatMeta(), Symbol[], ReadStatVarMeta[], TypedColumns(),
    nothing, String[], nothing, nothing, 0, -1, nothing, nothing, true, false, false, 0)

# Rows to preallocate per column: what the file reports, minus the offset,
# capped by the limit; 0 when unknown (buffers then grow row by row).
function alloc_rows(pc::ParseContext)
    pc.collect_values || return 0
    rc = pc.meta.row_count
    rc < 0 && return 0
    n = max(rc - pc.row_offset, 0)
    pc.row_limit >= 0 && (n = min(n, pc.row_limit))
    return n
end
