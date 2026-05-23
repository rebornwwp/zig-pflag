//! String flag type. Maps from pflag/string.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

const stringVtable = Value.VTable{
    .set = stringSetFn,
    .string = stringStrFn,
    .typeName = struct {
        fn tn() []const u8 {
            return "string";
        }
    }.tn,
};
fn stringSetFn(ptr: *anyopaque, v: []const u8) !void {
    (@as(*[]const u8, @ptrCast(@alignCast(ptr)))).* = v;
}
fn stringStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
    return gpa.dupe(u8, (@as(*[]const u8, @ptrCast(@alignCast(ptr)))).*) catch "";
}

pub fn stringValue(val: []const u8, p: *[]const u8) Value {
    p.* = val;
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = &stringVtable };
}
