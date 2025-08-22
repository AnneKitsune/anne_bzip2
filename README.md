# Zig Bzip2
This is wrapper around the C bzip2 implementation, making it easier to use from zig.

## Usage
Call these two functions:
```zig
fn compress(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, options: Bzip2StreamCompressor.Options) !usize;
fn decompress(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, options: Bzip2StreamDecompressor.Options) !usize;
```

They will take data from the reader and write it to the writer after compressing/decompressing.

For a more advanced usage (I'm not sure that would be ever required), see `src/compressor.zig` and `src/decompressor.zig` code documentation.
