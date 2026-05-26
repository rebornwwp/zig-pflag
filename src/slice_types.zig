//! Slice flag types. Maps from pflag/*_slice.go, string_array.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const bool_types = @import("bool_types.zig");
const Value = pflag.Value;

// ─── Generic Slice State ───

/// Wrapper struct to track allocator for slice values.
/// Used by int/uint/float/bool slice types.
pub fn SliceState(comptime T: type) type {
    return struct {
        value: *std.ArrayListUnmanaged(T),
        gpa: std.mem.Allocator,
    };
}

// ─── String Slice ───

/// Wrapper struct to track changed state for string slice values.
/// First Set replaces defaults; subsequent Sets append.
///
/// changed flag: tracks whether set() has been called at least once.
/// Before the first Set, the slice contains user-provided defaults whose
/// string pointers may be string literals (non-heap) — the library must NOT
/// free them. After the first Set, all entries are created by the library
/// via gpa.dupe(), so deinit() conditionally frees each string only when
/// changed == true. The container (ArrayListUnmanaged backing array) is
/// always freed via state.value.deinit(gpa).
pub const StringSliceState = struct {
    value: *std.ArrayListUnmanaged([]const u8),
    gpa: std.mem.Allocator,
    changed: bool = false,
};

const stringSliceVtable = Value.VTable{
    .set = struct {
        fn set(ptr: *anyopaque, v: []const u8) !void {
            const state: *StringSliceState = @ptrCast(@alignCast(ptr));
            const slice = state.value;
            const gpa = state.gpa;
            if (!state.changed) {
                slice.clearRetainingCapacity();
            }
            const items_before = slice.items.len;
            errdefer {
                // Free items appended during this call on error
                for (slice.items[items_before..]) |item| gpa.free(item);
                slice.shrinkRetainingCapacity(items_before);
            }
            var it = std.mem.splitScalar(u8, v, ',');
            while (it.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " \t");
                const item = try gpa.dupe(u8, trimmed);
                // Catch: dupe succeeded but append may fail — free item to avoid leak
                slice.append(gpa, item) catch |err| {
                    gpa.free(item);
                    return err;
                };
            }
            if (!state.changed) state.changed = true;
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
            const state: *StringSliceState = @ptrCast(@alignCast(ptr));
            const slice = state.value;
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            for (slice.items, 0..) |s, i| {
                if (i > 0) try buf.appendSlice(gpa, ",");
                try buf.appendSlice(gpa, s);
            }
            return try buf.toOwnedSlice(gpa);
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "stringSlice";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            const state: *StringSliceState = @ptrCast(@alignCast(ptr));
            if (state.changed) {
                for (state.value.items) |s| gpa.free(s);
            }
            state.value.deinit(gpa);
        }
    }.di,
};

pub fn stringSliceValue(state: *StringSliceState) Value {
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = &stringSliceVtable };
}

// ─── String Array ───

/// Type alias for string array values.
/// StringArray reuses StringSliceState; only the VTable set() differs
/// (append-only vs CSV-replace semantics).
pub const StringArrayState = StringSliceState;

const stringArrayVtable = Value.VTable{
    .set = struct {
        fn set(ptr: *anyopaque, v: []const u8) !void {
            const state: *StringSliceState = @ptrCast(@alignCast(ptr));
            const slice = state.value;
            const gpa = state.gpa;
            if (!state.changed) {
                slice.clearRetainingCapacity();
            }
            try slice.append(gpa, try gpa.dupe(u8, v));
            state.changed = true;
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
            const state: *StringSliceState = @ptrCast(@alignCast(ptr));
            const slice = state.value;
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            for (slice.items, 0..) |s, i| {
                if (i > 0) try buf.appendSlice(gpa, ",");
                try buf.appendSlice(gpa, s);
            }
            return try buf.toOwnedSlice(gpa);
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "stringArray";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            const state: *StringSliceState = @ptrCast(@alignCast(ptr));
            if (state.changed) {
                for (state.value.items) |s| gpa.free(s);
            }
            state.value.deinit(gpa);
        }
    }.di,
};

pub fn stringArrayValue(state: *StringSliceState) Value {
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = &stringArrayVtable };
}

// ─── Int Slice ───

