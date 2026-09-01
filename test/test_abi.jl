@testitem "C ABI: ReadStatValue layout" begin
    using ReadStat: CAPI
    using ReadStat_jll: libreadstat

    # readstat_value_t: 8-byte value union, Cint type at 8, char tag at 12,
    # then two 1-bit bitfields. SysV GCC packs the bitfields into byte 13
    # (size 16); MinGW GCC uses MS bitfield layout, placing a fresh unsigned
    # int unit at offset 16 (size 24).
    @test sizeof(CAPI.ReadStatValue) == (Sys.iswindows() ? 24 : 16)
    @test fieldoffset(CAPI.ReadStatValue, findfirst(==(:type), fieldnames(CAPI.ReadStatValue))) == 8
    @test fieldoffset(CAPI.ReadStatValue, findfirst(==(:tag), fieldnames(CAPI.ReadStatValue))) == 12
    @test fieldoffset(CAPI.ReadStatValue, findfirst(==(:bits), fieldnames(CAPI.ReadStatValue))) ==
        (Sys.iswindows() ? 16 : 13)

    # Behavioral check of the by-value ABI in both directions. Missing ranges
    # declared on a writer variable come back as readstat_value_t BY VALUE from
    # readstat_variable_get_missing_range_lo/_hi, and are then passed BY VALUE
    # into the accessor functions. If the struct layout disagreed with the C
    # library, these reads would come back as garbage rather than the exact
    # doubles inserted below.
    writer = @ccall libreadstat.readstat_writer_init()::CAPI.WriterPtr
    @test writer != C_NULL
    try
        var = @ccall libreadstat.readstat_add_variable(
            writer::CAPI.WriterPtr, "x"::Cstring,
            CAPI.READSTAT_TYPE_DOUBLE::CAPI.ReadStatType, 8::Csize_t)::CAPI.VariablePtr
        @test var != C_NULL

        @test (@ccall libreadstat.readstat_variable_add_missing_double_range(
            var::CAPI.VariablePtr, (-99.5)::Cdouble, (-90.25)::Cdouble)::CAPI.ReadStatError) ==
            CAPI.READSTAT_OK
        @test (@ccall libreadstat.readstat_variable_add_missing_double_value(
            var::CAPI.VariablePtr, 999.0::Cdouble)::CAPI.ReadStatError) == CAPI.READSTAT_OK

        @test CAPI.readstat_variable_get_missing_ranges_count(var) == 2

        lo = CAPI.readstat_variable_get_missing_range_lo(var, 0)
        hi = CAPI.readstat_variable_get_missing_range_hi(var, 0)
        @test CAPI.readstat_value_type(lo) == CAPI.READSTAT_TYPE_DOUBLE
        @test CAPI.readstat_double_value(lo) == -99.5
        @test CAPI.readstat_double_value(hi) == -90.25
        @test CAPI.readstat_value_tag(lo) == '\0'
        @test !CAPI.readstat_value_is_system_missing(lo)
        @test !CAPI.readstat_value_is_tagged_missing(lo)

        # A singleton "range" (lo == hi) carrying the flag bits through the
        # by-value path: 999.0 is defined missing for this variable.
        v = CAPI.readstat_variable_get_missing_range_lo(var, 1)
        @test CAPI.readstat_double_value(v) == 999.0
        @test CAPI.readstat_value_is_defined_missing(v, var)
        @test CAPI.readstat_value_is_missing(v, var)
        @test !CAPI.readstat_value_is_missing(v, C_NULL)
    finally
        @ccall libreadstat.readstat_writer_free(writer::CAPI.WriterPtr)::Cvoid
    end
end
