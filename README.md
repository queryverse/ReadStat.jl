[![Travis CI build status](https://travis-ci.org/WizardMac/ReadStat.jl.svg?branch=master)](https://travis-ci.org/WizardMac/ReadStat.jl)
[![Appveyor build status](https://ci.appveyor.com/api/projects/status/t297nextsc020qtd?svg=true)](https://ci.appveyor.com/project/evanmiller/dataread-jl/branch/master)

ReadStat.jl: Read files from Stata, SPSS, and SAS
--

The ReadStat.jl Julia module uses the
[ReadStat](https://github.com/WizardMac/ReadStat) C library to parse binary and
transport files from Stata, SPSS and SAS. All functions return a
[DataFrame](https://github.com/JuliaStats/DataFrames.jl).

Usage:

```julia
using ReadStat

read_dta("/path/to/something.dta")

read_por("/path/to/something.por")

read_sav("/path/to/something.sav")

read_sas7bdat("/path/to/something.sas7bdat")
```
