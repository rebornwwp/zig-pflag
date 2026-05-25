//! Count flag type. Maps from pflag/count.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

const countVtable = Value.VTable{
    .set = countSetFn,
    .string = countStrFn,
    .typeName = struct {
        fn tn() []const u8 {
            return "count";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            _ = ptr;
            _ = gpa;
        }
    }.di,
};
fn countSetFn(ptr: *anyopaque, v: []const u8) !void {
    const p: *i32 = @ptrCast(@alignCast(ptr));
    // "+1" means no specific value was passed (shorthand without value), so increment
    if (std.mem.eql(u8, v, "+1")) {
        p.* += 1;
        return;
    }
    // Otherwise, parse and assign the value
    const n = try std.fmt.parseInt(i32, v, 0);
    p.* = n;
}
fn countStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
    const p: *i32 = @ptrCast(@alignCast(ptr));
    return std.fmt.allocPrint(gpa, "{d}", .{p.*});
}

pub fn countValue(val: i32, p: *i32) Value {
    p.* = val;
    return .{ .ptr = p, .vtable = &countVtable };
}
