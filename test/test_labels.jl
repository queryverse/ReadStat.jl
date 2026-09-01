@testitem "value labels" begin
    using DataValues

    dir = joinpath(@__DIR__, "data")

    @testset "LabeledValue / LabeledArray semantics" begin
        tbl = read_sav(joinpath(dir, "sample.sav"))
        d = valuelabels(tbl, :mylabl)
        @test d == Dict(1.0 => "Male", 2.0 => "Female")

        la = labeled(tbl, :mylabl)
        @test la isa LabeledArray
        @test length(la) == 5
        @test rawvalues(la) === tbl[:mylabl]
        @test getvaluelabels(la) === d

        x = la[1]
        @test x isa DataValue{LabeledValue{Float64}}
        lv = get(x)
        @test unwrap(lv) == 1.0
        @test valuelabel(lv) == "Male"

        # Computes as the code, compares against strings as the label.
        @test lv == 1.0
        @test 1.0 == lv
        @test lv == "Male"
        @test lv != "Female"
        @test hash(lv) == hash(1.0)
        lv2 = get(la[2])
        @test lv != lv2
        @test isless(lv, lv2)
        @test sort([lv2, lv]) == [lv, lv2]

        # Displays as the label.
        @test sprint(print, lv) == "Male"
        @test sprint(show, MIME"text/plain"(), lv) == "Male (1.0)"

        # Partial label sets: unlabeled codes fall back to string(code).
        @test valuelabel(LabeledValue(9.0, d)) == "9.0"

        @test_throws ArgumentError labeled(tbl, :mychar)
    end

    @testset "apply_value_labels" begin
        tbl = read_sav(joinpath(dir, "sample.sav"); apply_value_labels=true)
        @test tbl[:mylabl] isa LabeledArray
        @test tbl[:myord] isa LabeledArray
        @test !(tbl[:mynum] isa LabeledArray)
        @test labeled(tbl, :mylabl) === tbl[:mylabl]
        @test [sprint(print, get(x)) for x in tbl[:mylabl]] ==
            ["Male", "Female", "Male", "Female", "Male"]
        @test rawvalues(tbl[:mylabl]) == DataValueArray{Float64}([1, 2, 1, 2, 1])
        @test occursin("Male", sprint(show, MIME"text/plain"(), tbl))
    end

    @testset "string-keyed labels" begin
        tbl = read_sav(joinpath(dir, "string_labeled_value.sav"); apply_value_labels=true)
        la = tbl[:v611]
        @test la isa LabeledArray
        @test unwrap(get(la[1])) == "BE33"
        @test valuelabel(get(la[1])) == "Prov. Liege"
    end

    @testset "sas7bcat catalogs" begin
        catpath = joinpath(dir, "test_formats_linux.sas7bcat")
        cat = read_sas7bcat(catpath)
        @test cat[Symbol("\$A")]["1"] == "Male"
        @test cat[Symbol("\$A")]["2"] == "Female"

        tbl = read_sas7bdat(joinpath(dir, "test_data_linux.sas7bdat");
                            catalog=catpath, apply_value_labels=true)
        @test varmetadata(tbl, :SEXA).vallabel == Symbol("\$A")
        @test tbl[:SEXA] isa LabeledArray
        # Expected labels from pyreadstat's sas_formatted.csv.
        @test [valuelabel(get(x)) for x in tbl[:SEXA]] == ["Male", "Female", "Male"]
        @test [valuelabel(get(x)) for x in tbl[:SEXB]] == ["Male", "Female", "Male"]

        # Without the catalog the label sets are simply absent.
        plain = read_sas7bdat(joinpath(dir, "test_data_linux.sas7bdat"))
        @test valuelabels(plain, :SEXA) === nothing

        @test_throws ArgumentError read_dta(joinpath(@__DIR__, "types.dta");
                                            catalog=catpath)
    end

    @testset "labeled view over tagged missings (alltypes.dta)" begin
        tbl = read_dta(joinpath(dir, "alltypes.dta"))
        la = labeled(tbl, :vbyte)
        @test valuelabel(get(la[1])) == "A"
        @test isna(la[2])
    end
end
