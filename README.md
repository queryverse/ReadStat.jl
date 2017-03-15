[![Travis CI build status](https://travis-ci.org/WizardMac/ReadStat.jl.svg?branch=master)](https://travis-ci.org/WizardMac/ReadStat.jl)
[![Appveyor build status](https://ci.appveyor.com/api/projects/status/t297nextsc020qtd?svg=true)](https://ci.appveyor.com/project/evanmiller/dataread-jl/branch/master)
[![Coverage Status](https://coveralls.io/repos/github/WizardMac/ReadStat.jl/badge.svg?branch=master)](https://coveralls.io/github/WizardMac/ReadStat.jl?branch=master)

ReadStat.jl: Read files from Stata, SPSS, and SAS
--

The ReadStat.jl Julia module uses the
[ReadStat](https://github.com/WizardMac/ReadStat) C library to parse binary and
transport files from Stata, SPSS and SAS. All functions return either a
[DataFrame](https://github.com/JuliaStats/DataFrames.jl) (default) or a
[DataTable](https://github.com/JuliaData/DataTables.jl).

Usage:

```julia
using ReadStat, DataTables, DataFrames

read_dta("/path/to/something.dta")

read_por("/path/to/something.por")

read_sav("/path/to/something.sav")

read_sas7bdat("/path/to/something.sas7bdat")

read_dta(DataTable, "/path/to/something.dta")

read_por(DataTable, "/path/to/something.por")

read_sav(DataTable, "/path/to/something.sav")

read_sas7bdat(DataTable, "/path/to/something.sas7bdat")

read_dta(DataFrame, "/path/to/something.dta")

read_por(DataFrame, "/path/to/something.por")

read_sav(DataFrame, "/path/to/something.sav")

read_sas7bdat(DataFrame, "/path/to/something.sas7bdat")


```
