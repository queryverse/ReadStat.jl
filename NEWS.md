# ReadStat.jl v2.0.0 Release Notes

Breaking release. Highlights:

* The readers return a `ReadStatTable`: concretely typed `DataValueVector`
  columns by name or index, plus complete file-level (`filemetadata`) and
  per-variable (`varmetadata`) metadata — creation/modified time, format
  version, compression, endianness, encoding, notes, frequency weight,
  variable labels, display formats, measures, alignments, and all value
  labels. `ReadStatDataFrame` remains as a deprecated alias with `getproperty`
  shims for the 1.x fields.
* Reader keyword arguments: `usecols` (column projection inside the C
  parse), `row_limit`/`row_offset`, `ntasks` (parallel chunked parsing into
  shared buffers), `file_encoding`/`handler_encoding`, `user_missing`,
  `convert_datetime`, `apply_value_labels`, `catalog`, and `progress`
  (cancellable). New entry points: `readstat` (extension dispatch),
  `read_meta` (metadata only), `read_sas7bcat` (SAS value-label catalogs),
  and `read_txt` (fixed-width text via SAS/SPSS/Stata schema files). Every
  reader also accepts an `IO`.
* Columns with date/time display formats decode to `Date`/`DateTime`/`HMS`
  by default (Stata, SAS, and SPSS format tables and epochs); `HMS` carries
  times of day and durations beyond 24 hours.
* Value labels: `valuelabels`, and the lazy `LabeledArray`/`LabeledValue`
  view (via `labeled` or `apply_value_labels=true`) that displays labels but
  computes on the raw codes. Tagged missing values keep their tags
  (`missingtags`), including labeled tags; SPSS user-defined missing values
  can be kept as data (`user_missing=:keep`) and their rules are always in
  `varmetadata(tbl, col).missing_ranges`.
* `ReadStatSource`: a lazy handle with `schema`/`colnames`/`coltypes`/
  `nrows`/`supports`, pushdown-capable `read(src; usecols, rows)`, and
  single-pass streaming `chunks`.
* Write support for all formats: `write_dta`, `write_sav`, `write_por`,
  `write_sas7bdat`, `write_xport`, and `write_sas7bcat`, from columns or a
  `ReadStatTable`, covering value labels, tagged and user-defined missing
  values, notes, compression (`.zsav`), and date/time re-encoding; plus the
  public low-level `ReadStat.Writer` (one-to-one with the C writer API,
  including Stata strL) and the complete raw C bindings in `ReadStat.CAPI`.
* Fixes: the `readstat_value_t` ABI on Windows is now verified behaviorally
  against the C library; cells the parser never delivers are NA over defined
  storage instead of undefined memory; parsers are freed even when a handler
  throws.
* Requires Julia 1.12.

# ReadStat.jl v1.1.0 Release Notes
* Add support for SAS XPORT

# ReadStat.jl v1.0.2 Release Notes
* Fix a type instability

# ReadStat.jl v1.0.1 Release Notes
* Bugfix release

# ReadStat.jl v1.0.0 Release Notes
* Drop support for all Julia pre 1.3 versions
* Migrate to Project.toml
* Migrate to artifacts

# ReadStat.jl v0.4.1 Release Notes
* Fix remaining julia 0.7/1.0 issues

# ReadStat.jl v0.4.0 Release Notes
* Drop julia 0.6 support, add julia 0.7 support
* Use BinaryProvider.jl

# ReadStat.jl v0.3.0 Release Notes
* Change return type of API
* Return more info

# ReadStat.jl v0.2.0 Release Notes
* Remove dependency on DataFrames and DataTables

# ReadStat.jl v0.1.1 Release Notes
* Bug fix release

# ReadStat.jl v0.1.0 Release Notes
* First release