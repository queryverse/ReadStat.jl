@testitem "reading from IO" begin
    using DataValues

    dir = @__DIR__

    # A minimal read-only, non-seekable stream to exercise the buffering path.
    struct NoSeekIO <: IO
        inner::IOBuffer
    end
    Base.read(io::NoSeekIO, ::Type{UInt8}) = read(io.inner, UInt8)
    Base.eof(io::NoSeekIO) = eof(io.inner)

    @testset "$file" for (reader, file) in
        ((read_dta, "types.dta"), (read_sav, "types.sav"),
         (read_sas7bdat, "types.sas7bdat"), (read_xport, "types.xpt"))
        path = joinpath(dir, file)
        expected = reader(path)

        for source in (open(path), IOBuffer(read(path)), NoSeekIO(IOBuffer(read(path))))
            tbl = reader(source)
            @test names(tbl) == names(expected)
            @test size(tbl) == size(expected)
            for i in 1:size(tbl, 2)
                @test tbl[i] == expected[i]
            end
            source isa IOStream && close(source)
        end
    end

    @testset "kwargs compose with IO input" begin
        path = joinpath(dir, "types.dta")
        tbl = read_dta(IOBuffer(read(path)); usecols=[:vlong], row_limit=2)
        @test names(tbl) == [:vlong]
        @test tbl[:vlong] == DataValueArray{Int32}([2, 7])
    end

    @testset "dispatcher and read_meta over IO" begin
        path = joinpath(dir, "types.sav")
        io = IOBuffer(read(path))
        @test size(readstat(io; format=:sav)) == (3, 6)
        @test_throws ArgumentError readstat(IOBuffer(read(path)))

        m = read_meta(IOBuffer(read(path)); format=:sav)
        @test size(m) == (0, 6)
        @test filemetadata(m).row_count == 3
    end
end
