DataRead.jl: Read files from Stata, SPSS, and SAS
--

The DataRead Julia module uses libreadstat to parse binary and transport files
from Stata, SPSS and SAS. All functions return a DataFrame.

To use the module, you first need to ensure that libreadstat.dylib is in
Julia's load path.

Usage:

    using DataRead

    read_dta("/path/to/something.dta")

    read_por("/path/to/something.por")

    read_sav("/path/to/something.sav")

    read_sas7bdat("/path/to/something.sas7bdat")
