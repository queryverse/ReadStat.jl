using BinDeps

@BinDeps.setup

libreadstat = library_dependency("libreadstat", aliases=["libreadstat-0"])

provides(Sources, URI("http://github.com/WizardMac/ReadStat/archive/master.tar.gz"),
    libreadstat, os=:Unix, unpacked_dir="ReadStat-master")

srcdir = joinpath(BinDeps.depsdir(libreadstat), "src", "ReadStat-master")

provides(SimpleBuild,
    (@build_steps begin
        GetSources(libreadstat)
        @build_steps begin
            ChangeDirectory(srcdir)
            `./autogen.sh`
            `./configure`
            `make`
        end
    end), libreadstat, os=:Unix)

@windows_only begin
    using WinRPM
    push!(WinRPM.sources, "http://download.opensuse.org/repositories/home:/davidanthoff/openSUSE_13.2")
    WinRPM.update()
    provides(WinRPM.RPM, "readstat", [libreadstat], os = :Windows)
end

@BinDeps.install Dict([(:libreadstat, :libreadstat)])
