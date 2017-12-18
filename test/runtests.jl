using ReadStat
using DataValues
using Base.Test

@testset "ReadStat" begin

@testset "DTA files" begin

dtafile = joinpath(dirname(@__FILE__), "types.dta")
data, headers = read_dta(dtafile)

@test length(data) == 6
@test headers == [:vfloat, :vdouble, :vlong, :vint, :vbyte, :vstring]
@test data[1] == DataValueArray{Float32}([3.14, 7., NA])
@test data[2] == DataValueArray{Float64}([3.14, 7., NA])
@test data[3] == DataValueArray{Int32}([2, 7, NA])
@test data[4] == DataValueArray{Int16}([2, 7, NA])
@test data[5] == DataValueArray{Int8}([2, 7., NA])
@test data[6] == DataValueArray{String}(["2", "7", ""])
end

@testset "SAV files" begin

dtafile = joinpath(dirname(@__FILE__), "types.sav")
data, headers = read_sav(dtafile)

@test length(data) == 6
@test headers == [:vfloat, :vdouble, :vlong, :vint, :vbyte, :vstring]
@test data[1] == DataValueArray{Float32}([3.14, 7., NA])
@test data[2] == DataValueArray{Float64}([3.14, 7., NA])
@test data[3] == DataValueArray{Int32}([2, 7, NA])
@test data[4] == DataValueArray{Int16}([2, 7, NA])
@test data[5] == DataValueArray{Int8}([2, 7., NA])
@test data[6] == DataValueArray{String}(["2", "7", ""])
end

@testset "SAS7BDAT files" begin

dtafile = joinpath(dirname(@__FILE__), "types.sas7bdat")
data, headers = read_sas7bdat(dtafile)

@test length(data) == 6
@test headers == [:vfloat, :vdouble, :vlong, :vint, :vbyte, :vstring]
@test data[1] == DataValueArray{Float32}([3.14, 7., NA])
@test data[2] == DataValueArray{Float64}([3.14, 7., NA])
@test data[3] == DataValueArray{Int32}([2, 7, NA])
@test data[4] == DataValueArray{Int16}([2, 7, NA])
@test data[5] == DataValueArray{Int8}([2, 7., NA])
@test data[6] == DataValueArray{String}(["2", "7", ""])
end

end
