//! Uint flag types. Maps from pflag/uint*.go v1.0.9.
//! Uses comptime generics instead of per-type files.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

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

test "UintVar different types" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    var a: u8 = 0;
    var b: u64 = 0;
    try fs.uintVar(u8, &a, "a", 0, "");
    try fs.uintVar(u64, &b, "b", 0, "");
    try fs.parse(&.{ "--a=255", "--b=18446744073709551615" });
    try std.testing.expectEqual(@as(u8, 255), a);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), b);
}

test "UintVar rejects negative values" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var count: u32 = 0;
    try fs.uintVar(u32, &count, "count", 0, "");
    try std.testing.expectError(error.Overflow, fs.parse(&.{"--count=-1"}));
}
