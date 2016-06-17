using BinDeps

@BinDeps.setup

libreadstat = library_dependency("libreadstat", aliases=["libreadstat-0"])

provides(Sources, URI("http://github.com/WizardMac/ReadStat/archive/e7ca8b7530023d2b91e1f0dbaf7a86d39034d8b7.tar.gz"),
    libreadstat, os=:Unix, unpacked_dir="ReadStat-e7ca8b7530023d2b91e1f0dbaf7a86d39034d8b7")

prefix = joinpath(BinDeps.depsdir(libreadstat), "usr")
srcdir = joinpath(BinDeps.depsdir(libreadstat), "src", "ReadStat-e7ca8b7530023d2b91e1f0dbaf7a86d39034d8b7")

provides(SimpleBuild,
    (@build_steps begin
        GetSources(libreadstat)
        @build_steps begin
            ChangeDirectory(srcdir)
            `./autogen.sh`
            `./configure --prefix=$prefix`
            `make`
            `make install`
        end
    end), libreadstat, os=:Unix)

@windows_only begin
    using WinRPM
    push!(WinRPM.sources, "http://download.opensuse.org/repositories/home:/davidanthoff/openSUSE_13.2")
    WinRPM.update()
    provides(WinRPM.RPM, "readstat", [libreadstat], os = :Windows)
end

@BinDeps.install Dict([(:libreadstat, :libreadstat)])
