using BinaryProvider

const prefix = Prefix(joinpath(@__DIR__,"usr"))

const platform = platform_key()

libreadstat = LibraryProduct(prefix, "libreadstat")

const bin_prefix="https://github.com/davidanthoff/ReadStatBuilder/releases/download/v0.1.2-pre%2Bbuild.1"

# TODO Update hash values, only the Windows x64 hash is correct right now
const download_info = Dict(
    Linux(:i686) =>     ("$bin_prefix/readstat.i686-linux-gnu.tar.gz", "f77422c570ecfdbf4f73c421f73d326ca58ae6e991e11b9327bdca7a88f752cc"),
    Linux(:x86_64) =>   ("$bin_prefix/readstat.x86_64-linux-gnu.tar.gz", "10a19e73f1b06969e46a5fb084c7646369437d8ffdecd871b739074db26b2bbf"),
    Linux(:aarch64) =>  ("$bin_prefix/readstat.aarch64-linux-gnu.tar.gz", "c6caf757df977801d835f2741d79a655f3511aad7645e827ff4bb7fdc63206b5"),
    Linux(:armv7l) =>   ("$bin_prefix/readstat.arm-linux-gnueabihf.tar.gz", "681b63cb71ab72e714562a2bf8a24c2a30d515c5333a9d922808ac427fc05e68"),
    Linux(:ppc64le) =>  ("$bin_prefix/readstat.powerpc64le-linux-gnu.tar.gz", "a6323f24b55f502bd1316b1f81b69493d863dab38fa2efc73bf6c260bf91462f"),
    MacOS() =>          ("$bin_prefix/readstat.x86_64-apple-darwin14.tar.gz", "bca0547cee2f4bb94d9b744def548c0d32e59bb59e81c3baa3be66c544b52635"),
    Windows(:i686) =>   ("$bin_prefix/readstat.i686-w64-mingw32.tar.gz", "3316ce88a1ed0ba8c9a3df6556ed8c353692b3a3c024a30920650b766afc87ab"),
    Windows(:x86_64) => ("$bin_prefix/readstat.x86_64-w64-mingw32.tar.gz", "4c8c80513f7e3d8736ff32d61cb9a1a41d09a8487656e8ecde0798175a57c179"),
)

if platform in keys(download_info)
    # Grab the url and tarball hash for this particular platform
    url, tarball_hash = download_info[platform]

    install(url, tarball_hash; prefix=prefix, force=true, verbose=true)

    # Finaly, write out a deps file containing paths to libreadstat
    @write_deps_file libreadstat
else
    error("Your platform $(Sys.MACHINE) is not recognized, we cannot install libreadstat.")
end
