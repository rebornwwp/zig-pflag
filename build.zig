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

    // Tests — root is pflag.zig so all *_types.zig test blocks are collected.
    // pflag.zig conditionally imports pflag_test.zig when building tests.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/pflag.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = test_mod });

    const run_tests = b.addRunArtifact(tests);
    run_tests.step.dependOn(&lib.step);

    const test_step = b.step("test", "Run pflag tests");
    test_step.dependOn(&run_tests.step);

    // ── HTML API documentation ──
    // Compiler -femit-docs bundle (index.html + wasm viewer + sources.tar)
    // rooted at src/pflag.zig, which reaches every module via file imports.
    // Opt-in step so `zig build` and CI stay lean. Relative paths rely on the
    // Run step inheriting the invocation CWD (the repo root).
    const docs_run = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build-lib",
        "-fno-emit-bin",
        "-femit-docs=zig-out/docs",
        "src/pflag.zig",
    });
    const docs_step = b.step("docs", "Generate HTML API documentation into zig-out/docs");
    docs_step.dependOn(&docs_run.step);

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
    run_demo.addPassthruArgs();
    const run_demo_step = b.step("run-demo", "Run the zig-pflag demo");
    run_demo_step.dependOn(&run_demo.step);

    // ── Standalone examples ──
    const standalone_examples = [_][]const u8{
        "struct_config",
        "shorthand_lookup",
        "string_to_string",
        "interspersed",
    };

    for (standalone_examples) |name| {
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
        b.getInstallStep().dependOn(&install_exe.step);

        const run_exe = b.addRunArtifact(exe);
        run_exe.step.dependOn(&install_exe.step);
        run_exe.addPassthruArgs();
        const run_step = b.step(b.fmt("run-{s}", .{name}), b.fmt("Run the {s} example", .{name}));
        run_step.dependOn(&run_exe.step);
    }

    // ── Allocator examples (N types × M allocators) ──
    const example_names = [_][]const u8{
        "int_gpa",         "int_arena",         "int_page",         "int_fba",         "int_c_allocator",         "int_smp_allocator",
        "string_gpa",      "string_arena",      "string_page",      "string_fba",      "string_c_allocator",      "string_smp_allocator",
        "float_slice_gpa", "float_slice_arena", "float_slice_page", "float_slice_fba", "float_slice_c_allocator", "float_slice_smp_allocator",
    };

    const build_examples_step = b.step("build-examples", "Build all allocator examples (18 exes)");
    const run_all_examples_step = b.step("run-examples", "Run all allocator examples");

    for (example_names) |name| {
        const needs_libc = std.mem.endsWith(u8, name, "_c_allocator");
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .link_libc = needs_libc,
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

        // Add run step for each example
        const run_exe = b.addRunArtifact(exe);
        run_exe.step.dependOn(&install_exe.step);
        const run_step = b.step(b.fmt("run-{s}", .{name}), b.fmt("Run the {s} example", .{name}));
        run_step.dependOn(&run_exe.step);
        run_all_examples_step.dependOn(&run_exe.step);
    }
}
