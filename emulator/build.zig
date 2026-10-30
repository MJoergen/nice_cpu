const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const window = b.option(bool, "window", "Build the window of --window, with SDL from source") orelse false;

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const options = b.addOptions();
    options.addOption(bool, "window", window);
    mod.addOptions("build_options", options);

    // SDL is a lazy dependency: the default build fetches nothing. Zig has
    // no @cImport, so a translate-c step reads the header.
    if (window) {
        if (b.lazyDependency("sdl", .{ .target = target, .optimize = optimize })) |sdl_dep| {
            const tc = b.addTranslateC(.{ .root_source_file = b.path("src/sdl.h"), .target = target, .optimize = optimize });
            tc.addIncludePath(sdl_dep.path("include"));
            mod.addImport("sdl", tc.createModule());
            mod.linkLibrary(sdl_dep.artifact("SDL3"));
        }
    }

    const exe = b.addExecutable(.{ .name = "niceemu", .root_module = mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPassthruArgs();
    b.step("run", "Run the emulator").dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Run the unit tests").dependOn(&b.addRunArtifact(tests).step);
}
