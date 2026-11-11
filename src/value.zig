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

    /// Type-erase a concrete storage pointer plus its operation table —
    /// the whole "interface" in Zig terms. `VTable` mirrors Go's `Value`
    /// interface methods exactly (Set/String/Type + our added Deinit).
    pub const VTable = struct {
        set: *const fn (ptr: *anyopaque, val: []const u8) anyerror!void,
        string: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8,
        typeName: *const fn () []const u8,
        deinit: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator) void,
    };

    /// Assign from raw command-line text; each concrete type defines its own
    /// grammar and propagates its own errors to the parse caller.
    pub fn set(self: Value, val: []const u8) anyerror!void {
        return self.vtable.set(self.ptr, val);
    }
    /// Render the current value as text (allocated from gpa; CALLER frees).
    /// Used for def_value snapshots, usage lines, and getString.
    pub fn string(self: Value, gpa: std.mem.Allocator) anyerror![]const u8 {
        return self.vtable.string(self.ptr, gpa);
    }
    /// Static name tag, compared with std.mem.eql by the typed getters —
    /// must match the spelling the getters expect ("bool", @typeName(T)...).
    pub fn typeName(self: Value) []const u8 {
        return self.vtable.typeName();
    }
    /// Release value-owned memory (dupe'd items, maps, lists). Invoked by
    /// FlagSet.deinit; implementations must only free what the LIBRARY
    /// allocated (see state.changed / state.allocated rules).
    pub fn deinit(self: Value, gpa: std.mem.Allocator) void {
        return self.vtable.deinit(self.ptr, gpa);
    }
};
