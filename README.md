DataRead.jl: Read files from Stata, SPSS, and SAS
--

The DataRead Julia module uses
[ReadStat](https://github.com/WizardMac/ReadStat) to parse binary and transport
files from Stata, SPSS and SAS. All functions return a
[DataFrame](https://github.com/JuliaStats/DataFrames.jl).

Usage:

```julia
using DataRead

read_dta("/path/to/something.dta")

read_por("/path/to/something.por")

read_sav("/path/to/something.sav")

read_sas7bdat("/path/to/something.sas7bdat")
```