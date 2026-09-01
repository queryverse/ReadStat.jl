using TestItemRunner

include("test_abi.jl")
include("test_read.jl")
include("test_deprecated.jl")

@run_package_tests
