const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/pflag.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "pflag",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // Tests
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/pflag_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = test_mod });
    tests.root_module.addImport("pflag", lib_mod);

    const run_tests = b.addRunArtifact(tests);
    run_tests.step.dependOn(&lib.step);

    const test_step = b.step("test", "Run pflag tests");
    test_step.dependOn(&run_tests.step);

    // ── Demo executable ──
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("demo/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pflag", .module = lib_mod },
        },
    });
    const demo_exe = b.addExecutable(.{
        .name = "pflag-demo",
        .root_module = demo_mod,
    });
    const install_demo = b.addInstallArtifact(demo_exe, .{});
    b.getInstallStep().dependOn(&install_demo.step);

    const run_demo = b.addRunArtifact(demo_exe);
    run_demo.step.dependOn(&install_demo.step);
    if (b.args) |args| {
        run_demo.addArgs(args);
    }
    const run_demo_step = b.step("run-demo", "Run the zig-pflag demo");
    run_demo_step.dependOn(&run_demo.step);
}
