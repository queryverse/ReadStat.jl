"""
    ReadStatTable

The result of reading a stat-package file: a set of named `DataValueVector`
columns plus the file's complete metadata.

Columns are accessed by position (`tbl[1]`) or name (`tbl[:price]`);
`names(tbl)` lists the column names and `size(tbl)` returns
`(rows, columns)`. File-level metadata is available via
[`filemetadata`](@ref), per-variable metadata via [`varmetadata`](@ref), and
value-label sets via [`valuelabels`](@ref).
"""
struct ReadStatTable
    cols::Vector{AbstractVector}
    names::Vector{Symbol}
    lookup::Dict{Symbol,Int}
    meta::ReadStatMeta
    colmeta::Vector{ReadStatVarMeta}
    # Per-column tags of tagged missing values ('a'-'z'; '\0' where untagged),
    # allocated lazily only for columns that contain any.
    tags::Vector{Union{Nothing,Vector{Char}}}
end

function ReadStatTable(cols::Vector{AbstractVector}, names::Vector{Symbol},
                       meta::ReadStatMeta, colmeta::Vector{ReadStatVarMeta})
    lookup = Dict{Symbol,Int}(name => i for (i, name) in enumerate(names))
    tags = Union{Nothing,Vector{Char}}[nothing for _ in names]
    return ReadStatTable(cols, names, lookup, meta, colmeta, tags)
end

ncols(tbl::ReadStatTable) = length(getfield(tbl, :cols))
nrows(tbl::ReadStatTable) = ncols(tbl) == 0 ? 0 : length(getfield(tbl, :cols)[1])

Base.names(tbl::ReadStatTable) = getfield(tbl, :names)
Base.size(tbl::ReadStatTable) = (nrows(tbl), ncols(tbl))
function Base.size(tbl::ReadStatTable, dim::Integer)
    dim == 1 ? nrows(tbl) : dim == 2 ? ncols(tbl) :
        throw(ArgumentError("dimension must be 1 or 2"))
end

function columnindex(tbl::ReadStatTable, name::Symbol)
    i = get(getfield(tbl, :lookup), name, 0)
    i == 0 && throw(ArgumentError("no column named $name"))
    return i
end
columnindex(tbl::ReadStatTable, i::Integer) = Int(i)

Base.getindex(tbl::ReadStatTable, i::Integer) = getfield(tbl, :cols)[i]
Base.getindex(tbl::ReadStatTable, name::Symbol) = getfield(tbl, :cols)[columnindex(tbl, name)]

"""
    filemetadata(tbl::ReadStatTable) -> ReadStatMeta

The file-level metadata of the table: row/variable counts as recorded in the
file, timestamps, format version, compression, endianness, file label,
encoding, notes, and all value-label sets.
"""
filemetadata(tbl::ReadStatTable) = getfield(tbl, :meta)

"""
    varmetadata(tbl::ReadStatTable, col) -> ReadStatVarMeta

Per-variable metadata for the column given by index or name: variable label,
display format, raw storage type, value-label set name, widths, measure,
alignment, and SPSS missing-value rules.
"""
varmetadata(tbl::ReadStatTable, col::Union{Integer,Symbol}) =
    getfield(tbl, :colmeta)[columnindex(tbl, col)]

"""
    valuelabels(tbl::ReadStatTable, col) -> Union{Nothing, ValueLabelDict}

The value-label dictionary attached to the column given by index or name, or
`nothing` when the column has no value labels. The returned dictionary maps
raw values (and `Char` tags of labeled tagged missing values) to their
labels.
"""
function valuelabels(tbl::ReadStatTable, col::Union{Integer,Symbol})
    vm = varmetadata(tbl, col)
    vm.vallabel === Symbol("") && return nothing
    return get(filemetadata(tbl).value_labels, vm.vallabel, nothing)
end

##############################################################################
##
## Display
##
##############################################################################

function Base.show(io::IO, tbl::ReadStatTable)
    r, c = size(tbl)
    print(io, "$(r)x$(c) ReadStatTable")
end

function Base.show(io::IO, ::MIME"text/plain", tbl::ReadStatTable)
    r, c = size(tbl)
    meta = filemetadata(tbl)
    print(io, "$(r)x$(c) ReadStatTable")
    isempty(meta.file_label) || print(io, ": ", meta.file_label)
    c == 0 && return

    maxrows = min(r, get(io, :limit, true) ? 10 : r)
    maxcols = min(c, 20)
    cells = Matrix{String}(undef, maxrows + 1, maxcols)
    for j in 1:maxcols
        cells[1, j] = string(names(tbl)[j])
        col = tbl[j]
        for i in 1:maxrows
            cells[i + 1, j] = _showcell(col[i])
        end
    end
    widths = [maximum(textwidth, view(cells, :, j)) for j in 1:maxcols]
    for i in 1:(maxrows + 1)
        print(io, "\n  ")
        for j in 1:maxcols
            print(io, lpad(cells[i, j], widths[j]))
            j < maxcols && print(io, "  ")
        end
        c > maxcols && print(io, "  …")
        if i == 1
            print(io, "\n  ", join([repeat("─", w) for w in widths], "  "))
        end
    end
    maxrows < r && print(io, "\n  ⋮ ($(r - maxrows) more rows)")
    return
end

_showcell(v) = sprint(print, v)
_showcell(v::DataValues.DataValue) = DataValues.isna(v) ? "NA" : sprint(print, get(v))
