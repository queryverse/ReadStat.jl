@testitem "date/time conversion" begin
    using DataValues
    using Dates

    dir = joinpath(@__DIR__, "data")

    expected_dates = DataValueArray{Date}(
        [Date(2018, 5, 6), Date(1880, 5, 6), Date(1960, 1, 1), Date(1583, 1, 1), NA])
    expected_dtimes = DataValueArray{DateTime}(
        [DateTime(2018, 5, 6, 10, 10, 10), DateTime(1880, 5, 6, 10, 10, 10),
         DateTime(1960, 1, 1), DateTime(1583, 1, 1), NA])
    expected_times = [36610.0, 83410.0, 0.0, 58210.0]  # seconds of day, row 5 NA

    @testset "$file" for (file, datecol, dtimecol, timecol) in
        (("sample.dta", :mydate, :dtime, nothing),       # mytime in .dta is %tc, tested below
         ("sample.sav", :mydate, :dtime, :mytime),
         ("sample.por", :MYDATE, :DTIME, :MYTIME),
         ("sample.sas7bdat", :mydate, :dtime, :mytime),
         ("sample.xpt", :MYDATE, :DTIME, :MYTIME))

        tbl = readstat(joinpath(dir, file))
        @test tbl[datecol] == expected_dates
        @test tbl[dtimecol] == expected_dtimes
        if timecol !== nothing
            col = tbl[timecol]
            @test eltype(eltype(col)) === HMS
            @test [unwrap(get(x)) for x in col[1:4]] == expected_times
            @test isna(col[5])
        end

        # Raw numbers when conversion is off.
        raw = readstat(joinpath(dir, file); convert_datetime=false)
        @test eltype(eltype(raw[datecol])) <: Number
    end

    @testset "Stata %tc time-of-day and DATETIME13" begin
        tbl = read_dta(joinpath(dir, "sample.dta"))
        # mytime uses %tcHH:MM:SS — a datetime anchored at the epoch day.
        @test get(tbl[:mytime][1]) == DateTime(1960, 1, 1, 10, 10, 10)

        x = readstat(joinpath(dir, "datetime13.xpt"))
        @test get(x[:DTTEST][1]) == DateTime(1960, 1, 2, 10, 17, 36)

        a = read_dta(joinpath(dir, "alltypes.dta"))
        @test get(a[:vdate][1]) == Date(1960, 1, 2)       # %td, value 1
        @test get(a[:vtime][1]) == DateTime(1960, 1, 1, 0, 0, 0, 1)  # %tc, value 1
        @test isna(a[:vdate][2]) && isna(a[:vdate][3])
    end

    @testset "HMS" begin
        t = HMS(36610.0)
        @test unwrap(t) == 36610.0
        @test Dates.hour(t) == 10
        @test Dates.minute(t) == 10
        @test Dates.second(t) == 10
        @test sprint(show, t) == "10:10:10"
        @test Time(t) == Time(10, 10, 10)

        # Durations beyond a day and negative durations are representable.
        long = HMS(30 * 3600.0)
        @test Dates.hour(long) == 30
        @test sprint(show, long) == "30:00:00"
        @test_throws ArgumentError Time(long)
        @test sprint(show, HMS(-3661.0)) == "-1:01:01"
        @test Dates.hour(HMS(-3661.0)) == -1

        @test sprint(show, HMS(0.5)) == "0:00:00.500"
        @test HMS(1.0) < HMS(2.0)
        @test HMS(1.0) == HMS(1.0)
        @test hash(HMS(1.0)) == hash(HMS(1.0))
    end

    @testset "format classification" begin
        @test ReadStat.datetime_rule("%tm", :dta) !== nothing
        f, T = ReadStat.datetime_rule("%tm", :dta)
        @test T === Date && f(1) == Date(1960, 2, 1)
        f, T = ReadStat.datetime_rule("%tq", :dta)
        @test f(1) == Date(1960, 4, 1)
        f, T = ReadStat.datetime_rule("%th", :dta)
        @test f(1) == Date(1960, 7, 1)
        f, T = ReadStat.datetime_rule("%ty", :dta)
        @test f(1987) == Date(1987, 1, 1)
        f, T = ReadStat.datetime_rule("%tw", :dta)
        @test f(0) == Date(1960, 1, 1)
        @test f(52) == Date(1961, 1, 1)

        @test ReadStat.datetime_rule("F8.2", :sav) === nothing
        @test ReadStat.datetime_rule("BEST12", :sas7bdat) === nothing
        @test ReadStat.datetime_rule("", :dta) === nothing
        @test ReadStat.datetime_rule("DATETIME22.3", :sas7bdat) !== nothing
        @test ReadStat.datetime_rule("MMDDYYS10", :xport) !== nothing
        @test ReadStat.datetime_rule("SDATE10", :por) !== nothing
        @test ReadStat.datetime_rule("DTIME10", :sav) !== nothing
    end
end
