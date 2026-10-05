# Introduction

ReadStat.jl reads and writes the data file formats of Stata (`.dta`), SPSS
(`.sav`, `.zsav`, `.por`), and SAS (`.sas7bdat`, `.xpt`, and `.sas7bcat`
value-label catalogs), plus fixed-width text files described by schema
files, using the [ReadStat](https://github.com/WizardMac/ReadStat) C
library. Missing data is represented with
[DataValues.jl](https://github.com/queryverse/DataValues.jl).

## Reading

```julia
using ReadStat

tbl = read_dta("data.dta")     # read_sav, read_por, read_sas7bdat, read_xport
tbl = readstat("data.sav")     # dispatch on the file extension
```

The result is a [`ReadStatTable`](@ref): columns by name (`tbl[:price]`) or
index, [`filemetadata`](@ref) and [`varmetadata`](@ref) for everything the
file records, [`valuelabels`](@ref) and [`labeled`](@ref) for value labels,
and [`missingtags`](@ref) for tagged missing values. All readers accept the
same keyword arguments for column projection, row selection, parallel
parsing, encodings, missing-value semantics, and date/time conversion — see
[`read_dta`](@ref).

For metadata without data, use [`read_meta`](@ref). For planning and
streaming — schema first, then a projected read or a single-pass chunked
scan — use [`ReadStatSource`](@ref) with `read` and [`chunks`](@ref).

## Writing

[`write_dta`](@ref), `write_sav`, `write_por`, `write_sas7bdat`,
`write_xport`, and [`write_sas7bcat`](@ref) write columns or a whole
`ReadStatTable`, including value labels, missing-value declarations, notes,
compression, and date/time re-encoding. The public but unexported
[`ReadStat.Writer`](@ref) mirrors the C writer API one-to-one, and
`ReadStat.CAPI` holds the raw C bindings.

# API Reference

```@autodocs
Modules = [ReadStat]
```
