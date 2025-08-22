/// The bzip2 compressor/decompressor ported to zig.
/// We wrap over the original C files into a convenient zig module.
/// Running the compressor requires a minimum of ~4.2MB of memory available in the allocator passed to it.
/// # Uses
/// For simple uses, the `compress` and `decompress` functions should be entirely sufficient. They automatically stream data from the input reader to the output writer.
///
/// For more advanced uses, `Bzip2StreamCompressor` and `Bzip2StreamDecompressor` are available.
/// However, we recommend against using them directly due to their complexity and the apparent lack of advantages in using the lower level interfaces.
const std = @import("std");

pub const Bzip2StreamCompressor = @import("compressor.zig").Bzip2StreamCompressor;
pub const Bzip2StreamDecompressor = @import("decompressor.zig").Bzip2StreamDecompressor;

/// Compresses the bytes from `reader` into `writer` using bzip2.
/// The allocator will automatically clean up after itself when the function ends.
pub fn compress(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, options: Bzip2StreamCompressor.Options) !usize {
    var compressor = try Bzip2StreamCompressor.init(allocator, options);
    defer compressor.deinit(allocator);

    const total = try compressor.compressAll(reader, writer);
    return total;
}

/// Decompresses the bytes from `reader` into `writer` using bzip2.
/// The allocator will automatically clean up after itself when the function ends.
pub fn decompress(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, options: Bzip2StreamDecompressor.Options) !usize {
    var decompressor = try Bzip2StreamDecompressor.init(allocator, options);
    defer decompressor.deinit(allocator);

    const total = try decompressor.decompressAll(reader, writer);
    return total;
}

/// Wrapping the internal error message since we use the no-std mode of bzip2.
/// Required to avoid a linker error.
export fn bz_internal_error(errcode: c_int) void {
    var msg: [128]u8 = undefined;
    const msg_formatted = std.fmt.bufPrint(msg[0..], "Received bzip2 internal error code: {}", .{errcode}) catch {return;};
    @panic(msg_formatted);
}

test "import" {
    _ = @import("tests.zig");
}
