const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

//    const obj_blocksort = b.addObject(.{
//        .name = "blocksort",
//        .root_module
//    });
    const libbz2_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const libbz2 = b.addLibrary(.{
        .name = "bz2",
        .root_module = libbz2_mod,
    });
    libbz2.addCSourceFiles(.{
        .files = &.{
            "blocksort.c",
            "huffman.c",
            "crctable.c",
            "randtable.c",
            "compress.c",
            "decompress.c",
            "bzlib.c",
        },
        .flags = &.{
            "-Dwall",
            "-Winline",
            //"-O2",
            "-g",
            "-D_FILE_OFFSET_BITS=64",
        },
    });
    libbz2.installHeadersDirectory(b.path("."), "bzip2", .{
        .exclude_extensions = &.{ ".c" },
    });

    b.installArtifact(libbz2);


    const mod = b.addModule("anne_bzip2", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
    });
    mod.linkLibrary(libbz2);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    const lib = b.addLibrary(.{
        .name = "anne_bzip2",
        .root_module = mod,
    });
    lib.linkLibrary(libbz2);
}

