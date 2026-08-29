using Documenter, ReadStat

makedocs(
	modules = [ReadStat],
	sitename = "ReadStat.jl",
	format = Documenter.HTML(analytics = "UA-132838790-1"),
	warnonly = [:missing_docs],
	pages = [
        "Introduction" => "index.md"
    ]
)

deploydocs(
    repo = "github.com/queryverse/ReadStat.jl.git"
)
