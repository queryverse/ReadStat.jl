using TestItemRunner

include("test_abi.jl")
include("test_read.jl")
include("test_kwargs.jl")
include("test_missing.jl")
include("test_labels.jl")
include("test_datetime.jl")
include("test_deprecated.jl")

@run_package_tests
