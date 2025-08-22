const std = @import("std");
const bzip2 = @import("bzip2");

const Arena = std.heap.ArenaAllocator;

const allocator_wrapper = @import("allocator_wrapper.zig");

/// The lower level Bzip2 decompressor.
/// It operates directly on memory buffers.
/// For a high-level function, see `decompress` which instead works using `Reader` and `Writer`.
///
/// You cannot decompress multiple things using the same decompressor. You must create a new decompressor for each input stream you want to decompress.
pub const Bzip2StreamDecompressor = struct {
    /// The inner bzip2 stream structure. Needs to be heap allocated due to the return semantics of `init` and inner pointer arithmetic done by bzip2.
    stream: *bzip2.bz_stream,
    /// The inner arena allocator. Required to bypass a memory allocation bug when using the default c malloc allocator and the inability for zig allocators to deallocate without knowing the size of the data (which we don't have in the `dealloc` callback.)
    arena: *Arena,
    /// The allocator of the arena, heap allocated. Required to be done this way so that it can be passed to `bz_stream.opaque`.
    allocator: *std.mem.Allocator,

    const S = @This();

    pub const Options = struct {
        verbosity: u8 = 0,
    };

    /// Creates a new `Bzip2StreamCompressor`.
    /// The allocator must live as long as it.
    /// See `Bzip2StreamCompressor.Options` for a list of options (the defaults should be fine for most uses.)
    /// Don't forget to call `deinit` when you are done.
    pub fn init(allocator: std.mem.Allocator, opts: Options) !S {
        var strm = try allocator.create(bzip2.bz_stream);
        errdefer allocator.destroy(strm);

        strm.bzalloc = allocator_wrapper.alloc;
        strm.bzfree = allocator_wrapper.dealloc;
        strm.avail_in = 0;

        const arena_ptr = try allocator.create(Arena);
        errdefer allocator.destroy(arena_ptr);

        // will crash if not heap allocated
        arena_ptr.* = Arena.init(allocator);
        const alloc_ptr = try allocator.create(std.mem.Allocator);
        errdefer allocator.destroy(alloc_ptr);

        alloc_ptr.* = arena_ptr.allocator();
        strm.@"opaque" = @ptrCast(alloc_ptr);
        strm.avail_in = 0;
        const err1 = bzip2.BZ2_bzDecompressInit(strm, @intCast(opts.verbosity), 0);
        errdefer _ = arena_ptr.reset(.free_all);

        switch (err1) {
            bzip2.BZ_OK => {},
            bzip2.BZ_CONFIG_ERROR => return error.BzipConfigError,
            bzip2.BZ_PARAM_ERROR => @panic("Wrong parameter passed to bzip."),
            bzip2.BZ_MEM_ERROR => return error.OutOfMemory,
            else => @panic("Unhandled bzip error."),
        }

        return S{
            .stream = strm,
            .arena = arena_ptr,
            .allocator = alloc_ptr,
        };
    }

    /// Decompresses (part of) the input into the output buffer.
    /// If the return value is equal to the output buffer size, you must call `decompressBuffer` again until it is not.
    pub fn decompressBuffer(s: *S, input: []const u8, output: []u8) !usize {
        s.stream.avail_out = @intCast(output.len);
        s.stream.next_out = output.ptr;

        if (s.stream.avail_in == 0 and input.len > 0) {
            s.stream.avail_in = @intCast(input.len);
            s.stream.next_in = @ptrCast(@constCast(input.ptr));
        }
        const err1 = bzip2.BZ2_bzDecompress(s.stream);
        switch (err1) {
            bzip2.BZ_OK, bzip2.BZ_STREAM_END => {},
            bzip2.BZ_PARAM_ERROR => @panic("Code error in setting up the decompressor"),
            bzip2.BZ_DATA_ERROR => return error.BzipDataStreamInvalid,
            bzip2.BZ_SEQUENCE_ERROR => return error.BzipSequenceInvalid,
            else => @panic("Unexpected bzip error."),
        }

        const written = output.len - s.stream.avail_out;
        return written;
    }

    /// Decompresses the reader into the writer by reading chunks of data, decompressing the chunk and writing that to the writer.
    /// See `decompress` for an easier to use function.
    pub fn decompressAll(s: *S, reader: *std.Io.Reader, writer: *std.Io.Writer) !usize {
        const OUT_BUF_SIZE = 8192;
        var buf_in: [2048]u8 = undefined;
        var buf_out: [OUT_BUF_SIZE]u8 = undefined;
        var done = false;
        var total_written: usize = 0;

        while (!done) {
            // fill input buf
            var buf_len: usize = 0;
            while (buf_len < buf_in.len) {
                const maybe_byte = reader.takeByte();
                if (maybe_byte == error.EndOfStream) {
                    done = true;
                    break;
                }
                buf_in[buf_len] = try maybe_byte;
                buf_len += 1;
            }

            const in_slice = buf_in[0..buf_len];

            // compress input buf into output buf
            var written = try s.decompressBuffer(in_slice, buf_out[0..]);
            total_written += written;
            // Write into the output writer
            try writer.writeAll(buf_out[0..written]);

            while (written == OUT_BUF_SIZE) {
                // we filled the output, which means there's a chance we didn't finish processing the input.
                // we need to keep processing the same input, into a new output buffer.
                // s.stream keeps in mind the location we are at in the input buffer.
                written = try s.decompressBuffer(in_slice, buf_out[0..]);
                total_written += written;
                // Write into the output writer
                try writer.writeAll(buf_out[0..written]);
            }
        }
        return total_written;
    }

    pub fn deinit(s: *S, allocator: std.mem.Allocator) void {
        const err1 = bzip2.BZ2_bzDecompressEnd(s.stream);
        std.debug.assert(err1 == bzip2.BZ_OK);
        allocator.destroy(s.allocator);
        allocator.destroy(s.stream);
        s.arena.deinit();
        allocator.destroy(s.arena);
    }
};
