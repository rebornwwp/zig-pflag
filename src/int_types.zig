//! Int flag types. Maps from pflag/int*.go v1.0.9.
//! Uses comptime generics instead of per-type files.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

const i8Vtable = makeIntVtable(i8);
const i16Vtable = makeIntVtable(i16);
const i32Vtable = makeIntVtable(i32);
const i64Vtable = makeIntVtable(i64);

fn makeIntVtable(comptime T: type) Value.VTable {
    return .{
        .set = intSetFn(T),
        .string = intStrFn(T),
        .typeName = intTypeNameFn(T),
        .deinit = intDeinitFn(T),
    };
}
fn intSetFn(comptime T: type) *const fn (*anyopaque, []const u8) anyerror!void {
    return struct {
        fn set(ptr: *anyopaque, v: []const u8) anyerror!void {
            const p: *T = @ptrCast(@alignCast(ptr));
            p.* = try std.fmt.parseInt(T, v, 0);
        }
    }.set;
}
fn intStrFn(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) anyerror![]const u8 {
    return struct {
        fn str(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
            const p: *T = @ptrCast(@alignCast(ptr));
            return gpa.print("{d}", .{p.*});
        }
    }.str;
}
fn intTypeNameFn(comptime T: type) *const fn () []const u8 {
    return struct {
        fn tn() []const u8 {
            return @typeName(T);
        }
    }.tn;
}
fn intDeinitFn(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) void {
    _ = T;
    return struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            _ = ptr;
            _ = gpa;
        }
    }.di;
}

pub fn intValue(comptime T: type, val: T, p: *T) Value {
    p.* = val;
    const vt: *const Value.VTable = switch (T) {
        i8 => &i8Vtable,
        i16 => &i16Vtable,
        i32 => &i32Vtable,
        i64 => &i64Vtable,
        else => @compileError("Unsupported int type: " ++ @typeName(T)),
    };
    return .{ .ptr = p, .vtable = vt };
}

// ── Tests ──

test "IntVar" {
    const TestCase = struct {
        input: []const []const u8,
        expected: i32,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{"--count=42"}, .expected = 42 },
        .{ .input = &.{ "--count", "99" }, .expected = 99 },
        .{ .input = &.{"--count=0"}, .expected = 0 },
        .{ .input = &.{"--count=-42"}, .expected = -42 },
    };

    for (testCases) |tc| {
        var count: i32 = 0;
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.intVar(i32, &count, "count", 0, "the count");
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected, count);
    }
}

test "IntVar different types" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    var a: i8 = 0;
    var b: i64 = 0;
    try fs.intVar(i8, &a, "a", 0, "");
    try fs.intVar(i64, &b, "b", 0, "");
    try fs.parse(&.{ "--a=127", "--b=9223372036854775807" });
    try std.testing.expectEqual(@as(i8, 127), a);
    try std.testing.expectEqual(@as(i64, 9223372036854775807), b);
}

test "IntVar invalid value returns error" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var count: i32 = 0;
    try fs.intVar(i32, &count, "count", 0, "");
    try std.testing.expectError(error.InvalidCharacter, fs.parse(&.{"--count=abc"}));
}

test "IntVar overflow returns error" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var count: i8 = 0;
    try fs.intVar(i8, &count, "count", 0, "");
    try std.testing.expectError(error.Overflow, fs.parse(&.{"--count=999"}));
}
