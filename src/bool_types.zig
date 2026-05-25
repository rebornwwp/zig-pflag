//! Bool flag type. Maps from pflag/bool.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

const boolVtable = Value.VTable{
    .set = boolSetFn,
    .string = boolStrFn,
    .typeName = boolTypeNameFn,
    .deinit = boolDeinitFn,
};
fn boolSetFn(ptr: *anyopaque, v: []const u8) !void {
    const p: *bool = @ptrCast(@alignCast(ptr));
    p.* = try parseBool(v);
}

/// Go-compatible bool parsing: accepts true/false, TRUE/FALSE, True/False,
/// T/F, t/f, 1/0, and empty string (treated as true).
pub fn parseBool(v: []const u8) !bool {
    if (v.len == 0) return true;
    if (equalsIgnoreCase(v, "true") or equalsIgnoreCase(v, "t") or std.mem.eql(u8, v, "1")) return true;
    if (equalsIgnoreCase(v, "false") or equalsIgnoreCase(v, "f") or std.mem.eql(u8, v, "0")) return false;
    return error.InvalidBoolValue;
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (toLower(ca) != toLower(cb)) return false;
    }
    return true;
}

fn toLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn boolStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
    const val = (@as(*bool, @ptrCast(@alignCast(ptr)))).*;
    return gpa.dupe(u8, if (val) "true" else "false");
}
fn boolTypeNameFn() []const u8 {
    return "bool";
}
fn boolDeinitFn(ptr: *anyopaque, gpa: std.mem.Allocator) void {
    _ = ptr;
    _ = gpa;
}

pub fn boolValue(val: bool, p: *bool) Value {
    p.* = val;
    return .{ .ptr = p, .vtable = &boolVtable };
}
