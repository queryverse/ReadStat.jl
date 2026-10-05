# High-level writing: columns plus names (Queryverse-style, not a table
# protocol) or a ReadStatTable, canonicalized onto the six storage types the
# formats support, with metadata, value labels, tagged missings, and
# date/time re-encoding.

const _WRITE_PRODUCER = Dict(:dta => :dta, :sav => :spss, :por => :spss,
    :sas7bdat => :sas, :xport => :sas)

# A column ready for the row loop: canonical storage values, NA mask access
# through the DataValueVector API, per-row tags, and variable attributes.
struct PreparedColumn
    data::AbstractVector      # DataValueVector{S} with S one of the 6 storage types
    type::ReadStatType
    storage_width::Int
    format::String            # derived format ("" = keep caller's hint)
    tags::Union{Nothing,Vector{Char}}
end

_plain_to_dv(v::AbstractVector{T}) where {T} = DataValueVector{T}(collect(v), fill(false, length(v)))

function _prepare_column(col::AbstractVector, producer::Symbol, convert_datetime::Bool,
                         format::Symbol, tags::Union{Nothing,Vector{Char}})
    col isa LabeledArray && return _prepare_column(rawvalues(col), producer, convert_datetime,
        format, tags)
    col isa DataValueVector || (col = _plain_to_dv(col))
    T = eltype(eltype(col))
    n = length(col)

    # The por writer only handles doubles (the format is text-based), so
    # every numeric column becomes Float64 there.
    if T <: Real && format === :por && T !== Float64
        out = DataValueVector{Float64}(Vector{Float64}(undef, n), fill(true, n))
        for i in 1:n
            DataValues.isna(col[i]) || (out[i] = Float64(get(col[i])))
        end
        return PreparedColumn(out, READSTAT_TYPE_DOUBLE, 0, "", tags)
    elseif T === Bool
        out = DataValueVector{Int8}(Vector{Int8}(undef, n), fill(true, n))
        for i in 1:n
            DataValues.isna(col[i]) || (out[i] = Int8(get(col[i])))
        end
        return PreparedColumn(out, READSTAT_TYPE_INT8, 0, "", tags)
    elseif T === Int8 || T === Int16 || T === Int32 || T === Float32 || T === Float64
        width = format === :xport && T === Float64 ? 8 : 0
        return PreparedColumn(col, rstype(T), width, "", tags)
    elseif T <: Integer
        # Narrow to Int32 when every value fits, otherwise go through Float64.
        fits = all(i -> DataValues.isna(col[i]) ||
            typemin(Int32) <= get(col[i]) <= typemax(Int32), 1:n)
        S = fits ? Int32 : Float64
        out = DataValueVector{S}(Vector{S}(undef, n), fill(true, n))
        for i in 1:n
            DataValues.isna(col[i]) || (out[i] = S(get(col[i])))
        end
        return PreparedColumn(out, rstype(S), 0, "", tags)
    elseif T <: Real
        out = DataValueVector{Float64}(Vector{Float64}(undef, n), fill(true, n))
        for i in 1:n
            DataValues.isna(col[i]) || (out[i] = Float64(get(col[i])))
        end
        return PreparedColumn(out, READSTAT_TYPE_DOUBLE, 0, "", tags)
    elseif T <: AbstractString
        out = DataValueVector{String}(fill("", n), fill(true, n))
        width = 1
        for i in 1:n
            if !DataValues.isna(col[i])
                s = String(get(col[i]))
                out[i] = s
                width = max(width, sizeof(s))
            end
        end
        return PreparedColumn(out, READSTAT_TYPE_STRING, width, "", tags)
    elseif convert_datetime && (T === Date || T === DateTime || T === HMS || T === Time)
        f, S, fmt = _dt_encode(producer, T)
        out = DataValueVector{S}(Vector{S}(undef, n), fill(true, n))
        for i in 1:n
            DataValues.isna(col[i]) || (out[i] = f(get(col[i])))
        end
        width = format === :xport && S === Float64 ? 8 : 0
        return PreparedColumn(out, rstype(S), width, fmt, tags)
    else
        throw(ArgumentError("cannot write a column with element type $T" *
            (T in (Date, DateTime, HMS, Time) ? " with convert_datetime=false" : "")))
    end
