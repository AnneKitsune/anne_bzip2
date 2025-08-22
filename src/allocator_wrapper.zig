const std = @import("std");

/// Wrapping a zig allocator alloc function into a callback callable from C code.
/// Bzip2 will call this whenever it wants memory.
/// The associated dealloc function is a no-op, because we can't know the size of the data we should be freeing.
/// Due to this, we are wrapping the user's allocator in an `ArenaAllocator` and freeing everything at once at the end of compression/decompression.
pub fn alloc(any: ?*anyopaque, items: i32, size: i32) callconv(.c) ?*anyopaque {
    if (any == null) {
        @panic("Tried to allocate with a null allocator.");
    }
    const allocator: *std.mem.Allocator = @ptrCast(@alignCast(any.?));
    std.debug.assert(items > 0);
    std.debug.assert(size > 0);
    std.debug.assert(items * size < 1_000_000_000); // 1GB max size. normally we use much much smaller buffers.
    const mem: []u8 = allocator.alloc(u8, @intCast(items * size)) catch {
        return null;
    };
    return @ptrCast(mem.ptr);
}

/// No-op. See `alloc`.
pub fn dealloc(any: ?*anyopaque, addr: ?*anyopaque) callconv(.c) void {
    _ = any;
    _ = addr;
}
