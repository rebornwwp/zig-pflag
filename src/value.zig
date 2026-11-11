//! Value interface — the vtable contract every flag type implements.
//! Maps from pflag/value.go v1.0.9.
//!
//! Kept independent of pflag.zig: this module imports nothing from the rest of
//! the library, so `*_types.zig` can depend on the interface alone instead of
//! reaching back through `pflag.Value`. Concrete implementations live in the
//! `*_types.zig` files; `Flag`/`FlagSet` in pflag.zig only ever see `Value`.

const std = @import("std");

pub const Value = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        set: *const fn (ptr: *anyopaque, val: []const u8) anyerror!void,
        string: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8,
        typeName: *const fn () []const u8,
        deinit: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator) void,
    };

    pub fn set(self: Value, val: []const u8) anyerror!void {
        return self.vtable.set(self.ptr, val);
    }
    pub fn string(self: Value, gpa: std.mem.Allocator) anyerror![]const u8 {
        return self.vtable.string(self.ptr, gpa);
    }
    pub fn typeName(self: Value) []const u8 {
        return self.vtable.typeName();
    }
    pub fn deinit(self: Value, gpa: std.mem.Allocator) void {
        return self.vtable.deinit(self.ptr, gpa);
    }
};
