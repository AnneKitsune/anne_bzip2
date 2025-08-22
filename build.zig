const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // generate zig-compatible bzip2 header
    const header = b.addTranslateC(.{
        .root_source_file = b.path("bzip2/bzlib.h"),
        .target = target,
        .optimize = optimize,
    });
    const header_mod = header.createModule();

    // create main mod file
    const mod = b.addModule("anne_bzip2", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "bzip2", .module = header_mod },
        },
    });
    // ... with the bzip2 implementation integrated to it
    mod.addCSourceFiles(.{
        .files = &.{
            "bzip2/blocksort.c",
            "bzip2/huffman.c",
            "bzip2/crctable.c",
            "bzip2/randtable.c",
            "bzip2/compress.c",
            "bzip2/decompress.c",
            "bzip2/bzlib.c",
        },
        .flags = &.{
            "-Dwall",
            "-Winline",
            "-g",
            "-D_FILE_OFFSET_BITS=64",
            "-DBZ_NO_STDIO",
        },
        .language = .c,
    });

    // Create the static library users can link against
    const lib = b.addLibrary(.{
        .name = "anne_bzip2",
        .root_module = mod,
    });
    lib.step.dependOn(&header.step);

    // unit tests
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    b.installArtifact(lib);
}
