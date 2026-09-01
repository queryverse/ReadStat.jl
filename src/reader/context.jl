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
end

ParseContext() = ParseContext(ReadStatMeta(), Symbol[], ReadStatVarMeta[], TypedColumns(), nothing)
