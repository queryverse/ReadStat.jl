@testitem "read basics" begin
    using DataValues
    using Dates
    using ReadStat: CAPI

    # Expected alignments/measures are the raw enum values as stored in the
    # fixtures; every fixture reports measure UNKNOWN (0).
    @testset "types.$ext" for (reader, ext, alignments, has_row_count) in
        ((read_dta, "dta", [3, 3, 3, 3, 3, 3], true),
         (read_sav, "sav", [0, 0, 0, 0, 0, 0], true),
         (read_sas7bdat, "sas7bdat", [0, 0, 0, 0, 0, 0], true),
         (read_xport, "xpt", [3, 3, 3, 3, 3, 1], false))

        tbl = reader(joinpath(@__DIR__, "types.$ext"))

        @test size(tbl) == (3, 6)
        @test size(tbl, 1) == 3
        @test size(tbl, 2) == 6
        @test names(tbl) == [:vfloat, :vdouble, :vlong, :vint, :vbyte, :vstring]

        @test tbl[:vfloat] == DataValueArray{Float32}([3.14, 7.0, NA])
        @test tbl[:vdouble] == DataValueArray{Float64}([3.14, 7.0, NA])
        @test tbl[:vlong] == DataValueArray{Int32}([2, 7, NA])
        @test tbl[:vint] == DataValueArray{Int16}([2, 7, NA])
        @test tbl[:vbyte] == DataValueArray{Int8}([2, 7, NA])
        # None of these formats has a distinct missing state for strings —
        # Stata's missing string literally is the empty string — so the C
        # library delivers "" as a regular value and the cell is not NA.
        @test tbl[:vstring] == DataValueArray{String}(["2", "7", ""])
        @test tbl[1] === tbl[:vfloat]
        @test_throws ArgumentError tbl[:nonexistent]

        meta = filemetadata(tbl)
        @test meta.var_count == 6
        @test meta.row_count == (has_row_count ? 3 : -1)
        @test meta.modified_time isa DateTime
        @test meta.modified_time > DateTime(2000)
        @test isempty(meta.notes)
        @test isempty(meta.value_labels)

        @test [Int(varmetadata(tbl, i).alignment) for i in 1:6] == alignments
        @test all(varmetadata(tbl, i).measure == CAPI.READSTAT_MEASURE_UNKNOWN for i in 1:6)
        @test varmetadata(tbl, :vstring).type == CAPI.READSTAT_TYPE_STRING
        # Only Stata has a distinct float storage type; SPSS and SAS report
        # doubles (the equality checks above compare numerically).
        @test varmetadata(tbl, :vfloat).type ==
            (ext == "dta" ? CAPI.READSTAT_TYPE_FLOAT : CAPI.READSTAT_TYPE_DOUBLE)
        @test varmetadata(tbl, :vbyte).name === :vbyte
        @test all(isempty(varmetadata(tbl, i).missing_ranges) for i in 1:6)
        @test valuelabels(tbl, :vfloat) === nothing

        rendered = sprint(show, MIME"text/plain"(), tbl; context=:limit => true)
        @test occursin("3x6 ReadStatTable", rendered)
        @test occursin("vstring", rendered)
        @test occursin("NA", rendered)
    end

    @test_throws ArgumentError read_dta(joinpath(@__DIR__, "no_such_file.dta"))
end
