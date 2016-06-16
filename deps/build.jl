using BinDeps

@BinDeps.setup

libreadstat = library_dependency("libreadstat", aliases=["libreadstat-0"])

@windows_only begin
    using WinRPM
    push!(WinRPM.sources, "http://download.opensuse.org/repositories/home:/davidanthoff/openSUSE_13.2")
    WinRPM.update()
    provides(WinRPM.RPM, "readstat", [libreadstat], os = :Windows)
end

@BinDeps.install Dict([(:libreadstat, :libreadstat)])
