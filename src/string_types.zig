//! String flag type. Maps from pflag/string.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

/// Wrapper struct to track allocator for string values.
/// Ensures set() duplicates the input so it doesn't dangle.
/// The value pointed to must always be heap-allocated (or empty with allocated=false).
pub const StringState = struct {
    value: *[]const u8,
    gpa: std.mem.Allocator,
    allocated: bool = false,
};

const stringVtable = Value.VTable{
    .set = stringSetFn,
    .string = stringStrFn,
    .typeName = struct {
        fn tn() []const u8 {
            return "string";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            _ = ptr;
            _ = gpa;
        }
    }.di,
};
fn stringSetFn(ptr: *anyopaque, v: []const u8) !void {
    const state: *StringState = @ptrCast(@alignCast(ptr));
    const gpa = state.gpa;
    const duped = try gpa.dupe(u8, v);
    const old = state.value.*;
    const was_allocated = state.allocated;
    state.value.* = duped;
    state.allocated = true;
    if (was_allocated) {
        gpa.free(old);
    }
}
fn stringStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
    const state: *StringState = @ptrCast(@alignCast(ptr));
    return gpa.dupe(u8, state.value.*);
}

pub fn stringValue(val: []const u8, p: *[]const u8) Value {
    // NOTE: caller should use stringStateValue for proper allocator tracking.
    // This legacy form stores the pointer directly (no copy on set).
    p.* = val;
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = &stringVtableLegacy };
}

pub fn stringStateValue(state: *StringState) Value {
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = &stringVtable };
}

const stringVtableLegacy = Value.VTable{
    .set = stringSetFnLegacy,
    .string = stringStrFnLegacy,
    .typeName = struct {
        fn tn() []const u8 {
            return "string";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            _ = ptr;
            _ = gpa;
        }
    }.di,
};
fn stringSetFnLegacy(ptr: *anyopaque, v: []const u8) !void {
    (@as(*[]const u8, @ptrCast(@alignCast(ptr)))).* = v;
}
fn stringStrFnLegacy(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
    return gpa.dupe(u8, (@as(*[]const u8, @ptrCast(@alignCast(ptr)))).*);
}
