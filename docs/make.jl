using Documenter, ReadStat

makedocs(
    modules=[ReadStat],
    sitename="ReadStat.jl",
    analytics="UA-132838790-1",
    pages=[
        "Introduction" => "index.md"
    ]
)

deploydocs(
    repo="github.com/queryverse/ReadStat.jl.git"
)
