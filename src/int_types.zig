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
fn intStrFn(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) []const u8 {
    return struct {
        fn str(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
            const p: *T = @ptrCast(@alignCast(ptr));
            return std.fmt.allocPrint(gpa, "{d}", .{p.*}) catch "?";
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
