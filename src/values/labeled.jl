# A lazily labeled view of a value-labeled column.
#
# Stat packages store "categorical" columns as raw codes plus a (possibly
# partial) label set. A LabeledArray keeps the raw code column untouched and
# looks labels up only on access, so nothing is lost (codes, gaps, unlabeled
# values, ordering) and nothing is paid when the view is not used. This is
# deliberately a partial dictionary encoding, not a categorical/factor type:
# unlabeled codes remain first-class values that merely display as
# `string(code)`.

"""
    LabeledValue{T}

A single value from a value-labeled column: the raw code of type `T` plus a
reference to the column's shared label dictionary. It displays as its label
(falling back to `string(code)` when the code has no label) but computes as
its code: `==`, `isless`, and `hash` all act on the code, so predicates,
joins, and grouping behave exactly as on the raw column. Comparing against
an `AbstractString` compares the label instead.

Access the parts with [`unwrap`](@ref) (the code) and [`valuelabel`](@ref)
(the label).
"""
struct LabeledValue{T}
    value::T
    labels::ValueLabelDict
end

"""
    unwrap(lv::LabeledValue{T}) -> T

The raw code stored in a labeled value.
"""
unwrap(lv::LabeledValue) = lv.value

_labelkey(v::Integer) = Int32(v)
_labelkey(v::AbstractFloat) = Float64(v)
_labelkey(v::AbstractString) = String(v)

"""
    valuelabel(lv::LabeledValue) -> String

The label of a labeled value, or `string(unwrap(lv))` when its code has no
label in the column's label set.
"""
valuelabel(lv::LabeledValue) = get(() -> string(lv.value), lv.labels, _labelkey(lv.value))

Base.:(==)(a::LabeledValue, b::LabeledValue) = a.value == b.value
Base.:(==)(a::LabeledValue, b::Number) = a.value == b
Base.:(==)(a::Number, b::LabeledValue) = a == b.value
Base.:(==)(a::LabeledValue, b::AbstractString) = valuelabel(a) == b
Base.:(==)(a::AbstractString, b::LabeledValue) = a == valuelabel(b)
Base.isequal(a::LabeledValue, b::LabeledValue) = isequal(a.value, b.value)
Base.isless(a::LabeledValue, b::LabeledValue) = isless(a.value, b.value)
Base.isless(a::LabeledValue, b::Number) = isless(a.value, b)
Base.isless(a::Number, b::LabeledValue) = isless(a, b.value)
Base.hash(lv::LabeledValue, h::UInt) = hash(lv.value, h)

Base.show(io::IO, lv::LabeledValue) = print(io, valuelabel(lv))
function Base.show(io::IO, ::MIME"text/plain", lv::LabeledValue)
    print(io, valuelabel(lv), " (", lv.value, ")")
end

"""
    LabeledArray{T} <: AbstractVector{DataValue{LabeledValue{T}}}

A lazy labeled view of a value-labeled column: wraps the raw
`DataValueVector` of codes plus the shared label dictionary, constructing
[`LabeledValue`](@ref)s only on access. NA cells stay NA. Obtain one with
[`labeled`](@ref) or by reading with `apply_value_labels=true`; get the raw
column back with [`rawvalues`](@ref) (zero-copy) and the dictionary with
`getvaluelabels`.
"""
struct LabeledArray{T} <: AbstractVector{DataValues.DataValue{LabeledValue{T}}}
    values::DataValueVector{T}
    labels::ValueLabelDict
end

"""
    rawvalues(a::LabeledArray) -> DataValueVector

The raw code column underlying a labeled view (zero-copy).
"""
rawvalues(a::LabeledArray) = a.values

"""
    getvaluelabels(a::LabeledArray) -> ValueLabelDict

The label dictionary shared by the elements of a labeled view.
"""
getvaluelabels(a::LabeledArray) = a.labels

Base.size(a::LabeledArray) = size(a.values)
Base.IndexStyle(::Type{<:LabeledArray}) = IndexLinear()

function Base.getindex(a::LabeledArray{T}, i::Int) where {T}
    v = a.values[i]
    DataValues.isna(v) ? DataValues.DataValue{LabeledValue{T}}() :
        DataValues.DataValue(LabeledValue{T}(get(v), a.labels))
end

Base.setindex!(a::LabeledArray{T}, v, i::Int) where {T} = (a.values[i] = v; a)
Base.setindex!(a::LabeledArray{T}, v::LabeledValue, i::Int) where {T} =
    (a.values[i] = unwrap(v); a)
