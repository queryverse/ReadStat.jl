using TestItemRunner

include("test_abi.jl")
include("test_readstat.jl")

@run_package_tests
