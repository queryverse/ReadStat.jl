@testitem "missing values" begin
    using DataValues

    @testset "tagged missings (alltypes.dta)" begin
        tbl = read_dta(joinpath(@__DIR__, "data", "alltypes.dta"))
        @test size(tbl, 1) == 3

        # Rows: 1 = the value 1, 2 = .a (tagged missing), 3 = system missing.
        for col in (:vbyte, :vint, :vlong, :vfloat, :vdouble)
            c = tbl[col]
            @test !isna(c[1]) && get(c[1]) == 1
            @test isna(c[2])
            @test isna(c[3])
            @test missingtags(tbl, col) == ['\0', 'a', '\0']
        end
        @test missingtags(tbl, :vstr) === nothing

        # The label set covers a value and a tagged missing value.
        d = valuelabels(tbl, :vbyte)
        @test d !== nothing
        @test d[Int32(1)] == "A"
        @test d['a'] == "Tagged missing"

        # strL values surface as Strings.
        @test occursin("long string!", get(tbl[:vstrL][1]))
    end

    @testset "SPSS user-defined missings (sample_missing.sav)" begin
        path = joinpath(@__DIR__, "data", "sample_missing.sav")

        # Default: user-defined missing values collapse to NA
        # (expected values from pyreadstat's sample_missing.csv).
        tbl = read_sav(path)
        @test tbl[:mychar] == DataValueArray{String}(["a", "b", "c", "d", "e", "Z", ""])
        @test tbl[:mynum] == DataValueArray{Float64}([1.1, 1.2, -1000.3, -1.4, 1000.3, NA, NA])
        @test isna.(tbl[:mydate]) == [false, false, false, false, true, true, true]
        @test !isempty(varmetadata(tbl, :mynum).missing_ranges)

        # :keep returns the user-missing codes as data
        # (expected values from pyreadstat's sample_missing_user.csv).
        kept = read_sav(path; user_missing=:keep)
        @test kept[:mynum] ==
            DataValueArray{Float64}([1.1, 1.2, -1000.3, -1.4, 1000.3, -1.0, 2500.0])
        @test kept[:mylabl] == DataValueArray{Float64}([1, 2, 1, 2, 1, -1, NA])
        @test kept[:myord] == DataValueArray{Float64}([1, 2, 3, 1, 1, -1, -3])
        # System-missing cells stay NA either way.
        @test isna.(kept[:mydate]) == [false, false, false, false, true, true, true]

        @test_throws ArgumentError read_sav(path; user_missing=:bogus)
    end
end

@testitem "read_por" begin
    using DataValues

    tbl = read_por(joinpath(@__DIR__, "data", "sample.por"))
    @test size(tbl) == (5, 7)
    @test filemetadata(tbl).row_count == -1
    @test names(tbl) == [:MYCHAR, :MYNUM, :MYDATE, :DTIME, :MYLABL, :MYORD, :MYTIME]
    @test tbl[:MYCHAR] == DataValueArray{String}(["a", "b", "c", "d", "e"])
    @test tbl[:MYNUM] == DataValueArray{Float64}([1.1, 1.2, -1000.3, -1.4, 1000.3])
    @test isna(tbl[:MYDATE][5])
    @test varmetadata(tbl, :MYDATE).format == "EDATE10"
    d = valuelabels(tbl, :MYLABL)
    @test d !== nothing && d[1.0] == "Male" && d[2.0] == "Female"

    # The types.por fixture inherited from StatFiles.jl has an invalid
    # timestamp that readstat 1.1.9 rejects; the error must surface cleanly
    # (queryverse/ReadStat.jl#96, queryverse/StatFiles.jl#32).
    err = try
        read_por(joinpath(@__DIR__, "types.por"))
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("timestamp", err.msg)
end
