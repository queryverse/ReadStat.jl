using ReadStat
using DataValues
using Test

@testset "ReadStat" begin

@testset "DTA files" begin

dtafile = joinpath(dirname(@__FILE__), "types.dta")
rsdf = read_dta(dtafile)
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

@testset "SAV files" begin

dtafile = joinpath(dirname(@__FILE__), "types.sav")
rsdf = read_sav(dtafile)
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

@testset "SAS7BDAT files" begin

dtafile = joinpath(dirname(@__FILE__), "types.sas7bdat")
rsdf = read_sas7bdat(dtafile)
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

end
