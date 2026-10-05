# 1.x compatibility shims, to be removed in 3.0.
#
# ReadStat 1.x returned a `ReadStatDataFrame` whose data and metadata were
# reached through 15 public fields. The old name aliases the new table type,
# and property access reconstructs the old field values with a deprecation
# warning, so existing consumers (StatFiles.jl in particular uses `.data` and
# `.headers`) keep working against 2.0.

"""
    ReadStatDataFrame

Deprecated alias for [`ReadStatTable`](@ref). The 1.x field access
(`df.data`, `df.headers`, ...) still works but emits deprecation warnings;
use the 2.0 accessors instead.
"""
const ReadStatDataFrame = ReadStatTable

function _dep(old::Symbol, instead::AbstractString)
    Base.depwarn("`ReadStatDataFrame.$old` is deprecated; use $instead instead.", old)
end

function Base.getproperty(tbl::ReadStatTable, s::Symbol)
    if s === :cols || s === :names || s === :lookup || s === :meta || s === :colmeta || s === :tags
        return getfield(tbl, s)
    elseif s === :data
        _dep(s, "`tbl[i]` / `tbl[:name]`")
        return Any[c for c in getfield(tbl, :cols)]
    elseif s === :headers
        _dep(s, "`names(tbl)`")
        return copy(getfield(tbl, :names))
    elseif s === :types
        _dep(s, "`eltype(eltype(tbl[i]))`")
        return DataType[jltype(m.type) for m in getfield(tbl, :colmeta)]
    elseif s === :labels
        _dep(s, "`varmetadata(tbl, i).label`")
        return String[m.label for m in getfield(tbl, :colmeta)]
    elseif s === :formats
        _dep(s, "`varmetadata(tbl, i).format`")
        return String[m.format for m in getfield(tbl, :colmeta)]
    elseif s === :storagewidths
        _dep(s, "`varmetadata(tbl, i).storage_width`")
        return Csize_t[m.storage_width for m in getfield(tbl, :colmeta)]
    elseif s === :measures
        _dep(s, "`varmetadata(tbl, i).measure`")
        return Cint[Cint(Int(m.measure)) for m in getfield(tbl, :colmeta)]
    elseif s === :alignments
        _dep(s, "`varmetadata(tbl, i).alignment`")
        return Cint[Cint(Int(m.alignment)) for m in getfield(tbl, :colmeta)]
    elseif s === :val_label_keys
        _dep(s, "`varmetadata(tbl, i).vallabel`")
        return String[string(m.vallabel) for m in getfield(tbl, :colmeta)]
    elseif s === :val_label_dict
        _dep(s, "`valuelabels(tbl, col)` / `filemetadata(tbl).value_labels`")
        return Dict{String,Dict{Any,String}}(
            string(k) => Dict{Any,String}(kk => vv for (kk, vv) in v)
            for (k, v) in getfield(tbl, :meta).value_labels)
    elseif s === :rows
        _dep(s, "`size(tbl, 1)` or `filemetadata(tbl).row_count`")
        return getfield(tbl, :meta).row_count
    elseif s === :columns
        _dep(s, "`size(tbl, 2)`")
        return getfield(tbl, :meta).var_count
    elseif s === :filelabel
        _dep(s, "`filemetadata(tbl).file_label`")
        return getfield(tbl, :meta).file_label
    elseif s === :timestamp
        _dep(s, "`filemetadata(tbl).modified_time`")
        return getfield(tbl, :meta).modified_time
    elseif s === :format
        _dep(s, "`filemetadata(tbl).file_format_version`")
        return Clong(getfield(tbl, :meta).file_format_version)
    elseif s === :types_as_int
        _dep(s, "`varmetadata(tbl, i).type`")
        return Cint[Cint(Int(m.type)) for m in getfield(tbl, :colmeta)]
    elseif s === :hasmissings
        _dep(s, "`varmetadata(tbl, i).missing_ranges`")
        return Bool[!isempty(m.missing_ranges) for m in getfield(tbl, :colmeta)]
    else
        # Fall through for reflection etc.
        return getfield(tbl, s)
    end
end

function Base.propertynames(::ReadStatTable, private::Bool=false)
    private ? (fieldnames(ReadStatTable)..., DEPRECATED_PROPERTIES...) : DEPRECATED_PROPERTIES
end

const DEPRECATED_PROPERTIES = (:data, :headers, :types, :labels, :formats, :storagewidths,
    :measures, :alignments, :val_label_keys, :val_label_dict, :rows, :columns, :filelabel,
    :timestamp, :format, :types_as_int, :hasmissings)
