@testitem "multi-task reads" begin
    using DataValues

    dir = joinpath(@__DIR__, "data")

    function tables_equal(a, b)
        names(a) == names(b) || return false
        size(a) == size(b) || return false
        for i in 1:size(a, 2)
            typeof(a[i]) == typeof(b[i]) || return false
            a[i] isa LabeledArray ? (rawvalues(a[i]) == rawvalues(b[i]) || return false) :
                (a[i] == b[i] || return false)
            missingtags(a, i) == missingtags(b, i) || return false
        end
        fa, fb = filemetadata(a), filemetadata(b)
        return fa.value_labels == fb.value_labels && fa.notes == fb.notes
    end

    @testset "$file ≡ serial" for file in
        ("sample.dta", "sample.sav", "sample.sas7bdat", "alltypes.dta")
        path = joinpath(dir, file)
        serial = readstat(path; ntasks=1)
        for T in (2, 3, 8)
            @test tables_equal(readstat(path; ntasks=T), serial)
        end
    end

    @testset "kwargs compose with ntasks" begin
        path = joinpath(dir, "sample.dta")
        serial = read_dta(path; row_offset=1, row_limit=3)
        threaded = read_dta(path; row_offset=1, row_limit=3, ntasks=2)
        @test tables_equal(threaded, serial)
        # The pre-pass reports the file's true row count even under a limit.
        @test filemetadata(threaded).row_count == 5

        @test tables_equal(read_dta(path; usecols=[:mynum, :mylabl], ntasks=2),
                           read_dta(path; usecols=[:mynum, :mylabl]))
        @test tables_equal(
            read_sav(joinpath(dir, "sample_missing.sav"); user_missing=:keep, ntasks=2),
            read_sav(joinpath(dir, "sample_missing.sav"); user_missing=:keep))
        @test tables_equal(
            read_sav(joinpath(dir, "sample.sav"); apply_value_labels=true, ntasks=3),
            read_sav(joinpath(dir, "sample.sav"); apply_value_labels=true))
    end

    @testset "tags survive the chunk merge" begin
        tbl = read_dta(joinpath(dir, "alltypes.dta"); ntasks=3)
        @test missingtags(tbl, :vbyte) == ['\0', 'a', '\0']
        @test valuelabels(tbl, :vbyte)['a'] == "Tagged missing"
    end

    @testset "fallbacks" begin
        # Unknown row count: xport cannot split and parses serially.
        xpt = joinpath(dir, "sample.xpt")
        @test tables_equal(readstat(xpt; ntasks=4), readstat(xpt))
        # More tasks than rows.
        @test size(read_dta(joinpath(dir, "sample.dta"); ntasks=100), 1) == 5
        # Zero-row reads keep full metadata.
        tbl = read_sav(joinpath(dir, "sample.sav"); row_limit=0, ntasks=2)
        @test size(tbl) == (0, 7)
        @test !isempty(filemetadata(tbl).value_labels)
    end
end
