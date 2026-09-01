# Test fixtures

Sourced fixtures (verified against the upstream git blob SHAs when copied):

- `alltypes.dta`, `stringtypes.dta`, `sample.dta`, `sample.sav`, `sample.por`,
  `sample.sas7bdat`, `sample.xpt`, `string_labeled_value.sav`,
  `datetime13.xpt` are copied from
  [ReadStatTables.jl](https://github.com/junyuan-chen/ReadStatTables.jl)
  (`data/`, MIT license). `alltypes.dta` and `stringtypes.dta` are generated
  by the `alltypes.do`/`stringtypes.do` scripts kept in that repository;
  the `sample.*` files there originally come from pyreadstat (see below),
  with `sample.dta` slightly modified for wider test coverage.
- `sample_missing.sav`, `sample_missing.csv`, `sample_missing_user.csv`, and
  `sample.zsav` are copied from
  [pyreadstat](https://github.com/Roche/pyreadstat) (`test_data/basic/`,
  Apache-2.0 license). The two CSV files hold the expected values of
  `sample_missing.sav` with user-defined missing values collapsed to missing
  and kept as data, respectively.

The `types.{dta,sav,sas7bdat,xpt,por}` fixtures in the parent directory are
the original ReadStat.jl fixtures (`types.por` was copied from
StatFiles.jl, which ships the same table in SPSS portable form).
