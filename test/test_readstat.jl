@testitem "ReadStat" begin
    using DataValues

    # Expected alignments are readstat_alignment_t values:
    # 0 = UNKNOWN, 1 = LEFT, 2 = CENTER, 3 = RIGHT.
    @testset "ReadStat: $ext files" for (reader, ext, alignments) in
        ((read_dta, "dta", Int32[3, 3, 3, 3, 3, 3]),
         (read_sav, "sav", Int32[0, 0, 0, 0, 0, 0]),
         (read_sas7bdat, "sas7bdat", Int32[0, 0, 0, 0, 0, 0]),
         (read_xport, "xpt", Int32[3, 3, 3, 3, 3, 1]))

        dtafile = joinpath(@__DIR__, "types.$ext")
        rsdf = reader(dtafile)
        data = rsdf.data

        @test length(data) == 6
        @test rsdf.headers == [:vfloat, :vdouble, :vlong, :vint, :vbyte, :vstring]
        @test data[1] == DataValueArray{Float32}([3.14, 7., NA])
        @test data[2] == DataValueArray{Float64}([3.14, 7., NA])
        @test data[3] == DataValueArray{Int32}([2, 7, NA])
        @test data[4] == DataValueArray{Int16}([2, 7, NA])
        @test data[5] == DataValueArray{Int8}([2, 7., NA])
        @test data[6] == DataValueArray{String}(["2", "7", ""])

        # Alignments must come from readstat_variable_get_alignment, not from
        # the measure accessor sitting next to it in the C API. Every fixture
        # reports measure UNKNOWN, so reading the wrong one yields all zeros.
        @test rsdf.alignments == alignments
        @test rsdf.measures == Int32[0, 0, 0, 0, 0, 0]

        # Every readstat_type_t the readers emit must map to a concrete Julia
        # type; a gap in that mapping used to surface as Nothing.
        @test all(!=(Nothing), rsdf.types)
    end
end
