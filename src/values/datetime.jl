# Date/time decoding driven by the producers' display-format strings.
#
# Stat packages store dates and times as plain numbers plus a display format;
# the format string is the only record of which numbers are calendar values.
# The tables below map format names to (kind, epoch, unit) rules per
# producer: Stata counts from 1960-01-01 (milliseconds for %tc, days for %td,
# plus week/month/quarter/half-year/year counts), SAS counts seconds or days
# from 1960-01-01, and SPSS counts seconds from 1582-10-14. Times of day are
# plain second counts that may exceed 24 hours (durations), which
# `Dates.Time` cannot represent — they decode into `HMS`.

"""
    HMS

A time of day or duration as a number of seconds, with unbounded hours: SAS
and SPSS time values can exceed 24 hours or be negative, which `Dates.Time`
cannot represent. Displays as `H:MM:SS[.fff]`; access the raw seconds with
[`unwrap`](@ref), the parts with `Dates.hour`/`minute`/`second`, and convert
to `Dates.Time` via `Time(hms)` when the value is within a calendar day.
"""
struct HMS
    seconds::Float64
end

"""
    unwrap(t::HMS) -> Float64

The raw number of seconds in an `HMS` value.
"""
unwrap(t::HMS) = t.seconds

Base.:(==)(a::HMS, b::HMS) = a.seconds == b.seconds
Base.isequal(a::HMS, b::HMS) = isequal(a.seconds, b.seconds)
Base.isless(a::HMS, b::HMS) = isless(a.seconds, b.seconds)
Base.hash(t::HMS, h::UInt) = hash(t.seconds, hash(:HMS, h))

Dates.hour(t::HMS) =
    t.seconds < 0 ? -Int(fld(-t.seconds, 3600)) : Int(fld(t.seconds, 3600))
Dates.minute(t::HMS) = Int(fld(mod(abs(t.seconds), 3600), 60))
Dates.second(t::HMS) = floor(Int, mod(abs(t.seconds), 60))
Dates.millisecond(t::HMS) = round(Int, mod(abs(t.seconds), 1) * 1000)

function Dates.Time(t::HMS)
    0 <= t.seconds < 86400 ||
        throw(ArgumentError("HMS value $(t) is outside a calendar day"))
    return Time(0) + Millisecond(round(Int64, t.seconds * 1000))
end

function Base.show(io::IO, t::HMS)
    s = abs(t.seconds)
    t.seconds < 0 && print(io, '-')
    print(io, Int(fld(s, 3600)), ':', lpad(Int(fld(mod(s, 3600), 60)), 2, '0'), ':')
    sec = mod(s, 60)
    isec = floor(Int, sec)
    print(io, lpad(isec, 2, '0'))
    frac = sec - isec
    frac > 0 && print(io, '.', lpad(round(Int, frac * 1000), 3, '0'))
    return
end

##############################################################################
##
## Format classification
##
##############################################################################

const STATA_EPOCH_DATETIME = DateTime(1960, 1, 1)
const STATA_EPOCH_DATE = Date(1960, 1, 1)
const SAS_EPOCH_DATETIME = DateTime(1960, 1, 1)
const SAS_EPOCH_DATE = Date(1960, 1, 1)
const SPSS_EPOCH_DATETIME = DateTime(1582, 10, 14)
const SPSS_EPOCH_DATE = Date(1582, 10, 14)

# SAS format base names (with trailing width digits and decimals stripped).
const SAS_DATETIME_FORMATS = Set(["DATETIME", "E8601DT", "E8601DX", "E8601DZ",
    "E8601LX", "E8601DN", "E8601LZ", "E8601TX", "E8601TZ"])
const SAS_DATE_FORMATS = Set(["DATE", "WEEKDATE", "WEEKDATX", "WEEKDAY", "MMDDYY",
    "DDMMYY", "YYMMDD", "DDMMYYB", "DDMMYYC", "DDMMYYD", "DDMMYYN", "DDMMYYP",
    "DDMMYYS", "MMDDYYB", "MMDDYYC", "MMDDYYD", "MMDDYYN", "MMDDYYP", "MMDDYYS",
    "YYMMDDB", "YYMMDDD", "YYMMDDN", "YYMMDDP", "YYMMDDS", "MONNAME", "MONTH",
    "MONYY", "QTR", "QTRR", "YEAR", "DAY", "DOWNAME", "JULIAN", "E8601DA"])
