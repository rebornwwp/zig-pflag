//! Bool flag type. Maps from pflag/bool.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = @import("value.zig").Value;

const boolVtable = Value.VTable{
    .set = boolSetFn,
    .string = boolStrFn,
    .typeName = boolTypeNameFn,
    .deinit = boolDeinitFn,
};
fn boolSetFn(ptr: *anyopaque, v: []const u8) !void {
    const p: *bool = @ptrCast(@alignCast(ptr));
    p.* = try parseBool(v);
}

/// Re-exported from internal.zig so `pflag.bool_types.parseBool` stays valid.
pub const parseBool = @import("internal.zig").parseBool;
fn boolStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
    const val = (@as(*bool, @ptrCast(@alignCast(ptr)))).*;
    return gpa.dupe(u8, if (val) "true" else "false");
}
fn boolTypeNameFn() []const u8 {
    return "bool";
}
fn boolDeinitFn(ptr: *anyopaque, gpa: std.mem.Allocator) void {
    _ = ptr;
    _ = gpa;
}

pub fn boolValue(val: bool, p: *bool) Value {
    p.* = val;
    return .{ .ptr = p, .vtable = &boolVtable };
}

// ── Tests ──

test "BoolVar" {
    const TestCase = struct {
        input: []const []const u8,
        expected: bool,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{"--verbose"}, .expected = true },
        .{ .input = &.{"-v"}, .expected = true },
        .{ .input = &.{"--verbose=true"}, .expected = true },
        .{ .input = &.{"--verbose=false"}, .expected = false },
        .{ .input = &.{"--verbose=1"}, .expected = true },
        .{ .input = &.{"--verbose=0"}, .expected = false },
        .{ .input = &.{"--verbose=TRUE"}, .expected = true },
        .{ .input = &.{"--verbose=FALSE"}, .expected = false },
        .{ .input = &.{"--verbose=True"}, .expected = true },
        .{ .input = &.{"--verbose=False"}, .expected = false },
        .{ .input = &.{"--verbose=t"}, .expected = true },
        .{ .input = &.{"--verbose=f"}, .expected = false },
    };

    for (testCases) |tc| {
        var flag_val: bool = false;
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.boolVarP(&flag_val, "verbose", "v", false, "enable verbose");
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected, flag_val);
    }
}

test "BoolVar invalid value returns error" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var flag_val: bool = false;
    try fs.boolVar(&flag_val, "verbose", false, "");
    try std.testing.expectError(error.InvalidBoolValue, fs.parse(&.{"--verbose=invalid"}));
}

test "BoolP - short flag with extra argument" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    var flag_val: bool = false;
    try fs.boolVarP(&flag_val, "verbose", "v", false, "enable verbose");
    // Short bool flag with extra argument - the "maybe" becomes a positional arg
    try fs.parse(&.{ "-v", "maybe" });
    try std.testing.expect(flag_val);
    try std.testing.expectEqual(@as(usize, 1), fs.nArg());
    try std.testing.expectEqualStrings("maybe", fs.arg(0));
}
