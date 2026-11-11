//! Int flag types. Maps from pflag/int*.go v1.0.9.
//! Uses comptime generics instead of per-type files.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = @import("value.zig").Value;

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

/// Binds `*T` (i8..i64) as a Value with radix-0 integer parsing.
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
        .{ .input = &.{ "--count", "-7" }, .expected = -7 },
        .{ .input = &.{"--count=+42"}, .expected = 42 }, // unary plus
        .{ .input = &.{"--count=0x2a"}, .expected = 42 }, // hex
        .{ .input = &.{"--count=0X2A"}, .expected = 42 }, // uppercase hex prefix
        .{ .input = &.{"--count=0o52"}, .expected = 42 }, // octal
        .{ .input = &.{"--count=0b101010"}, .expected = 42 }, // binary
        .{ .input = &.{"--count=-0x2a"}, .expected = -42 }, // negative hex
        .{ .input = &.{"--count=1_000"}, .expected = 1000 }, // underscore grouping
        .{ .input = &.{"--count=010"}, .expected = 10 }, // Zig radix-0: leading 0 is DECIMAL (Go would read octal 8)
        .{ .input = &.{ "-c", "16" }, .expected = 16 },
        .{ .input = &.{"-c=32"}, .expected = 32 },
        .{ .input = &.{"-c64"}, .expected = 64 }, // glued shorthand value
    };

    for (testCases) |tc| {
        var count: i32 = 0;
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.intVarP(i32, &count, "count", "c", 0, "the count");
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected, count);
    }
}

fn checkIntWidth(comptime T: type) !void {
    var v: T = 0;
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.intVar(T, &v, "n", 0, "");

    const max_s = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{@as(i128, std.math.maxInt(T))});
    defer std.testing.allocator.free(max_s);
    const min_s = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{@as(i128, std.math.minInt(T))});
    defer std.testing.allocator.free(min_s);
    const over_s = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{@as(i128, std.math.maxInt(T)) + 1});
    defer std.testing.allocator.free(over_s);
    const under_s = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{@as(i128, std.math.minInt(T)) - 1});
    defer std.testing.allocator.free(under_s);

    try fs.set("n", max_s);
    try std.testing.expectEqual(std.math.maxInt(T), v);
    try fs.set("n", min_s);
    try std.testing.expectEqual(std.math.minInt(T), v);
    try fs.set("n", "0");
    try std.testing.expectEqual(@as(T, 0), v);
    try std.testing.expectError(error.Overflow, fs.set("n", over_s));
    try std.testing.expectError(error.Overflow, fs.set("n", under_s));
}

test "IntVar widths cover full signed range" {
    try checkIntWidth(i8);
    try checkIntWidth(i16);
    try checkIntWidth(i32);
    try checkIntWidth(i64);
}

fn checkIntInvalid(comptime T: type) !void {
    var v: T = 0;
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.intVar(T, &v, "n", 0, "");
    // All verified against std.fmt.parseInt radix-0 in Zig 0.17 ("" is
    // InvalidCharacter here, NOT MissingDigits like Go would surface).
    const bad = [_][]const u8{ "abc", "", "1x", "0x", " 1", "1 " };
    for (bad) |s| {
        try std.testing.expectError(error.InvalidCharacter, fs.set("n", s));
    }
}

test "IntVar invalid forms across widths" {
    try checkIntInvalid(i8);
    try checkIntInvalid(i16);
    try checkIntInvalid(i32);
    try checkIntInvalid(i64);
}

fn checkIntStr(comptime T: type, input: []const u8, expected: []const u8) !void {
    var v: T = 0;
    var val = intValue(T, 0, &v);
    try std.testing.expectEqualStrings(@typeName(T), val.typeName());
    try val.set(input);
    const s = try val.string(std.testing.allocator);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings(expected, s);
}

test "IntValue string output normalizes to decimal" {
    try checkIntStr(i8, "-128", "-128");
    try checkIntStr(i8, "+42", "42");
    try checkIntStr(i16, "-32768", "-32768");
    try checkIntStr(i16, "010", "10");
    try checkIntStr(i32, "0x10", "16");
    try checkIntStr(i32, "0b1111", "15");
    try checkIntStr(i64, "-9223372036854775808", "-9223372036854775808");
    try checkIntStr(i64, "9223372036854775807", "9223372036854775807");
    try checkIntStr(i64, "1_000", "1000");
}
