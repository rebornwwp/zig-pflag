//! Map flag types. Maps from pflag/string_to_*.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

// ─── String → Int (comptime-generic: i8-i64, u8-u64) ───

/// Wrapper struct to track changed state for StringToInt map values.
/// First Set replaces defaults; subsequent Sets merge.
pub fn StringToIntState(comptime T: type) type {
    return struct {
        value: *std.StringHashMapUnmanaged(T),
        gpa: std.mem.Allocator,
        changed: bool = false,
    };
}

fn strToIntVtableGen(comptime T: type) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                const State = StringToIntState(T);
                const state: *State = @ptrCast(@alignCast(ptr));
                const map = state.value;
                const gpa = state.gpa;
                var it = std.mem.splitScalar(u8, v, ',');
                while (it.next()) |pair| {
                    const trimmed = std.mem.trim(u8, pair, " \t");
                    if (trimmed.len == 0) continue;
                    const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse return error.ExpectedKeyValue;
                    const key = try gpa.dupe(u8, trimmed[0..eq]);
                    errdefer gpa.free(key);
                    const val_str = trimmed[eq + 1 ..];
                    const val = try std.fmt.parseInt(T, val_str, 0);
                    if (!state.changed) {
                        // First Set: defaults may have literal (non-owned) keys,
                        // so do NOT free them — just clear the backing storage.
                        map.clearRetainingCapacity();
                        state.changed = true;
                    }
                    // If key already in map (duped), replace value in place so we
                    // don't leak the new duped key (put doesn't overwrite the key pointer).
                    if (map.getEntry(key)) |entry| {
                        entry.value_ptr.* = val;
                        gpa.free(key);
                    } else {
                        try map.put(gpa, key, val);
                    }
                }
                if (!state.changed) state.changed = true;
            }
        }.set,
        .string = struct {
            fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
                const State = StringToIntState(T);
                const state: *State = @ptrCast(@alignCast(ptr));
                const map = state.value;
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                var it = map.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) try buf.appendSlice(gpa, ", ");
                    first = false;
                    var tmp: [64]u8 = undefined;
                    try buf.appendSlice(gpa, entry.key_ptr.*);
                    try buf.appendSlice(gpa, "=");
                    try buf.appendSlice(gpa, std.fmt.bufPrint(&tmp, "{d}", .{entry.value_ptr.*}) catch unreachable);
                }
                return try buf.toOwnedSlice(gpa);
            }
        }.string,
        .typeName = struct {
            fn tn() []const u8 {
                return "stringTo" ++ @typeName(T);
            }
        }.tn,
        .deinit = struct {
            fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
                const State = StringToIntState(T);
                const state: *State = @ptrCast(@alignCast(ptr));
                if (state.changed) {
                    var it = state.value.iterator();
                    while (it.next()) |entry| gpa.free(entry.key_ptr.*);
                }
                state.value.deinit(gpa);
            }
        }.di,
    };
}

const strToI32Vtable = strToIntVtableGen(i32);
const strToI64Vtable = strToIntVtableGen(i64);
const strToU32Vtable = strToIntVtableGen(u32);
const strToU64Vtable = strToIntVtableGen(u64);

pub fn stringToIntValue(comptime T: type, state: *StringToIntState(T)) Value {
    const vt: *const Value.VTable = switch (T) {
        i32 => &strToI32Vtable,
        i64 => &strToI64Vtable,
        u32 => &strToU32Vtable,
        u64 => &strToU64Vtable,
        else => @compileError("Unsupported stringToInt type: " ++ @typeName(T)),
    };
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = vt };
}

// ─── String → String ───

/// Wrapper struct to track changed state for StringToString map values.
/// First Set replaces defaults; subsequent Sets merge.
pub const StringToStringState = struct {
    value: *std.StringHashMapUnmanaged([]const u8),
    gpa: std.mem.Allocator,
    changed: bool = false,
};

const strToStrVtable = Value.VTable{
    .set = struct {
        fn set(ptr: *anyopaque, v: []const u8) !void {
            const state: *StringToStringState = @ptrCast(@alignCast(ptr));
            const map = state.value;
            const gpa = state.gpa;
            // Support comma-separated key=value pairs: "a=1,b=2"
            var it = std.mem.splitScalar(u8, v, ',');
            while (it.next()) |pair| {
                const trimmed = std.mem.trim(u8, pair, " \t");
                if (trimmed.len == 0) continue;
                const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse return error.ExpectedKeyValue;
                const key = try gpa.dupe(u8, trimmed[0..eq]);
                const val = try gpa.dupe(u8, trimmed[eq + 1 ..]);
                if (!state.changed) {
                    // First Set: defaults may have literal (non-owned) keys/values,
                    // so do NOT free them — just clear the backing storage.
                    map.clearRetainingCapacity();
                    state.changed = true;
                }
                // If key already exists, free old value
                if (map.getEntry(key)) |entry| {
                    gpa.free(entry.value_ptr.*);
                    entry.value_ptr.* = val;
                    gpa.free(key); // key already in map, free duplicate
                } else {
                    try map.put(gpa, key, val);
                }
            }
            if (!state.changed) state.changed = true;
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
            const state: *StringToStringState = @ptrCast(@alignCast(ptr));
            const map = state.value;
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            var it = map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try buf.appendSlice(gpa, ", ");
                first = false;
                try buf.appendSlice(gpa, entry.key_ptr.*);
                try buf.appendSlice(gpa, "=");
                try buf.appendSlice(gpa, entry.value_ptr.*);
            }
            return try buf.toOwnedSlice(gpa);
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "stringToString";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            const state: *StringToStringState = @ptrCast(@alignCast(ptr));
            if (state.changed) {
                var it = state.value.iterator();
                while (it.next()) |entry| {
                    gpa.free(entry.key_ptr.*);
                    gpa.free(entry.value_ptr.*);
                }
            }
            state.value.deinit(gpa);
        }
    }.di,
};

pub fn stringToStringValue(state: *StringToStringState) Value {
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = &strToStrVtable };
}
