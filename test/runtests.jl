using ReadStat
using DataValues
using Test

@testset "ReadStat: $ext files" for (reader, ext) in
                                    ((read_dta, "dta"),
    (read_sav, "sav"),
    (read_sas7bdat, "sas7bdat"),
    (read_xport, "xpt"))

    dtafile = joinpath(dirname(@__FILE__), "types.$ext")
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
