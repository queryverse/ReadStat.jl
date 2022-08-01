using ReadStat
using DataValues
using Test

testdir = joinpath(@__DIR__, "write_tests")
if isdir(testdir)
    rm(testdir, recursive = true)
end
mkdir(testdir)

@testset "ReadStat: $ext files" for (reader, writer, ext) in
    ((read_dta, write_dta, "dta"),
     (read_sav, write_sav, "sav"),
     (read_sas7bdat, write_sas7bdat, "sas7bdat"),
     (read_xport, write_xport, "xpt"))

    @testset "Reading" begin
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
    end

    @testset "Writing" begin
        data = (
            vdouble = [3.14, 7.],
            # vfloat = [3.14f0, 7.f0, missing],
            # vlong = [2, 7, missing],
            # vint = [Int16(2), Int16(7), missing],
            # vbyte = [Int8(2), Int8(7), missing],
            # vstring = ["2", "7", ""],
        )
        filepath = joinpath(testdir, "testwrite.$ext")
        writer(filepath, data)
        rsdf = reader(filepath)
        data_read = rsdf.data
        @test length(data_read) == length(data)
        @test rsdf.headers == [:vdouble]
    end
end
