//! Uint flag types. Maps from pflag/uint*.go v1.0.9.
//! Uses comptime generics instead of per-type files.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = @import("value.zig").Value;

const u8Vtable = makeUintVtable(u8);
const u16Vtable = makeUintVtable(u16);
const u32Vtable = makeUintVtable(u32);
const u64Vtable = makeUintVtable(u64);

fn makeUintVtable(comptime T: type) Value.VTable {
    return .{
        .set = uintSetFn(T),
        .string = uintStrFn(T),
        .typeName = uintTypeNameFn(T),
        .deinit = uintDeinitFn(T),
    };
}
fn uintSetFn(comptime T: type) *const fn (*anyopaque, []const u8) anyerror!void {
    return struct {
        fn set(ptr: *anyopaque, v: []const u8) anyerror!void {
            const p: *T = @ptrCast(@alignCast(ptr));
            p.* = try std.fmt.parseInt(T, v, 0);
        }
    }.set;
}
fn uintStrFn(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) anyerror![]const u8 {
    return struct {
        fn str(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
            const p: *T = @ptrCast(@alignCast(ptr));
            return gpa.print("{d}", .{p.*});
        }
    }.str;
}
fn uintTypeNameFn(comptime T: type) *const fn () []const u8 {
    return struct {
        fn tn() []const u8 {
            return @typeName(T);
        }
    }.tn;
}
fn uintDeinitFn(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) void {
    _ = T;
    return struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            _ = ptr;
            _ = gpa;
        }
    }.di;
}

pub fn uintValue(comptime T: type, val: T, p: *T) Value {
    p.* = val;
    const vt: *const Value.VTable = switch (T) {
        u8 => &u8Vtable,
        u16 => &u16Vtable,
        u32 => &u32Vtable,
        u64 => &u64Vtable,
        else => @compileError("Unsupported uint type: " ++ @typeName(T)),
    };
    return .{ .ptr = p, .vtable = vt };
}

// ── Tests ──

test "UintVar" {
    const TestCase = struct {
        flag_name: []const u8,
        shorthand: ?[]const u8 = null,
        input: []const []const u8,
        expected: u32,
    };

    const testCases = [_]TestCase{
        .{ .flag_name = "count", .input = &.{"--count=42"}, .expected = 42 },
        .{ .flag_name = "port", .shorthand = "p", .input = &.{ "-p", "8080" }, .expected = 8080 },
        .{ .flag_name = "count", .input = &.{"--count=0x2a"}, .expected = 42 }, // hex
        .{ .flag_name = "count", .input = &.{"--count=0o52"}, .expected = 42 }, // octal
        .{ .flag_name = "count", .input = &.{"--count=0b101"}, .expected = 5 }, // binary
        .{ .flag_name = "count", .input = &.{"--count=+7"}, .expected = 7 }, // unary plus
        .{ .flag_name = "count", .input = &.{"--count=2_048"}, .expected = 2048 }, // underscores
        .{ .flag_name = "count", .input = &.{"--count=0777"}, .expected = 777 }, // radix-0: leading 0 stays DECIMAL (Go: octal 511)
        .{ .flag_name = "count", .input = &.{"--count=0"}, .expected = 0 },
        .{ .flag_name = "count", .input = &.{"-p=9"}, .shorthand = "p", .expected = 9 },
        .{ .flag_name = "count", .input = &.{"--count=-0"}, .expected = 0 }, // signed zero lands exactly on 0
    };

    for (testCases) |tc| {
        var val: u32 = 0;
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        if (tc.shorthand) |sh| {
            try fs.uintVarP(u32, &val, tc.flag_name, sh, 0, "");
        } else {
            try fs.uintVar(u32, &val, tc.flag_name, 0, "");
        }
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected, val);
    }
}

fn checkUintWidth(comptime T: type) !void {
    var v: T = 0;
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.uintVar(T, &v, "n", 0, "");

    const max_s = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{@as(u128, std.math.maxInt(T))});
    defer std.testing.allocator.free(max_s);
    const over_s = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{@as(u128, std.math.maxInt(T)) + 1});
    defer std.testing.allocator.free(over_s);

    try fs.set("n", "0");
    try std.testing.expectEqual(@as(T, 0), v);
    try fs.set("n", max_s);
    try std.testing.expectEqual(std.math.maxInt(T), v);
    try std.testing.expectError(error.Overflow, fs.set("n", over_s));
    // negative values parse as signed and then fail the width fit check
    try std.testing.expectError(error.Overflow, fs.set("n", "-1"));
    try std.testing.expectError(error.Overflow, fs.set("n", "-9999"));
    inline for (.{ "abc", "", "1x", "0x", " 1" }) |bad| {
        try std.testing.expectError(error.InvalidCharacter, fs.set("n", bad));
    }
}

test "UintVar widths: bounds, overflow, negatives, invalid forms" {
    try checkUintWidth(u8);
    try checkUintWidth(u16);
    try checkUintWidth(u32);
    try checkUintWidth(u64);
}

fn checkUintStr(comptime T: type, input: []const u8, expected: []const u8) !void {
    var v: T = 0;
    var val = uintValue(T, 0, &v);
    try std.testing.expectEqualStrings(@typeName(T), val.typeName());
    try val.set(input);
    const s = try val.string(std.testing.allocator);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings(expected, s);
}

test "UintValue string output normalizes to decimal" {
    try checkUintStr(u8, "255", "255");
    try checkUintStr(u8, "0x10", "16");
    try checkUintStr(u16, "+32768", "32768");
    try checkUintStr(u16, "0777", "777");
    try checkUintStr(u32, "0b10000", "16");
    try checkUintStr(u32, "-0", "0");
    try checkUintStr(u64, "18446744073709551615", "18446744073709551615");
    try checkUintStr(u64, "1_000_000", "1000000");
}
