const std = @import("std");
const bzip2 = @import("bzip2");

const Arena = std.heap.ArenaAllocator;

const allocator_wrapper = @import("allocator_wrapper.zig");

/// The lower level Bzip2 compressor.
/// It operates directly on memory buffers.
/// For a high-level function, see `compress` which instead works using `Reader` and `Writer`.
///
/// You cannot compress multiple things using the same compressor. You must create a new compressor for each input stream you want to compress.
pub const Bzip2StreamCompressor = struct {
    /// The inner bzip2 stream structure. Needs to be heap allocated due to the return semantics of `init` and inner pointer arithmetic done by bzip2.
    stream: *bzip2.bz_stream,
    /// The inner arena allocator. Required to bypass a memory allocation bug when using the default c malloc allocator and the inability for zig allocators to deallocate without knowing the size of the data (which we don't have in the `dealloc` callback.)
    arena: *Arena,
    /// The allocator of the arena, heap allocated. Required to be done this way so that it can be passed to `bz_stream.opaque`.
    allocator: *std.mem.Allocator,

    const S = @This();

    /// The options for the bzip2 stream compressor.
    pub const Options = struct {
        /// 1=fast (optimize for speed and memory use)
        /// 9=best (optimize for output size)
        block_size_100k: u8 = 5,
        /// The verbosity level.
        verbosity: u8 = 0,
        /// How much work bzip2 will put into compressing your data.
        /// See bzip2's documentation for details.
        work_factor: u8 = 30,
    };

    /// The action to run on the bzip2 internal compressor.
    /// Usually, you will be calling run repeatedly until no data is left, then call finish.
    pub const Action = enum(u2) {
        run = bzip2.BZ_RUN,
        flush = bzip2.BZ_FLUSH,
        finish = bzip2.BZ_FINISH,
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

        const err1 = bzip2.BZ2_bzCompressInit(strm, @intCast(opts.block_size_100k), @intCast(opts.verbosity), @intCast(opts.work_factor));
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

    /// Does some part of the compression process.
    /// # Returns
    /// Returns either BZ_RUN_OK (true), BZ_FLUSH_OK (true), BZ_FINISH_OK (false), BZ_STREAM_END (false) or an error.
    /// # Errors
    /// The possible errors are:
    /// - BZ_PARAM_ERROR
    /// - BZ_SEQUENCE_ERROR
    pub fn compressInner(s: *S, action: Action) !bool {
        const ret1 = bzip2.BZ2_bzCompress(s.stream, @intFromEnum(action));
        return switch (ret1) {
            bzip2.BZ_RUN_OK, bzip2.BZ_FLUSH_OK, bzip2.BZ_FINISH_OK => true,
            bzip2.BZ_STREAM_END => false,
            bzip2.BZ_PARAM_ERROR => error.ParameterError,
            bzip2.BZ_SEQUENCE_ERROR => error.SequenceError,
            else => @panic("Unhandled bzip2 error."),
        };
    }

    /// Compresses (part of) the input into the output buffer.
    /// If the return value is equal to the output buffer size, you must call `compressBuffer` again until it is not.
    pub fn compressBuffer(s: *S, input: []const u8, output: []u8) !u64 {
        if (s.stream.avail_in == 0) {
            // only eat new input once the previous is done.
            s.stream.avail_in = @intCast(input.len);
            s.stream.next_in = @ptrCast(@constCast(input.ptr));
        }

        s.stream.avail_out = @intCast(output.len);
        s.stream.next_out = output.ptr;
        _ = try s.compressInner(.run);

        const written: usize = @intCast(output.len - s.stream.avail_out);
        return written;
    }

    /// Finishes the compression and writes a bit of final data to output.
    /// # Panics
    /// Will assert if the input stream was not fully consumed prior to calling finish.
    pub fn compressFinish(s: *S, output: []u8) !u64 {
        // Should not be calling compressFinish if we are not done processing the input stream.
        std.debug.assert(s.stream.avail_in == 0);

        s.stream.avail_out = @intCast(output.len);
        s.stream.next_out = output.ptr;
        _ = try s.compressInner(.finish);
        const written: usize = @intCast(output.len - s.stream.avail_out);
        return written;
    }

    /// Compresses by reading chunks from the `Reader`, compressing it and writing it into the `Writer`.
    /// At the end, will write some more into the writer to finalize the data.
    pub fn compressAll(s: *S, reader: *std.Io.Reader, writer: *std.Io.Writer) !usize {
        const OUT_BUF_SIZE = 4096;
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
                } else if (maybe_byte == error.ReadFailed) {
                    return error.ReadFailed;
                }
                buf_in[buf_len] = try maybe_byte;
                buf_len += 1;
            }

            // compress input buf into output buf
            var written = try s.compressBuffer(buf_in[0..buf_len], buf_out[0..]);
            std.debug.assert(written <= OUT_BUF_SIZE);
            total_written += written;

            // Write into the output writer
            try writer.writeAll(buf_out[0..written]);

            while (written == OUT_BUF_SIZE) {
                // we are not done processing the input but the output buffer was full.
                written = try s.compressBuffer(buf_in[0..buf_len], buf_out[0..]);
                std.debug.assert(written <= OUT_BUF_SIZE);
                total_written += written;

                // Write into the output writer
                try writer.writeAll(buf_out[0..written]);
            }
        }

        var written = try s.compressFinish(buf_out[0..]);
        std.debug.assert(written <= OUT_BUF_SIZE);
        total_written += written;
        try writer.writeAll(buf_out[0..written]);
        while (written == OUT_BUF_SIZE) {
            // not done writing compressFinish's output because it did not fit into the output buffer.
            written = try s.compressFinish(buf_out[0..]);
            std.debug.assert(written <= OUT_BUF_SIZE);
            total_written += written;
            try writer.writeAll(buf_out[0..written]);
        }

        const bzip2_written: u64 = (@as(u64, @intCast(s.stream.total_out_hi32)) << 32) | @as(u64, @intCast(s.stream.total_out_lo32));
        std.debug.assert(bzip2_written == total_written);

        return total_written;
    }

    pub fn deinit(s: *S, allocator: std.mem.Allocator) void {
        const err1 = bzip2.BZ2_bzCompressEnd(s.stream);
        std.debug.assert(err1 == bzip2.BZ_OK);
        allocator.destroy(s.allocator);
        allocator.destroy(s.stream);
        s.arena.deinit();
        allocator.destroy(s.arena);
    }
};
