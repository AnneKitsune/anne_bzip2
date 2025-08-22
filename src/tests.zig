const std = @import("std");
const bzip2 = @import("bzip2");

const Arena = std.heap.ArenaAllocator;

pub const Bzip2StreamCompressor = @import("compressor.zig").Bzip2StreamCompressor;
pub const Bzip2StreamDecompressor = @import("decompressor.zig").Bzip2StreamDecompressor;

const test_plain_data = @embedFile("test_data/test.txt");
const test_compressed_data = @embedFile("test_data/test.txt.bz2");
const test_plain_large_data = @embedFile("test_data/large.txt");
const test_compressed_large_data = @embedFile("test_data/large.txt.bz2");

const root = @import("root.zig");

fn testCompress(allocator: std.mem.Allocator, in: []const u8, expected: []const u8) !void {
    var reader = std.Io.Reader.fixed(in[0..in.len]);
    var compressed: []u8 = try allocator.alloc(u8, expected.len);
    defer allocator.free(compressed);
    var writer = std.Io.Writer.fixed(compressed[0..]);

    const total = try root.compress(allocator, &reader, &writer, .{});

    try std.testing.expectEqual(expected.len, total);
    try std.testing.expectEqualDeep(expected, compressed[0..total]);
}

fn testDecompress(allocator: std.mem.Allocator, in: []const u8, expected: []const u8) !void {
    var reader = std.Io.Reader.fixed(in[0..in.len]);
    var decompressed: []u8 = try allocator.alloc(u8, expected.len);
    defer allocator.free(decompressed);
    var writer = std.Io.Writer.fixed(decompressed[0..]);

    const total = try root.decompress(allocator, &reader, &writer, .{});

    try std.testing.expectEqual(expected.len, total);
    try std.testing.expectEqualDeep(expected, decompressed[0..total]);
}

test "compress" {
    try testCompress(std.testing.allocator, test_plain_data[0..test_plain_data.len], test_compressed_data[0..test_compressed_data.len]);
}

test "decompress" {
    try testDecompress(std.testing.allocator, test_compressed_data[0..test_compressed_data.len], test_plain_data[0..test_plain_data.len]);
}

test "compress large" {
    try testCompress(std.testing.allocator, test_plain_large_data[0..test_plain_large_data.len], test_compressed_large_data[0..test_compressed_large_data.len]);
}

test "decompress large" {
    try testDecompress(std.testing.allocator, test_compressed_large_data[0..test_compressed_large_data.len], test_plain_large_data[0..test_plain_large_data.len]);
}

test "compress buffer too small" {
    // should error out and not panic
    const ret = testCompress(std.testing.allocator, test_plain_large_data[0..test_plain_large_data.len], test_compressed_large_data[0 .. test_compressed_large_data.len - 10]);
    try std.testing.expectError(error.WriteFailed, ret);
}

test "decompress buffer too small" {
    // should error out and not panic
    const ret = testDecompress(std.testing.allocator, test_compressed_large_data[0..test_compressed_large_data.len], test_plain_large_data[0 .. test_plain_large_data.len - 10]);
    try std.testing.expectError(error.WriteFailed, ret);
}

test "decompress cut input" {
    // should error out but not panic
    const ret = testDecompress(std.testing.allocator, test_compressed_large_data[0 .. test_compressed_large_data.len - 10], test_plain_large_data[0..test_plain_large_data.len]);
    if (ret) |_| {
        return error.ExpectedError;
    } else |_| {}
}

test "memory constraining compression" {
    // progressively reduce memory until zero while running compression/decompression
    // should error out at some point but not panic.
    var max_alloc: i32 = 100;
    while (max_alloc >= 0) {
        var failing_alloc = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = @intCast(max_alloc) });
        const ret = testCompress(failing_alloc.allocator(), test_plain_data[0..test_plain_data.len], test_compressed_data[0..test_compressed_data.len]);
        if (ret) |_| {} else |_| {
            try std.testing.expectError(error.OutOfMemory, ret);
        }
        max_alloc -= 1;
    }
}