fn intSliceVtable(comptime T: type) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                try state.value.append(state.gpa, try std.fmt.parseInt(T, v, 0));
            }
        }.set,
        .string = struct {
            fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                const slice = state.value;
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                for (slice.items, 0..) |v, i| {
                    if (i > 0) try buf.appendSlice(gpa, ", ");
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch unreachable;
                    try buf.appendSlice(gpa, s);
                }
                return try buf.toOwnedSlice(gpa);
            }
        }.string,
        .typeName = struct {
            fn tn() []const u8 {
                return @typeName(T) ++ "s";
            }
        }.tn,
        .deinit = struct {
            fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                state.value.deinit(gpa);
            }
        }.di,
    };
}
const i32SliceVtable = intSliceVtable(i32);
const i64SliceVtable = intSliceVtable(i64);

pub fn intSliceValue(comptime T: type, state: *SliceState(T)) Value {
    const vt: *const Value.VTable = switch (T) {
        i32 => &i32SliceVtable,
        i64 => &i64SliceVtable,
        else => @compileError("Unsupported int slice type: " ++ @typeName(T)),
    };
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = vt };
}

// ─── Uint Slice ───

fn uintSliceVtable(comptime T: type) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                try state.value.append(state.gpa, try std.fmt.parseInt(T, v, 0));
            }
        }.set,
        .string = struct {
            fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                const slice = state.value;
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                for (slice.items, 0..) |v, i| {
                    if (i > 0) try buf.appendSlice(gpa, ", ");
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch unreachable;
                    try buf.appendSlice(gpa, s);
                }
                return try buf.toOwnedSlice(gpa);
            }
        }.string,
        .typeName = struct {
            fn tn() []const u8 {
                return @typeName(T) ++ "s";
            }
        }.tn,
        .deinit = struct {
            fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                state.value.deinit(gpa);
            }
        }.di,
    };
}
const u8SliceVtable = uintSliceVtable(u8);
const u16SliceVtable = uintSliceVtable(u16);
const u32SliceVtable = uintSliceVtable(u32);
const u64SliceVtable = uintSliceVtable(u64);

pub fn uintSliceValue(comptime T: type, state: *SliceState(T)) Value {
    const vt: *const Value.VTable = switch (T) {
        u8 => &u8SliceVtable,
        u16 => &u16SliceVtable,
        u32 => &u32SliceVtable,
        u64 => &u64SliceVtable,
        else => @compileError("Unsupported uint slice type: " ++ @typeName(T)),
    };
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = vt };
}

// ─── Bool Slice ───

const boolSliceVtable = Value.VTable{
    .set = struct {
        fn set(ptr: *anyopaque, v: []const u8) !void {
            const state: *SliceState(bool) = @ptrCast(@alignCast(ptr));
            const b = try bool_types.parseBool(v);
            try state.value.append(state.gpa, b);
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
            const state: *SliceState(bool) = @ptrCast(@alignCast(ptr));
            const slice = state.value;
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            for (slice.items, 0..) |v, i| {
                if (i > 0) try buf.appendSlice(gpa, ", ");
                try buf.appendSlice(gpa, if (v) "true" else "false");
            }
            return try buf.toOwnedSlice(gpa);
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "bools";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            const state: *SliceState(bool) = @ptrCast(@alignCast(ptr));
            state.value.deinit(gpa);
        }
    }.di,
};

pub fn boolSliceValue(state: *SliceState(bool)) Value {
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = &boolSliceVtable };
}

// ─── Float Slice ───

fn floatSliceVtable(comptime T: type) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                try state.value.append(state.gpa, try std.fmt.parseFloat(T, v));
            }
        }.set,
        .string = struct {
            fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                const slice = state.value;
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                for (slice.items, 0..) |v, i| {
                    if (i > 0) try buf.appendSlice(gpa, ", ");
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch unreachable;
                    try buf.appendSlice(gpa, s);
                }
                return try buf.toOwnedSlice(gpa);
            }
        }.string,
        .typeName = struct {
            fn tn() []const u8 {
                return @typeName(T) ++ "s";
            }
        }.tn,
        .deinit = struct {
            fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                state.value.deinit(gpa);
            }
        }.di,
    };
}
const f32SliceVtable = floatSliceVtable(f32);
const f64SliceVtable = floatSliceVtable(f64);

pub fn floatSliceValue(comptime T: type, state: *SliceState(T)) Value {
    const vt: *const Value.VTable = switch (T) {
        f32 => &f32SliceVtable,
        f64 => &f64SliceVtable,
        else => @compileError("Unsupported float slice type: " ++ @typeName(T)),
    };
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = vt };
}
