@testitem "deprecated 1.x API" begin
    using DataValues
    using Dates

    df = read_dta(joinpath(@__DIR__, "types.dta"))
    @test df isa ReadStatDataFrame
    @test ReadStatDataFrame === ReadStatTable

    data = df.data
    @test data isa Vector{Any}
    @test length(data) == 6
    @test data[1] == DataValueArray{Float32}([3.14, 7.0, NA])
    @test data[5] == DataValueArray{Int8}([2, 7, NA])

    @test df.headers == [:vfloat, :vdouble, :vlong, :vint, :vbyte, :vstring]
    @test df.types == [Float32, Float64, Int32, Int16, Int8, String]
    @test df.types_as_int == Int32[4, 5, 3, 2, 1, 0]
    @test df.labels == fill("", 6)
    @test df.formats isa Vector{String}
    @test df.storagewidths isa Vector{Csize_t}
    @test df.measures == zeros(Int32, 6)
    @test df.alignments == Int32[3, 3, 3, 3, 3, 3]
    @test df.val_label_keys == fill("", 6)
    @test df.val_label_dict isa Dict{String,Dict{Any,String}}
    @test isempty(df.val_label_dict)
    @test df.rows == 3
    @test df.columns == 6
    @test df.filelabel == ""
    @test df.timestamp isa DateTime
    @test df.format isa Clong
    @test df.hasmissings == fill(false, 6)
end
