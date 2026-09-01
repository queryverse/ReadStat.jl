# Typed column buffers filled by the value handler.
#
# Columns are parsed into raw `Vector{T}` + `Vector{Bool}` NA-mask pairs and
# only wrapped into `DataValueVector`s once parsing is done. This keeps the
# hot path free of any DataValues internals (whose representation may change)
# and lets a future multi-parser run fill disjoint row regions of shared
# buffers from several threads — plain `Vector` writes to disjoint indices
# are thread-safe, which would not hold for a shared bit-packed mask.
#
# The mask starts all-`true` (every cell missing until the C library delivers
# it), so cells the parser never emits surface as NA rather than as undefined
# memory. String buffers are backed by `""` so every slot is always a defined
# object.

struct ColumnBuf{T}
    values::Vector{T}
    isna::Vector{Bool}
end

newbuf(::Type{T}, n::Int) where {T} = ColumnBuf{T}(Vector{T}(undef, n), fill(true, n))
newbuf(::Type{String}, n::Int) = ColumnBuf{String}(fill("", n), fill(true, n))

# Column storage grouped by element type, so every access from the value
# handler goes through a small typecode branch into fully type-stable code
# instead of a `Vector{Any}` of columns. `slots[i]` maps the i-th kept column
# (C `index_after_skipping` plus one) to `(typecode, index)` within the
# matching typed vector.
struct TypedColumns
    strings::Vector{ColumnBuf{String}}
    int8s::Vector{ColumnBuf{Int8}}
    int16s::Vector{ColumnBuf{Int16}}
    int32s::Vector{ColumnBuf{Int32}}
    floats::Vector{ColumnBuf{Float32}}
    doubles::Vector{ColumnBuf{Float64}}
    slots::Vector{Tuple{UInt8,Int}}
end

TypedColumns() = TypedColumns(ColumnBuf{String}[], ColumnBuf{Int8}[], ColumnBuf{Int16}[],
    ColumnBuf{Int32}[], ColumnBuf{Float32}[], ColumnBuf{Float64}[], Tuple{UInt8,Int}[])

const CODE_STRING = 0x01
const CODE_INT8 = 0x02
const CODE_INT16 = 0x03
const CODE_INT32 = 0x04
const CODE_FLOAT = 0x05
const CODE_DOUBLE = 0x06

# `n` is the preallocated length; pass 0 when the row count is unknown and
# the buffers grow row by row instead.
function addcolumn!(cols::TypedColumns, T::DataType, n::Int)
    if T === String
        push!(cols.strings, newbuf(String, n))
        push!(cols.slots, (CODE_STRING, length(cols.strings)))
    elseif T === Int8
        push!(cols.int8s, newbuf(Int8, n))
        push!(cols.slots, (CODE_INT8, length(cols.int8s)))
    elseif T === Int16
        push!(cols.int16s, newbuf(Int16, n))
        push!(cols.slots, (CODE_INT16, length(cols.int16s)))
    elseif T === Int32
        push!(cols.int32s, newbuf(Int32, n))
        push!(cols.slots, (CODE_INT32, length(cols.int32s)))
    elseif T === Float32
        push!(cols.floats, newbuf(Float32, n))
        push!(cols.slots, (CODE_FLOAT, length(cols.floats)))
    elseif T === Float64
        push!(cols.doubles, newbuf(Float64, n))
        push!(cols.slots, (CODE_DOUBLE, length(cols.doubles)))
    else
        throw(ArgumentError("unsupported column type $T"))
    end
    return cols
end

@inline function setvalue!(buf::ColumnBuf{T}, row::Int, v::T) where {T}
    n = length(buf.values)
    if row <= n
        @inbounds buf.values[row] = v
        @inbounds buf.isna[row] = false
    elseif row == n + 1
        push!(buf.values, v)
        push!(buf.isna, false)
    else
        throw(ArgumentError("out-of-order row index $row for column of length $n"))
    end
    return buf
end

@inline function setmissing!(buf::ColumnBuf{T}, row::Int) where {T}
    n = length(buf.values)
    if row <= n
        @inbounds buf.isna[row] = true
    elseif row == n + 1
        push!(buf.values, _navalue(T))
        push!(buf.isna, true)
    else
        throw(ArgumentError("out-of-order row index $row for column of length $n"))
    end
    return buf
end

_navalue(::Type{T}) where {T<:Number} = zero(T)
_navalue(::Type{String}) = ""

function trim!(buf::ColumnBuf, n::Int)
    if length(buf.values) > n
        resize!(buf.values, n)
        resize!(buf.isna, n)
    end
    return buf
end

# Trim every buffer to `n` rows (used when a parse was stopped early and the
# preallocated or partially filled buffers extend past the last complete row).
function trimcolumns!(cols::TypedColumns, n::Int)
    for group in (cols.strings, cols.int8s, cols.int16s, cols.int32s, cols.floats, cols.doubles)
        foreach(buf -> trim!(buf, n), group)
    end
    return cols
end

# Wrap a finished buffer without copying. The constructor takes ownership of
# both vectors; nothing may touch the ColumnBuf afterwards.
finalize_column(buf::ColumnBuf{T}) where {T} = DataValueVector{T}(buf.values, buf.isna)

function finalize_column(cols::TypedColumns, i::Int)
    code, slot = cols.slots[i]
    if code == CODE_STRING
        finalize_column(cols.strings[slot])
    elseif code == CODE_INT8
        finalize_column(cols.int8s[slot])
    elseif code == CODE_INT16
        finalize_column(cols.int16s[slot])
    elseif code == CODE_INT32
        finalize_column(cols.int32s[slot])
    elseif code == CODE_FLOAT
        finalize_column(cols.floats[slot])
    else
        finalize_column(cols.doubles[slot])
    end
end
