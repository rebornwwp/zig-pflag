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
fn uintStrFn(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) []const u8 {
    return struct {
        fn str(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
            const p: *T = @ptrCast(@alignCast(ptr));
            return std.fmt.allocPrint(gpa, "{d}", .{p.*}) catch "?";
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
