const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("pflag", .{
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
        .root_source_file = b.path("examples/demo.zig"),
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

    // ── Struct config example ──
    const struct_mod = b.createModule(.{
        .root_source_file = b.path("examples/struct_config.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pflag", .module = lib_mod },
        },
    });
    const struct_exe = b.addExecutable(.{
        .name = "example-struct_config",
        .root_module = struct_mod,
    });
    const install_struct = b.addInstallArtifact(struct_exe, .{});
    b.getInstallStep().dependOn(&install_struct.step);

    const run_struct = b.addRunArtifact(struct_exe);
    run_struct.step.dependOn(&install_struct.step);
    if (b.args) |args| {
        run_struct.addArgs(args);
    }
    const run_struct_step = b.step("run-struct-config", "Run the struct config example");
    run_struct_step.dependOn(&run_struct.step);

    // ── Allocator examples (N types × M allocators) ──
    const example_names = [_][]const u8{
        "int_gpa",         "int_arena",         "int_page",         "int_fba",
        "string_gpa",      "string_arena",      "string_page",      "string_fba",
        "float_slice_gpa", "float_slice_arena", "float_slice_page", "float_slice_fba",
        "struct_config",
    };

    const build_examples_step = b.step("build-examples", "Build all allocator examples (3 types × 4 allocators = 12 exes)");

    for (example_names) |name| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pflag", .module = lib_mod },
            },
        });
        const exe = b.addExecutable(.{
            .name = b.fmt("example-{s}", .{name}),
            .root_module = exe_mod,
        });
        const install_exe = b.addInstallArtifact(exe, .{});
        build_examples_step.dependOn(&install_exe.step);
    }
}
