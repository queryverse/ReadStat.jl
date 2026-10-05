@testitem "writer round trips" begin
    using DataValues
    using Dates
    using ReadStat: Writer, add_variable!, add_string_ref!, begin_writing!,
        begin_row!, insert_string_ref!, end_row!
    using ReadStat: CAPI

    tmp = mktempdir()
    cols = Any[
        DataValueArray{Int8}([1, 2, NA]),
        DataValueArray{Int16}([10, 20, NA]),
        DataValueArray{Int32}([100, 200, NA]),
        DataValueArray{Float32}([1.5f0, 2.5f0, NA]),
        DataValueArray{Float64}([1.25, 2.75, NA]),
        DataValueArray{String}(["ab", "cdef", NA]),
        DataValueArray{Date}([Date(2020, 1, 2), Date(1959, 12, 31), NA]),
        DataValueArray{DateTime}([DateTime(2020, 1, 2, 3, 4, 5), DateTime(1960, 1, 1), NA]),
    ]
    cnames = [:vbyte, :vint, :vlong, :vfloat, :vdouble, :vstr, :vdate, :vdt]
    writers = (dta=write_dta, sav=write_sav, por=write_por,
               sas7bdat=write_sas7bdat, xport=write_xport)

    @testset "all types via $fmt" for fmt in (:dta, :sav, :por, :sas7bdat, :xport)
        path = joinpath(tmp, "types_out.$(fmt === :xport ? "xpt" : fmt)")
        writers[fmt](path, cols, cnames; file_label="roundtrip")
        tbl = readstat(path; format=fmt)

        @test size(tbl) == (3, 8)
        expected_names = fmt === :por ?
            [Symbol(uppercase(String(n))) for n in cnames] : cnames
        @test names(tbl) == expected_names
        for i in 1:5
            @test tbl[i] == cols[i]  # numeric equality across widened storage
        end
        @test get(tbl[6][1]) == "ab" && get(tbl[6][2]) == "cdef"
        # A missing string cell comes back as the format's missing string,
        # which is the empty string.
        @test isna(tbl[6][3]) || get(tbl[6][3]) == ""
        @test tbl[7] == cols[7]
        @test tbl[8] == cols[8]
        @test filemetadata(tbl).file_label == "roundtrip"

        # Writing into an IO works the same.
        io = IOBuffer()
        writers[fmt](io, cols, cnames)
        @test size(readstat(IOBuffer(take!(io)); format=fmt)) == (3, 8)
    end

    @testset "labels, tags, notes, attributes (dta)" begin
        path = joinpath(tmp, "labels_out.dta")
        write_dta(path, Any[DataValueArray{Int32}([1, 2, NA])], [:grade];
            value_labels=Dict(:gl => ReadStat.ValueLabelDict(
                Int32(1) => "low", Int32(2) => "high", 'a' => "refused")),
            vallabels=[:gl],
            tags=[['\0', '\0', 'a']],
            labels=["the grade"],
            notes=["a note", "another note"],
            file_label="labeled",
            timestamp=DateTime(2020, 6, 1, 12, 0, 0))
        tbl = read_dta(path)
        @test missingtags(tbl, :grade) == ['\0', '\0', 'a']
        d = valuelabels(tbl, :grade)
        @test d[Int32(1)] == "low" && d[Int32(2)] == "high" && d['a'] == "refused"
        @test varmetadata(tbl, :grade).label == "the grade"
        @test filemetadata(tbl).notes == ["a note", "another note"]
        @test year(filemetadata(tbl).modified_time) == 2020
    end

    @testset "LabeledArray columns carry their labels" begin
        path = joinpath(tmp, "la_out.dta")
        la = LabeledArray(DataValueArray{Int32}([1, 2, 1]),
                          ReadStat.ValueLabelDict(Int32(1) => "one", Int32(2) => "two"))
        write_dta(path, Any[la], [:k])
        tbl = read_dta(path)
        d = valuelabels(tbl, :k)
        @test d !== nothing && d[Int32(1)] == "one" && d[Int32(2)] == "two"
        @test tbl[:k] == DataValueArray{Int32}([1, 2, 1])
    end

    @testset "SPSS user-defined missing values (sav)" begin
        path = joinpath(tmp, "um_out.sav")
        write_sav(path, Any[DataValueArray{Float64}([1.0, -1.0, 99.0])], [:x];
            missing_ranges=[[-1.0, (90.0, 100.0)]])
        tbl = read_sav(path)
        @test isna.(tbl[:x]) == [false, true, true]
        kept = read_sav(path; user_missing=:keep)
        @test kept[:x] == DataValueArray{Float64}([1.0, -1.0, 99.0])
        ranges = varmetadata(tbl, :x).missing_ranges
        @test (90.0, 100.0) in ranges && (-1.0, -1.0) in ranges
    end

    @testset "sas7bcat" begin
        path = joinpath(tmp, "cat_out.sas7bcat")
        write_sas7bcat(path, Dict(:NUMFMT => ReadStat.ValueLabelDict(1.0 => "yes", 2.0 => "no")))
        cat = read_sas7bcat(path)
        @test cat[:NUMFMT][1.0] == "yes" && cat[:NUMFMT][2.0] == "no"
    end

    @testset "strL through the low-level writer" begin
        path = joinpath(tmp, "strl_out.dta")
        w = Writer(path)
        ref = add_string_ref!(w, "a very long shared string")
        v = add_variable!(w, :s, CAPI.READSTAT_TYPE_STRING_REF)
        begin_writing!(w, :dta, 2)
        for _ in 1:2
            begin_row!(w)
            insert_string_ref!(w, v, ref)
            end_row!(w)
        end
        close(w)
        tbl = read_dta(path)
        @test [get(x) for x in tbl[:s]] == fill("a very long shared string", 2)
    end

    @testset "table round trips" begin
        src = read_dta(joinpath(@__DIR__, "data", "alltypes.dta"))
        path = joinpath(tmp, "tbl_out.dta")
        write_dta(path, src)
        tbl = read_dta(path)
        @test names(tbl) == names(src)
        @test missingtags(tbl, :vbyte) == missingtags(src, :vbyte)
        @test valuelabels(tbl, :vbyte) == valuelabels(src, :vbyte)
        @test tbl[:vdate] == src[:vdate]
        @test tbl[:vstrL] == src[:vstrL]

        sav = read_sav(joinpath(@__DIR__, "data", "sample.sav"))
        path2 = joinpath(tmp, "tbl_out.sav")
        write_sav(path2, sav)
        tbl2 = read_sav(path2)
        for i in 1:size(sav, 2)
            @test isequal(collect(tbl2[i]), collect(sav[i]))
        end
        @test valuelabels(tbl2, :mylabl) == valuelabels(sav, :mylabl)
    end

    @testset "compression" begin
        path = joinpath(tmp, "z_out.zsav")
        write_sav(path, Any[DataValueArray{Float64}([1.0, 2.0])], [:x]; compress=:binary)
        @test size(read_sav(path), 1) == 2
        path2 = joinpath(tmp, "c_out.sas7bdat")
        write_sas7bdat(path2, Any[DataValueArray{Float64}([1.0, 2.0])], [:x]; compress=:rows)
        @test size(read_sas7bdat(path2), 1) == 2
    end

    @testset "validation errors" begin
        one = Any[DataValueArray{Float64}([1.0])]
        @test_throws ErrorException write_sav(joinpath(tmp, "badnote.sav"), one, [:x];
            notes=[repeat("x", 200)])  # SPSS notes are capped at 80 characters
        @test_throws ArgumentError write_dta(joinpath(tmp, "mismatch.dta"), one, [:x, :y])
        @test_throws ArgumentError write_dta(joinpath(tmp, "raggedy.dta"),
            Any[DataValueArray{Float64}([1.0]), DataValueArray{Float64}([1.0, 2.0])], [:x, :y])
        @test_throws ArgumentError write_dta(joinpath(tmp, "nofw.dta"), one, [:x]; fweight=:nope)
    end
end

@testitem "large write/read round trip with ntasks and chunks" begin
    using DataValues

    n = 50_000
    isna_mask = [i % 997 == 0 for i in 1:n]
    cols = Any[
        DataValueVector{Int32}(collect(Int32, 1:n), copy(isna_mask)),
        DataValueVector{Float64}(collect(1:n) ./ 3, fill(false, n)),
        DataValueVector{String}(string.(mod.(1:n, 100)), copy(isna_mask)),
    ]
    path = joinpath(mktempdir(), "big.dta")
    write_dta(path, cols, [:id, :val, :bucket])

    serial = read_dta(path; ntasks=1)
    @test size(serial) == (n, 3)
    @test isna.(serial[:id]) == isna_mask
    @test get(serial[:val][n]) ≈ n / 3

    threaded = read_dta(path; ntasks=4)
    for i in 1:3
        @test isequal(collect(threaded[i]), collect(serial[i]))
    end

    reassembled = reduce(vcat,
        [collect(p[:id]) for p in chunks(ReadStatSource(path); chunksize=7_000)])
    @test isequal(reassembled, collect(serial[:id]))
end
