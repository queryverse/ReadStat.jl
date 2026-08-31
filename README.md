# ReadStat

[![Project Status: Active - The project has reached a stable, usable state and is being actively developed.](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/#active)
[![Build Status](https://github.com/queryverse/ReadStat.jl/actions/workflows/juliaci.yml/badge.svg?branch=main)](https://github.com/queryverse/ReadStat.jl/actions/workflows/juliaci.yml)
[![codecov](https://codecov.io/gh/queryverse/ReadStat.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/queryverse/ReadStat.jl)

## Overview

ReadStat.jl: Read files from Stata, SPSS, and SAS
--

The ReadStat.jl Julia package uses the [ReadStat](https://github.com/WizardMac/ReadStat) C library to parse binary and transport files from Stata, SPSS and SAS. All functions return a `ReadStatDataFrame` whose fields hold the various informations contained in the passed file (column names, column data, labels, formats...).

For integration with packages like [DataFrames.jl](https://github.com/JuliaData/DataFrames.jl) you should use the [StatFiles.jl](https://github.com/queryverse/StatFiles.jl) package.

## Usage:

```julia
using ReadStat

read_dta("/path/to/something.dta")

read_por("/path/to/something.por")

read_sav("/path/to/something.sav")

read_sas7bdat("/path/to/something.sas7bdat")

read_xport("path/to/something.xpt")
```

## Installation
To install the package, run the following:

```julia
Pkg.add("ReadStat")
```
