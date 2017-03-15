using DataArrays, NullableArrays, DataTables, DataFrames, Base.Test

dtafile = joinpath(dirname(@__FILE__), "types.dta")

# Test default return container type

df = read_dta(dtafile)
@test typeof(df[:, :vfloat]) == DataVector{Float32}
@test typeof(df[:, :vdouble]) == DataVector{Float64}
@test typeof(df[:, :vlong]) == DataVector{Int32}
@test typeof(df[:, :vint]) == DataVector{Int16}
@test typeof(df[:, :vbyte]) == DataVector{Int8}
@test typeof(df[:, :vstring]) == DataVector{String}

@test df[2, :vfloat] == 7
@test df[2, :vdouble] == 7
@test df[2, :vlong] == 7
@test df[2, :vint] == 7
@test df[2, :vbyte] == 7
@test df[2, :vstring] == "7"

@test isna(df[3, :vfloat])
@test isna(df[3, :vdouble])
@test isna(df[3, :vlong])
@test isna(df[3, :vint])
@test isna(df[3, :vbyte])
@test df[3, :vstring] == ""

# Test explicit DataFrame return container type

df = read_dta(DataFrame, dtafile)
@test typeof(df[:, :vfloat]) == DataVector{Float32}
@test typeof(df[:, :vdouble]) == DataVector{Float64}
@test typeof(df[:, :vlong]) == DataVector{Int32}
@test typeof(df[:, :vint]) == DataVector{Int16}
@test typeof(df[:, :vbyte]) == DataVector{Int8}
@test typeof(df[:, :vstring]) == DataVector{String}

@test df[2, :vfloat] == 7
@test df[2, :vdouble] == 7
@test df[2, :vlong] == 7
@test df[2, :vint] == 7
@test df[2, :vbyte] == 7
@test df[2, :vstring] == "7"

@test isna(df[3, :vfloat])
@test isna(df[3, :vdouble])
@test isna(df[3, :vlong])
@test isna(df[3, :vint])
@test isna(df[3, :vbyte])
@test df[3, :vstring] == ""

# Test explicit DataTable return container type

dt = read_dta(DataTable, dtafile)
@test typeof(dt[:, :vfloat]) == NullableVector{Float32}
@test typeof(dt[:, :vdouble]) == NullableVector{Float64}
@test typeof(dt[:, :vlong]) == NullableVector{Int32}
@test typeof(dt[:, :vint]) == NullableVector{Int16}
@test typeof(dt[:, :vbyte]) == NullableVector{Int8}
@test typeof(dt[:, :vstring]) == NullableVector{String}

@test get(dt[2, :vfloat]) == 7
@test get(dt[2, :vdouble]) == 7
@test get(dt[2, :vlong]) == 7
@test get(dt[2, :vint]) == 7
@test get(dt[2, :vbyte]) == 7
@test get(dt[2, :vstring]) == "7"

@test isnull(dt[3, :vfloat])
@test isnull(dt[3, :vdouble])
@test isnull(dt[3, :vlong])
@test isnull(dt[3, :vint])
@test isnull(dt[3, :vbyte])
@test get(dt[3, :vstring]) == ""
