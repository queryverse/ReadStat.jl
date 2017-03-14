using BinDeps

@BinDeps.setup

# The version of ReadStat to use
readstat_version = "0.1.1"

libreadstat = library_dependency("libreadstat", aliases=["libreadstat-0"])

provides(Sources, URI("https://github.com/WizardMac/ReadStat/releases/download/v$readstat_version/readstat-$readstat_version.tar.gz"),
    libreadstat, os=:Unix, unpacked_dir="readstat-$readstat_version")

prefix = joinpath(BinDeps.depsdir(libreadstat), "usr")
srcdir = joinpath(BinDeps.depsdir(libreadstat), "src", "readstat-$readstat_version")

provides(SimpleBuild,
    (@build_steps begin
        GetSources(libreadstat)
        @build_steps begin
            ChangeDirectory(srcdir)
            `./configure --prefix=$prefix`
            `make`
            `make install`
        end
    end), libreadstat, os=:Unix)

@static if is_windows()
    using WinRPM
    push!(WinRPM.sources, "http://download.opensuse.org/repositories/home:/davidanthoff/openSUSE_13.2")
    WinRPM.update()
    provides(WinRPM.RPM, "readstat", [libreadstat], os = :Windows)
end

@BinDeps.install Dict([(:libreadstat, :libreadstat)])