end

function _dt_encode(producer::Symbol, ::Type{Date})
    if producer === :dta
        (d -> Int32(Dates.value(d - STATA_EPOCH_DATE)), Int32, "%td")
    elseif producer === :spss
        (d -> Float64(Dates.value(d - SPSS_EPOCH_DATE)) * 86400.0, Float64, "EDATE10")
    else
        (d -> Float64(Dates.value(d - SAS_EPOCH_DATE)), Float64, "YYMMDD10")
    end
end

function _dt_encode(producer::Symbol, ::Type{DateTime})
    if producer === :dta
        (dt -> Float64(Dates.value(dt - STATA_EPOCH_DATETIME)), Float64, "%tc")
    elseif producer === :spss
        (dt -> Float64(Dates.value(dt - SPSS_EPOCH_DATETIME)) / 1000.0, Float64, "DATETIME20")
    else
        (dt -> Float64(Dates.value(dt - SAS_EPOCH_DATETIME)) / 1000.0, Float64, "DATETIME19")
    end
end

_seconds(t::HMS) = unwrap(t)
_seconds(t::Time) = Dates.value(t) / 1.0e9

function _dt_encode(producer::Symbol, ::Type{T}) where {T<:Union{HMS,Time}}
    if producer === :dta
        # Stata has no pure time type; times of day become %tc datetimes on
        # the epoch day, matching common Stata practice.
        (t -> _seconds(t) * 1000.0, Float64, "%tcHH:MM:SS")
    else
        (t -> Float64(_seconds(t)), Float64, "TIME8")
    end
end

# Infer the C key type of a label set from its dictionary keys (Char keys
# label tagged missings and do not constrain the type).
function _label_set_type(dict::AbstractDict)
    keytypes = [typeof(k) for k in keys(dict) if !(k isa Char)]
    any(t -> t <: AbstractString, keytypes) && return READSTAT_TYPE_STRING
    any(t -> t <: AbstractFloat, keytypes) && return READSTAT_TYPE_DOUBLE
    return READSTAT_TYPE_INT32
end

function _write_label_sets!(w::Writer, value_labels)
    sets = Dict{Symbol,LabelSet}()
    for (name, dict) in value_labels
        ls = add_label_set!(w, _label_set_type(dict), name)
        for (k, v) in dict
            label!(ls, k, v)
        end
        sets[Symbol(name)] = ls
    end
    return sets
end

_getvec(v::Nothing, i) = nothing
_getvec(v::AbstractVector, i) = v[i]

