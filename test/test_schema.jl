@testitem "fixed-width text via schema files" begin
    using DataValues

    dir = joinpath(@__DIR__, "data")
    data = joinpath(dir, "fixed.txt")
    dct = joinpath(dir, "schema.dct")

    tbl = read_txt(data, dct; schema_format=:stata_dictionary)
    @test size(tbl) == (3, 3)
    @test names(tbl) == [:id, :name, :wage]
    @test tbl[:id] == DataValueArray{Int16}([1, 42, 100])
    @test [get(x) for x in tbl[:name]] == ["Alice", "Bob", "Carol"]
    @test tbl[:wage] == DataValueArray{Float64}([3.5, 12.25, 0.75])
    @test varmetadata(tbl, :id).label == "ID number"

    # The reader kwargs push down as usual.
    part = read_txt(data, dct; schema_format=:stata_dictionary,
                    usecols=[:name], row_limit=2, row_offset=1)
    @test size(part) == (2, 1)
    @test [get(x) for x in part[:name]] == ["Bob", "Carol"]

    @test_throws ArgumentError read_txt(data, dct; schema_format=:nonsense)
    @test_throws ArgumentError read_txt("no_such.txt", dct;
                                        schema_format=:stata_dictionary)
    # A data file is not a valid schema file.
    @test_throws Exception read_txt(data, data; schema_format=:stata_dictionary)
end
