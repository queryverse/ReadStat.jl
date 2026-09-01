# Parsing from Julia IO streams via the C library's custom IO handlers.
#
# The C parsers drive all reading through an open/close/seek/read handler
# quartet; installing Julia implementations lets any seekable IO (an open
# file, an IOBuffer over bytes from anywhere) be parsed without touching the
# file system. Non-seekable streams are slurped into an IOBuffer first — the
# parsers seek backwards routinely, so streaming through them directly is
# not possible.
#
# The stream must contain the complete file starting at position 0: seek
# offsets from the C side are absolute.

mutable struct IOSource
    io::IO
    size::Int64
    err::Union{Nothing,Tuple{Any,Any}}
end

# Buffer a non-seekable stream in memory; the parsers seek backwards.
function _ensure_seekable(io::IO)
    seekable = try
        seek(io, position(io))
        true
    catch
        false
    end
    return seekable ? io : IOBuffer(read(io))
end

function IOSource(io::IO)
    io = _ensure_seekable(io)
    seekend(io)
    size = Int64(position(io))
    # Rewind so the same stream can be parsed repeatedly (ReadStatSource
    # reads its schema first and the data later).
    seekstart(io)
    return IOSource(io, size, nothing)
end

# The C side treats an open-handler return of -1 as failure; the stream is
# already open, so both open and close are no-ops.
handle_io_open(path::Cstring, io_ctx::Ptr{Cvoid})::Cint = Cint(0)
handle_io_close(io_ctx::Ptr{Cvoid})::Cint = Cint(0)

function handle_io_seek(offset::Int64, whence::ReadStatIOFlags, io_ctx::Ptr{Cvoid})::Int64
    src = unsafe_pointer_to_objref(io_ctx)::IOSource
    try
        pos = whence == READSTAT_SEEK_SET ? offset :
              whence == READSTAT_SEEK_CUR ? Int64(position(src.io)) + offset :
              src.size + offset
        (pos < 0 || pos > src.size) && return Int64(-1)
        seek(src.io, pos)
        return Int64(position(src.io))
    catch e
        src.err = (e, catch_backtrace())
        return Int64(-1)
    end
end

function handle_io_read(buf::Ptr{Cvoid}, nbyte::Csize_t, io_ctx::Ptr{Cvoid})::Cssize_t
    src = unsafe_pointer_to_objref(io_ctx)::IOSource
    try
        io = src.io
        n = min(Int(nbyte), max(src.size - Int64(position(io)), 0))
        n <= 0 && return Cssize_t(0)
        unsafe_read(io, Ptr{UInt8}(buf), UInt(n))
        return Cssize_t(n)
    catch e
        src.err = (e, catch_backtrace())
        return Cssize_t(-1)
    end
end

const CF_IO_OPEN = Ref(C_NULL)
const CF_IO_CLOSE = Ref(C_NULL)
const CF_IO_SEEK = Ref(C_NULL)
const CF_IO_READ = Ref(C_NULL)

function _init_io_cfunctions()
    CF_IO_OPEN[] = @cfunction(handle_io_open, Cint, (Cstring, Ptr{Cvoid}))
    CF_IO_CLOSE[] = @cfunction(handle_io_close, Cint, (Ptr{Cvoid},))
    CF_IO_SEEK[] = @cfunction(handle_io_seek, Int64, (Int64, ReadStatIOFlags, Ptr{Cvoid}))
    CF_IO_READ[] = @cfunction(handle_io_read, Cssize_t, (Ptr{Cvoid}, Csize_t, Ptr{Cvoid}))
    return nothing
end
