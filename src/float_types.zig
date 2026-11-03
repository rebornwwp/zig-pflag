//! Float flag types. Maps from pflag/float*.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

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

test "FloatVar and parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var val: f64 = 0.0;
    try fs.floatVar(f64, &val, "rate", 0.0, "the rate");
    try fs.parse(&.{"--rate=3.14"});
    try std.testing.expectApproxEqRel(3.14, val, @as(f64, @floatCast(0.0001)));
}

test "FloatVar hex value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var val: f64 = 0.0;
    try fs.floatVar(f64, &val, "val", 0.0, "");
    try fs.parse(&.{"--val=0x1.0p10"});
    try std.testing.expectApproxEqRel(1024.0, val, @as(f64, @floatCast(0.001)));
}

test "Invalid float value returns error" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var rate: f64 = 0.0;
    try fs.floatVar(f64, &rate, "rate", 0.0, "");
    const result = fs.parse(&.{"--rate=xyz"});
    try std.std.testing.expectError(error.InvalidCharacter, result);
}

test "Scientific notation float" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var rate: f64 = 0.0;
    try fs.floatVar(f64, &rate, "rate", 0.0, "");
    try fs.parse(&.{"--rate=1.5e2"});
    try std.testing.expectApproxEqAbs(@as(f64, 150.0), rate, 0.01);
}

test "Negative float value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var rate: f64 = 0.0;
    try fs.floatVar(f64, &rate, "rate", 0.0, "");
    try fs.parse(&.{"--rate=-3.14"});
    try std.testing.expectApproxEqAbs(@as(f64, -3.14), rate, 0.01);
}

