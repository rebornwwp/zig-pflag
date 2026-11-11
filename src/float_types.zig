//! Float flag types. Maps from pflag/float*.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = @import("value.zig").Value;

const f32Vtable = makeFloatVtable(f32);
const f64Vtable = makeFloatVtable(f64);

fn makeFloatVtable(comptime T: type) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                (@as(*T, @ptrCast(@alignCast(ptr)))).* = try std.fmt.parseFloat(T, v);
            }
        }.set,
        .string = floatStrFn(T),
        .typeName = struct {
            fn tn() []const u8 {
                return @typeName(T);
            }
        }.tn,
        .deinit = struct {
            fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
                _ = ptr;
                _ = gpa;
            }
        }.di,
    };
}
fn floatStrFn(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) anyerror![]const u8 {
    return struct {
        fn str(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
            const p: *T = @ptrCast(@alignCast(ptr));
            return gpa.print("{d}", .{p.*});
        }
    }.str;
}

pub fn floatValue(comptime T: type, val: T, p: *T) Value {
    p.* = val;
    const vt: *const Value.VTable = switch (T) {
        f32 => &f32Vtable,
        f64 => &f64Vtable,
        else => @compileError("Unsupported float type: " ++ @typeName(T)),
    };
    return .{ .ptr = p, .vtable = vt };
}

// ── Tests ──

test "FloatVar" {
    const TestCase = struct {
        input: []const u8,
        expected: f64,
    };

    const testCases = [_]TestCase{
        .{ .input = "3.14", .expected = 3.14 },
        .{ .input = "0x1.0p10", .expected = 1024.0 }, // hex float
        .{ .input = "1.5e2", .expected = 150.0 },
        .{ .input = "-3.14", .expected = -3.14 },
        .{ .input = "+1.5", .expected = 1.5 }, // unary plus
        .{ .input = ".5", .expected = 0.5 }, // leading dot
        .{ .input = "5.", .expected = 5.0 }, // trailing dot
        .{ .input = "1E3", .expected = 1000.0 }, // uppercase exponent
        .{ .input = "1.5e-2", .expected = 0.015 }, // negative exponent
        .{ .input = "1_0.5", .expected = 10.5 }, // underscore grouping
        .{ .input = "0", .expected = 0.0 },
    };

    for (testCases) |tc| {
        var val: f64 = 0.0;
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.floatVar(f64, &val, "rate", 0.0, "the rate");
        const arg = try std.fmt.allocPrint(std.testing.allocator, "--rate={s}", .{tc.input});
        defer std.testing.allocator.free(arg);
        try fs.parse(&.{arg});
        try std.testing.expectApproxEqRel(tc.expected, val, @as(f64, @floatCast(0.001)));
    }
}

test "FloatValue specials and silent saturation" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    var rate: f64 = 0.0;
    try fs.floatVar(f64, &rate, "rate", 0.0, "");

    try fs.set("rate", "inf");
    try std.testing.expect(std.math.isInf(rate) and rate > 0);
    try fs.set("rate", "-Inf");
    try std.testing.expect(std.math.isInf(rate) and rate < 0);
    try fs.set("rate", "infinity");
    try std.testing.expect(rate > 0 and std.math.isInf(rate));
    try fs.set("rate", "-infinity");
    try std.testing.expect(rate < 0 and std.math.isInf(rate));
    try fs.set("rate", "NaN");
    try std.testing.expect(std.math.isNan(rate));
    try fs.set("rate", "nan");
    try std.testing.expect(std.math.isNan(rate));
    // Overflow and underflow do NOT error in Zig — they saturate to inf / 0.
    // (Go's strconv.ParseFloat would surface ErrRange here.)
    try fs.set("rate", "1e400");
    try std.testing.expect(rate > 0 and std.math.isInf(rate));
    try fs.set("rate", "1e-400");
    try std.testing.expectEqual(@as(f64, 0), rate);
}

fn checkFloatStr(comptime T: type, input: []const u8, expected: []const u8) !void {
    var v: T = 0;
    var val = floatValue(T, 0, &v);
    try std.testing.expectEqualStrings(@typeName(T), val.typeName());
    try val.set(input);
    const s = try val.string(std.testing.allocator);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings(expected, s);
}

test "FloatValue widths, typeName and decimal string output" {
    try checkFloatStr(f64, "1.5", "1.5");
    try checkFloatStr(f64, "0.1", "0.1");
    try checkFloatStr(f64, "-0.0015", "-0.0015");
    try checkFloatStr(f64, "5.", "5");
    try checkFloatStr(f64, "1e20", "100000000000000000000");
    try checkFloatStr(f64, "inf", "inf");
    try checkFloatStr(f64, "NaN", "nan");
    try checkFloatStr(f32, "1.5", "1.5");
    try checkFloatStr(f32, "4e38", "inf"); // saturates at f32 range
}

test "FloatVar invalid value returns error" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var rate: f64 = 0.0;
    try fs.floatVar(f64, &rate, "rate", 0.0, "");
    inline for (.{ "xyz", "", "1e", "e5", " 1.5", "1.5 " }) |bad| {
        try std.testing.expectError(error.InvalidCharacter, fs.set("rate", bad));
    }
}
