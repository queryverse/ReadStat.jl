@testitem "ReadStatSource and chunks" begin
    using DataValues
    using Dates

    dir = joinpath(@__DIR__, "data")
    path = joinpath(dir, "sample.dta")

    @testset "planning surface" begin
        src = ReadStatSource(path; apply_value_labels=true)
        s = schema(src)
        @test size(s, 1) == 0
        @test colnames(src) == [:mychar, :mynum, :mydate, :dtime, :mylabl, :myord, :mytime]
        @test nrows(src) == 5
        ct = coltypes(src)
        @test ct[1] == DataValue{String}
        @test ct[3] == DataValue{Date}
        @test ct[4] == DataValue{DateTime}
        @test supports(src, :projection)
        @test supports(src, :row_range)
        @test supports(src, :row_count)
        @test supports(src, :parallel)
        @test !supports(src, :frobnicate)

        xsrc = ReadStatSource(joinpath(dir, "sample.xpt"))
        @test ismissing(nrows(xsrc))
        @test !supports(xsrc, :row_count)
        @test !supports(xsrc, :parallel)

        # The schema's column types match what a read produces.
        full = read(src)
        @test size(full) == (5, 7)
        @test [eltype(full[i]) for i in 1:7] == ct
        @test full[:mylabl] isa LabeledArray

        part = read(src; rows=2:4, usecols=[:mynum])
        @test size(part) == (3, 1)
        @test part[:mynum] == read_dta(path)[:mynum][2:4]
        @test_throws ArgumentError read(src; rows=0:3)

        # An IO-backed source serves schema and repeated reads off one stream.
        io_src = ReadStatSource(open(path); format=:dta)
        @test nrows(io_src) == 5
        @test size(read(io_src)) == (5, 7)
        @test size(read(io_src; rows=1:2)) == (2, 7)
        @test_throws ArgumentError ReadStatSource(IOBuffer(UInt8[]))
    end

    @testset "chunks ≡ full read" begin
        src = ReadStatSource(path; apply_value_labels=true)
        full = read(src)
        pieces = collect(chunks(src; chunksize=2))
        @test length(pieces) == 3
        @test [size(p, 1) for p in pieces] == [2, 2, 1]
        for j in 1:size(full, 2)
            @test isequal(reduce(vcat, [collect(p[j]) for p in pieces]), collect(full[j]))
        end
        # Metadata and labels are complete from the first chunk on.
        @test pieces[1][:mylabl] isa LabeledArray
        @test valuelabel(get(pieces[1][:mylabl][1])) in ("Male", "Female")
        @test names(pieces[1]) == names(full)

        # A chunk size beyond the file yields one chunk.
        @test length(collect(chunks(src; chunksize=100))) == 1
    end

    @testset "chunks with pushdown and unknown row counts" begin
        src = ReadStatSource(path)
        expected = read(src; rows=2:5, usecols=[:mynum, :mydate])
        pieces = collect(chunks(src; rows=2:5, usecols=[:mynum, :mydate], chunksize=3))
        @test [size(p, 1) for p in pieces] == [3, 1]
        @test names(pieces[1]) == [:mynum, :mydate]
        for j in 1:2
            @test isequal(reduce(vcat, [collect(p[j]) for p in pieces]), collect(expected[j]))
        end

        # Formats without a recorded row count stream fine.
        xsrc = ReadStatSource(joinpath(dir, "sample.xpt"))
        pieces = collect(chunks(xsrc; chunksize=2))
        @test [size(p, 1) for p in pieces] == [2, 2, 1]
    end

    @testset "early termination" begin
        src = ReadStatSource(path)
        it = chunks(src; chunksize=1)
        step = iterate(it)
        @test step !== nothing
        @test size(step[1], 1) == 1
        close(it)
        # Chunks already buffered when the iterator was closed still drain
        # (bounded channel of 2); after that, iteration ends and the parse
        # task has been released rather than blocking forever.
        drained = collect(it)
        @test length(drained) <= 2
        @test iterate(it) === nothing
    end

    # zsav coverage rides along here.
    @test size(read_sav(joinpath(dir, "sample.zsav"))) == (5, 7)
end
