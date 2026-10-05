# ReadStat

[![Project Status: Active - The project has reached a stable, usable state and is being actively developed.](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/#active)
[![Build Status](https://github.com/queryverse/ReadStat.jl/actions/workflows/juliaci.yml/badge.svg?branch=main)](https://github.com/queryverse/ReadStat.jl/actions/workflows/juliaci.yml)
[![codecov](https://codecov.io/gh/queryverse/ReadStat.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/queryverse/ReadStat.jl)

## Overview

ReadStat.jl reads and writes the data file formats of Stata (`.dta`), SPSS
(`.sav`, `.zsav`, `.por`), and SAS (`.sas7bdat`, `.xpt`, `.sas7bcat` value
catalogs), plus fixed-width text files described by schema files, using the
[ReadStat](https://github.com/WizardMac/ReadStat) C library. Missing data is
represented with [DataValues.jl](https://github.com/queryverse/DataValues.jl).

For integration with packages like
[DataFrames.jl](https://github.com/JuliaData/DataFrames.jl) you should use
the [StatFiles.jl](https://github.com/queryverse/StatFiles.jl) package.

## Reading

```julia
using ReadStat

tbl = read_dta("data.dta")        # also read_sav, read_por, read_sas7bdat, read_xport
tbl = readstat("data.sav")        # infer the format from the extension
tbl = read_dta(io)                # any IO holding the file works too

tbl[:price]                       # columns by name or index (DataValueVectors)
names(tbl), size(tbl)
filemetadata(tbl)                 # file label, timestamps, notes, encoding, ...
varmetadata(tbl, :price)          # variable label, display format, type, ...
```

Reads can push work into the C parser:

```julia
read_dta("data.dta"; usecols = [:price, :mpg])   # column projection
read_dta("data.dta"; row_offset = 1000, row_limit = 500)
read_dta("data.dta"; ntasks = 8)                 # parallel chunked parsing
read_meta("data.dta")                            # metadata only, zero rows
```

Columns with date/time display formats decode to `Date`, `DateTime`, or
`HMS` (a time-of-day/duration type with unbounded hours) automatically;
pass `convert_datetime=false` for the raw numbers.

Value labels are always parsed (`valuelabels(tbl, :rep77)`), and the
`labeled` view or `apply_value_labels=true` wraps labeled columns in a
`LabeledArray` whose elements display as their labels but compute as their
raw codes. SAS value labels live in catalog files:
`read_sas7bdat("f.sas7bdat"; catalog="formats.sas7bcat")`.

Tagged missing values (Stata/SAS `.a`-`.z`) read as NA with their tags
available via `missingtags(tbl, col)`; SPSS user-defined missing values
collapse to NA by default or stay data with `user_missing=:keep`.

## Lazy sources and streaming

`ReadStatSource` is a cheap handle for consumers that plan before they read:

```julia
src = ReadStatSource("big.dta")
schema(src); colnames(src); coltypes(src); nrows(src)
read(src; usecols = [:price], rows = 1_000:2_000)
for chunk in chunks(src; chunksize = 100_000)    # single-pass streaming
    # chunk is a complete ReadStatTable
end
```

## Writing

```julia
using DataValues

write_dta("out.dta",
    Any[DataValueArray([1, 2, 3]), DataValueArray(["a", "b", "c"])],
    [:id, :tag];
    labels = ["identifier", "a string"], file_label = "my data")

write_sav("out.sav", tbl)          # write a ReadStatTable, metadata included
```

`write_dta`, `write_sav`, `write_por`, `write_sas7bdat`, `write_xport`, and
`write_sas7bcat` cover value labels, tagged and user-defined missing values,
notes, compression (including `.zsav`), and date/time re-encoding. The
unexported low-level `ReadStat.Writer` follows the C writer API one-to-one
(including Stata strL columns), and `ReadStat.CAPI` exposes the raw C
bindings for anything else.

## Migrating from 1.x

The readers now return a `ReadStatTable`. The old `ReadStatDataFrame` name
and its field access (`df.data`, `df.headers`, ...) keep working with
deprecation warnings; switch to indexing and the metadata accessors. Date
and time columns are now decoded by default (`convert_datetime=false`
restores raw numbers), and cells the parser never delivers are NA instead
of undefined memory.

## Installation

```julia
Pkg.add("ReadStat")
```