const SAS_TIME_FORMATS = Set(["TIME", "HHMM", "HOUR", "MMSS", "E8601TM"])

# SPSS format base names.
const SPSS_DATETIME_FORMATS = Set(["DATETIME", "YMDHMS"])
const SPSS_DATE_FORMATS = Set(["DATE", "ADATE", "EDATE", "JDATE", "SDATE"])
const SPSS_TIME_FORMATS = Set(["TIME", "DTIME"])

# "DATETIME22.3" -> "DATETIME", "EDATE10" -> "EDATE", "E8601DA" -> "E8601DA".
_format_base(fmt::AbstractString) =
    replace(replace(uppercase(fmt), r"\.\d*$" => ""), r"\d+$" => "")

# Classify a format string into a converter function (applied to non-missing
# numeric cells) and a target element type, or `nothing` when the column is
# not a date/time.
function datetime_rule(fmt::AbstractString, producer::Symbol)
    isempty(fmt) && return nothing
    if producer === :dta
        if startswith(fmt, "%tc") || startswith(fmt, "%tC") ||
           startswith(fmt, "%-tc") || startswith(fmt, "%-tC")
            return (v -> STATA_EPOCH_DATETIME + Millisecond(round(Int64, Float64(v)))), DateTime
        elseif startswith(fmt, "%td") || startswith(fmt, "%-td") || startswith(fmt, "%d") ||
               startswith(fmt, "%-d")
            return (v -> STATA_EPOCH_DATE + Day(round(Int64, Float64(v)))), Date
        elseif startswith(fmt, "%tw")
            # Stata weeks reset every year: 52 fixed-length weeks per year.
            return (v -> (i = round(Int64, Float64(v));
                          Date(1960 + fld(i, 52), 1, 1) + Week(mod(i, 52)))), Date
        elseif startswith(fmt, "%tm")
            return (v -> STATA_EPOCH_DATE + Month(round(Int64, Float64(v)))), Date
        elseif startswith(fmt, "%tq")
            return (v -> STATA_EPOCH_DATE + Month(3 * round(Int64, Float64(v)))), Date
        elseif startswith(fmt, "%th")
            return (v -> STATA_EPOCH_DATE + Month(6 * round(Int64, Float64(v)))), Date
        elseif startswith(fmt, "%ty")
            return (v -> Date(round(Int64, Float64(v)), 1, 1)), Date
        end
        return nothing
    elseif producer === :sas7bdat || producer === :xport
        base = _format_base(fmt)
        if base in SAS_DATETIME_FORMATS
            return (v -> SAS_EPOCH_DATETIME + Millisecond(round(Int64, Float64(v) * 1000))), DateTime
        elseif base in SAS_DATE_FORMATS
            return (v -> SAS_EPOCH_DATE + Day(round(Int64, Float64(v)))), Date
        elseif base in SAS_TIME_FORMATS
            return (v -> HMS(Float64(v))), HMS
        end
        return nothing
    elseif producer === :sav || producer === :por
        base = _format_base(fmt)
        if base in SPSS_DATETIME_FORMATS
            return (v -> SPSS_EPOCH_DATETIME + Millisecond(round(Int64, Float64(v) * 1000))), DateTime
        elseif base in SPSS_DATE_FORMATS
            return (v -> SPSS_EPOCH_DATE + Day(fld(round(Int64, Float64(v)), 86400))), Date
        elseif base in SPSS_TIME_FORMATS
            return (v -> HMS(Float64(v))), HMS
        end
        return nothing
    end
    return nothing
end

# Convert a numeric column to Date/DateTime/HMS behind a function barrier.
function convert_datetime_column(col::DataValueVector{T}, f::F, ::Type{S}) where {T<:Number,F,S}
    n = length(col)
    out = DataValueVector{S}(Vector{S}(undef, n), fill(true, n))
    @inbounds for i in 1:n
        v = col[i]
        DataValues.isna(v) || (out[i] = f(get(v)))
    end
    return out
end
