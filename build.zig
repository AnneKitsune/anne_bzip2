const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //    const libbz2_mod = b.createModule(.{
    //        .target = target,
    //        .optimize = optimize,
    //        .link_libc = true,
    //    });
    //const libbz2 = b.addLibrary(.{
    //.name = "bz2",
    //.root_module = libbz2_mod,
    //});
    //const libbz2 = b.addObject(.{
    //.name = "bz2",
    //.root_module = libbz2_mod,
    //});
    //b.installArtifact(libbz2);

    const header_mod = b.addTranslateC(.{
        .root_source_file = b.path("bzip2/bzlib.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    //header_mod.linkLibrary(libbz2_mod);

    const mod = b.addModule("anne_bzip2", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
        .imports = &.{
            .{ .name = "bzip2", .module = header_mod },
        },
    });
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
            //"-DBZ_NO_STDIO",
        },
        .language = .c,
    });
    mod.addIncludePath(b.path("bzip2"));
    //mod.linkLibrary(libbz2);
    //mod.addObject(libbz2);

    //const lib = b.addLibrary(.{
    //.name = "anne_bzip2",
    //.root_module = mod,
    //});

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
