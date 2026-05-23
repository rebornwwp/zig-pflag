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
fn floatStrFn(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) []const u8 {
    return struct {
        fn str(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
            const p: *T = @ptrCast(@alignCast(ptr));
            return std.fmt.allocPrint(gpa, "{d}", .{p.*}) catch "?";
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
