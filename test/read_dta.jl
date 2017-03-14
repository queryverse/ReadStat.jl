using NullableArrays, Base.Test

dtafile = joinpath(dirname(@__FILE__), "types.dta")

df = read_dta(dtafile)
@test typeof(df[:, :vfloat]) == NullableVector{Float32}
@test typeof(df[:, :vdouble]) == NullableVector{Float64}
@test typeof(df[:, :vlong]) == NullableVector{Int32}
@test typeof(df[:, :vint]) == NullableVector{Int16}
@test typeof(df[:, :vbyte]) == NullableVector{Int8}
@test typeof(df[:, :vstring]) == NullableVector{String}

@test get(df[2, :vfloat]) == 7
@test get(df[2, :vdouble]) == 7
@test get(df[2, :vlong]) == 7
@test get(df[2, :vint]) == 7
@test get(df[2, :vbyte]) == 7
@test get(df[2, :vstring]) == "7"

@test isnull(df[3, :vfloat])
@test isnull(df[3, :vdouble])
@test isnull(df[3, :vlong])
@test isnull(df[3, :vint])
@test isnull(df[3, :vbyte])
@test get(df[3, :vstring]) == ""