function write_data_file(dest::Union{AbstractString,IO}, format::Symbol,
                         columns::AbstractVector, names::AbstractVector{Symbol};
                         labels::Union{Nothing,AbstractVector{<:AbstractString}}=nothing,
                         formats::Union{Nothing,AbstractVector{<:AbstractString}}=nothing,
                         value_labels=Dict{Symbol,ValueLabelDict}(),
                         vallabels::Union{Nothing,AbstractVector{Symbol}}=nothing,
                         measures::Union{Nothing,AbstractVector{ReadStatMeasure}}=nothing,
                         alignments::Union{Nothing,AbstractVector{ReadStatAlignment}}=nothing,
                         display_widths::Union{Nothing,AbstractVector{<:Integer}}=nothing,
                         missing_ranges::Union{Nothing,AbstractVector}=nothing,
                         tags::Union{Nothing,AbstractVector}=nothing,
                         file_label::AbstractString="", table_name::AbstractString="",
                         notes::AbstractVector{<:AbstractString}=String[],
                         timestamp::Union{Nothing,DateTime}=nothing,
                         version::Union{Nothing,Integer}=nothing,
                         compress::Symbol=:none, is_64bit::Bool=true,
                         fweight::Union{Nothing,Symbol}=nothing,
                         convert_datetime::Bool=true)
    ncols = length(columns)
    ncols == length(names) ||
        throw(ArgumentError("got $(length(columns)) columns for $(length(names)) names"))
    for (kw, v) in (("labels", labels), ("formats", formats), ("vallabels", vallabels),
                    ("measures", measures), ("alignments", alignments),
                    ("display_widths", display_widths), ("missing_ranges", missing_ranges),
                    ("tags", tags))
        v === nothing || length(v) == ncols ||
            throw(ArgumentError("$kw must have one entry per column"))
    end
    nrows = ncols == 0 ? 0 : length(columns[1])
    all(c -> length(c) == nrows, columns) ||
        throw(ArgumentError("all columns must have the same length"))

    # SPSS portable is an uppercase-only format; the C writer silently writes
    # no data under lowercase names, so normalize them here (a por read
    # returns uppercase names regardless).
    format === :por && (names = [Symbol(uppercase(String(n))) for n in names])

    producer = _WRITE_PRODUCER[format]
    prepared = PreparedColumn[
        _prepare_column(columns[i], producer, convert_datetime, format, _getvec(tags, i))
        for i in 1:ncols]

    w = Writer(dest)
    try
        sets = _write_label_sets!(w, value_labels)
        vars = Vector{WriterVariable}(undef, ncols)
        for i in 1:ncols
            p = prepared[i]
            # LabeledArray columns bring their own label set when none is named.
            vallabel = _getvec(vallabels, i)
            if vallabel === nothing && columns[i] isa LabeledArray
                vallabel = Symbol(:__auto_labels_, i)
                d = getvaluelabels(columns[i])
                ls = add_label_set!(w, _label_set_type(d), vallabel)
                for (k, v) in d
                    label!(ls, k, v)
                end
                sets[vallabel] = ls
            end
            fmt = p.format
            isempty(fmt) && formats !== nothing && (fmt = formats[i])
            ranges = missing_ranges === nothing ? () :
                Tuple((r isa Tuple ? r : (r, r)) for r in missing_ranges[i])
            vars[i] = add_variable!(w, names[i], p.type;
                storage_width=p.storage_width,
                label=labels === nothing ? "" : labels[i],
                format=fmt,
                label_set=vallabel === nothing || vallabel === Symbol("") ? nothing :
                    get(sets, vallabel, nothing),
                measure=measures === nothing ? READSTAT_MEASURE_UNKNOWN : measures[i],
                alignment=alignments === nothing ? READSTAT_ALIGNMENT_UNKNOWN : alignments[i],
                display_width=display_widths === nothing ? 0 : display_widths[i],
                missing_ranges=ranges)
        end
        isempty(file_label) || file_label!(w, file_label)
        isempty(table_name) || table_name!(w, table_name)
        timestamp === nothing || timestamp!(w, timestamp)
        version === nothing || format_version!(w, version)
        compress === :none || compression!(w, compress)
        format in (:sas7bdat, :xport) && is_64bit!(w, is_64bit)
        for note in notes
            add_note!(w, note)
        end
        if fweight !== nothing
            j = findfirst(==(fweight), names)
            j === nothing && throw(ArgumentError("fweight column $fweight not found"))
            fweight!(w, vars[j])
        end

        begin_writing!(w, format, nrows)
        for r in 1:nrows
            begin_row!(w)
            for i in 1:ncols
                _insert_cell!(w, vars[i], prepared[i], r)
            end
            end_row!(w)
        end
        end_writing!(w)
    finally
        close(w)
    end
    return dest
end

function _insert_cell!(w::Writer, var::WriterVariable, p::PreparedColumn, r::Int)
    t = p.tags
    if t !== nothing && t[r] != '\0'
        insert_tagged_missing!(w, var, t[r])
        return
    end
    _insert_cell!(w, var, p.data, r)
end

