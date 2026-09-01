@testitem "reader kwargs" begin
    using DataValues

    dta = joinpath(@__DIR__, "types.dta")
    xpt = joinpath(@__DIR__, "types.xpt")

    @testset "usecols" begin
        tbl = read_dta(dta; usecols=[:vint, :vstring])
        @test names(tbl) == [:vint, :vstring]
        @test size(tbl) == (3, 2)
        @test tbl[:vint] == DataValueArray{Int16}([2, 7, NA])
        @test varmetadata(tbl, :vstring).name === :vstring

        @test names(read_dta(dta; usecols=1)) == [:vfloat]
        @test names(read_dta(dta; usecols=:vbyte)) == [:vbyte]
        @test names(read_dta(dta; usecols=[2, 4])) == [:vdouble, :vint]
        @test names(read_dta(dta; usecols=r"^vd")) == [:vdouble]
        @test names(read_dta(dta; usecols=n -> startswith(string(n), "vs"))) == [:vstring]
        @test size(read_dta(dta; usecols=Symbol[])) == (0, 0)

        # Column selection composes with row selection on the C side.
        tbl = read_dta(dta; usecols=[:vlong], row_limit=2)
        @test size(tbl) == (2, 1)
        @test tbl[:vlong] == DataValueArray{Int32}([2, 7])
    end

    @testset "row_limit / row_offset" begin
        tbl = read_dta(dta; row_limit=2)
        @test size(tbl) == (2, 6)
        @test tbl[:vlong] == DataValueArray{Int32}([2, 7])

        tbl = read_dta(dta; row_offset=1)
        @test size(tbl) == (2, 6)
        @test tbl[:vlong] == DataValueArray{Int32}([7, NA])

        tbl = read_dta(dta; row_offset=1, row_limit=1)
        @test size(tbl) == (1, 6)
        @test tbl[:vlong] == DataValueArray{Int32}([7])

        @test size(read_dta(dta; row_limit=0)) == (0, 6)

        # Formats with unknown row counts grow their buffers row by row.
        tbl = read_xport(xpt; row_limit=2)
        @test size(tbl) == (2, 6)
        tbl = read_xport(xpt; row_offset=1)
        @test size(tbl) == (2, 6)
        @test tbl[:vlong] == DataValueArray{Int32}([7, NA])

        @test_throws ArgumentError read_dta(dta; row_offset=-1)
        @test_throws ArgumentError read_dta(dta; row_limit=-1)
    end

    @testset "read_meta" begin
        tbl = read_meta(dta)
        @test size(tbl) == (0, 6)
        @test names(tbl) == [:vfloat, :vdouble, :vlong, :vint, :vbyte, :vstring]
        @test filemetadata(tbl).row_count == 3
        @test varmetadata(tbl, :vint).name === :vint

        @test filemetadata(read_meta(joinpath(@__DIR__, "types.sav"))).row_count == 3
        @test filemetadata(read_meta(xpt)).row_count == -1
    end

    @testset "readstat dispatcher" begin
        for file in ("types.dta", "types.sav", "types.sas7bdat", "types.xpt")
            @test size(readstat(joinpath(@__DIR__, file)), 2) == 6
        end
        @test size(readstat(dta; format=:dta), 1) == 3
        @test_throws ArgumentError readstat("data.unknown")
    end

    @testset "progress" begin
        fractions = Float64[]
        tbl = read_dta(dta; progress=p -> (push!(fractions, p); true))
        @test size(tbl) == (3, 6)
        @test !isempty(fractions)
        @test all(0.0 .<= fractions .<= 1.0)

        # Returning false stops the parse; the rows read so far come back.
        tbl = read_dta(dta; progress=p -> false)
        @test size(tbl, 1) <= 3
    end

    @testset "encodings" begin
        tbl = read_dta(dta; handler_encoding="UTF-8")
        @test tbl[:vstring] == DataValueArray{String}(["2", "7", ""])
    end
end
