//! Bool flag type. Maps from pflag/bool.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

const boolVtable = Value.VTable{
    .set = boolSetFn,
    .string = boolStrFn,
    .typeName = boolTypeNameFn,
};
fn boolSetFn(ptr: *anyopaque, v: []const u8) !void {
    const p: *bool = @ptrCast(@alignCast(ptr));
    if (std.mem.eql(u8, v, "true") or std.mem.eql(u8, v, "1") or v.len == 0) {
        p.* = true;
    } else if (std.mem.eql(u8, v, "false") or std.mem.eql(u8, v, "0")) {
        p.* = false;
    } else return error.InvalidBoolValue;
}
fn boolStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
    const val = (@as(*bool, @ptrCast(@alignCast(ptr)))).*;
    return gpa.dupe(u8, if (val) "true" else "false") catch "true";
}
fn boolTypeNameFn() []const u8 {
    return "bool";
}

pub fn boolValue(val: bool, p: *bool) Value {
    p.* = val;
    return .{ .ptr = p, .vtable = &boolVtable };
}