function _insert_cell!(w::Writer, var::WriterVariable, col::DataValueVector{T}, r::Int) where {T}
    v = col[r]
    DataValues.isna(v) ? insert_missing!(w, var) : insert_value!(w, var, get(v))
    return
end

const _WRITE_KWARGS_DOC = """
`columns` is a vector of columns (`DataValueVector`s, [`LabeledArray`](@ref)s
— which bring their value labels along — or plain vectors) and `names` the
matching column names. Keyword arguments, all optional:

- `labels`, `formats`, `measures`, `alignments`, `display_widths`: one
  variable attribute per column.
- `value_labels::Dict{Symbol,ValueLabelDict}` plus `vallabels` (one label-set
  name per column, `Symbol("")` for none): explicit value-label sets.
- `missing_ranges`: per column, a collection of SPSS user-missing values or
  `(lo, hi)` range tuples.
- `tags`: per column, `nothing` or a `Vector{Char}` marking tagged missing
  values (`'a'`-`'z'`, `'\\0'` elsewhere; Stata/SAS formats).
- `file_label`, `notes`, `timestamp`, `version`, `table_name` (XPORT),
  `is_64bit` (SAS), `compress` (`:rows` for sas7bdat/sav, `:binary` for
  zsav), `fweight` (name of the frequency-weight column).
- `convert_datetime=true`: encode `Date`/`DateTime`/[`HMS`](@ref)/`Time`
  columns into the format's native representation with a matching display
  format.

Instead of a path, `dest` may be any writable `IO`.
"""

for (fn, fmt) in ((:write_dta, :dta), (:write_sav, :sav), (:write_por, :por),
                  (:write_sas7bdat, :sas7bdat), (:write_xport, :xport))
    @eval begin
        """
            $($(string(fn)))(dest, columns, names::Vector{Symbol}; kwargs...)
            $($(string(fn)))(dest, tbl::ReadStatTable; kwargs...)

        Write columns to $($(string(fmt))) format.

        $_WRITE_KWARGS_DOC
        """
        $fn(dest::Union{AbstractString,IO}, columns::AbstractVector,
            names::AbstractVector{Symbol}; kwargs...) =
            write_data_file(dest, $(QuoteNode(fmt)), columns, names; kwargs...)
        $fn(dest::Union{AbstractString,IO}, tbl::ReadStatTable; kwargs...) =
            _write_table(dest, $(QuoteNode(fmt)), tbl; kwargs...)
    end
end

"""
    write_sas7bcat(dest, value_labels::Dict{Symbol,<:AbstractDict})

Write a SAS value-label catalog holding the given label sets (as read by
[`read_sas7bcat`](@ref)).

!!! warning
    The catalog writer in readstat 1.1.9 only handles numeric label sets
    correctly; string-keyed sets do not survive a round trip.
"""
function write_sas7bcat(dest::Union{AbstractString,IO}, value_labels::AbstractDict)
    w = Writer(dest)
    try
        _write_label_sets!(w, value_labels)
        begin_writing!(w, :sas7bcat)
        end_writing!(w)
    finally
        close(w)
    end
    return dest
end

# Write a ReadStatTable, carrying its metadata across; explicit keyword
# arguments override what the table provides.
function _write_table(dest, format::Symbol, tbl::ReadStatTable; kwargs...)
    meta = filemetadata(tbl)
    colmeta = getfield(tbl, :colmeta)
    columns = getfield(tbl, :cols)
    provided = (;
        labels=[m.label for m in colmeta],
        value_labels=meta.value_labels,
        vallabels=[m.vallabel for m in colmeta],
        measures=[m.measure for m in colmeta],
        alignments=[m.alignment for m in colmeta],
        tags=getfield(tbl, :tags),
        file_label=meta.file_label,
        notes=meta.notes,
        fweight=meta.fweight === Symbol("") ? nothing : meta.fweight,
    )
    return write_data_file(dest, format, columns, names(tbl);
        merge(provided, NamedTuple(kwargs))...)
end
