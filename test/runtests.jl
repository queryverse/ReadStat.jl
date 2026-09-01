using TestItemRunner

include("test_abi.jl")
include("test_read.jl")
include("test_kwargs.jl")
include("test_missing.jl")
include("test_labels.jl")
include("test_datetime.jl")
include("test_io.jl")
include("test_threads.jl")
include("test_source.jl")
include("test_write.jl")
include("test_deprecated.jl")

@run_package_tests
