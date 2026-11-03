//! Map flag types. Maps from pflag/string_to_*.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

// ─── String → Int (comptime-generic: i8-i64, u8-u64) ───

/// Wrapper struct to track changed state for StringToInt map values.
/// First Set replaces defaults; subsequent Sets merge.
///
/// changed flag: tracks whether set() has been called at least once.
/// Before the first Set, the map contains user-provided defaults whose
/// key pointers may be string literals (non-heap) — the library must NOT
/// free them. After the first Set, all entries are created by the library
/// via gpa.dupe(), so deinit() conditionally frees keys only when
/// changed == true.
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
                    }
                    // If key already in map (duped), replace value in place so we
                    // don't leak the new duped key (put doesn't overwrite the key pointer).
                    if (map.getEntry(key)) |entry| {
                        entry.value_ptr.* = val;
                        gpa.free(key);
                    } else {
                        try map.put(gpa, key, val);
                    }
                    if (!state.changed) state.changed = true;
                }
                // changed flag also covers the empty-input case
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
///
/// changed flag: tracks whether set() has been called at least once.
/// Before the first Set, the map contains user-provided defaults whose
/// key/value pointers may be string literals (non-heap) — the library must
/// NOT free them. After the first Set, all entries are created by the library
/// via gpa.dupe(), so deinit() conditionally frees both keys and values only
/// when changed == true.
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
                errdefer gpa.free(key);
                const val = try gpa.dupe(u8, trimmed[eq + 1 ..]);
                if (!state.changed) {
                    // First Set: defaults may have literal (non-owned) keys/values,
                    // so do NOT free them — just clear the backing storage.
                    map.clearRetainingCapacity();
                }
                // If key already exists, free old value
                if (map.getEntry(key)) |entry| {
                    gpa.free(entry.value_ptr.*);
                    entry.value_ptr.* = val;
                    gpa.free(key); // key already in map, free duplicate
                } else {
                    try map.put(gpa, key, val);
                }
                if (!state.changed) state.changed = true;
            }
            // changed flag also covers the empty-input case
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


// ── Tests ──

test "StringToIntVar maps key=value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i32, &state, "headers", 0, "header map");
    try fs.parse(&.{ "--headers=a=1", "--headers=b=2", "--headers=c=3" });

    try std.std.testing.expectEqual(@as(i32, 1), map.get("a").?);
    try std.std.testing.expectEqual(@as(i32, 2), map.get("b").?);
    try std.std.testing.expectEqual(@as(i32, 3), map.get("c").?);
}

test "StringToIntVar rejects non-key=value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try std.std.testing.expectError(error.ExpectedKeyValue, fs.parse(&.{"--headers=badval"}));
}

test "StringToStringVar maps key=value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToStringVar(&state, "labels", "", "");
    try fs.parse(&.{ "--labels=env=prod", "--labels=region=us-east" });

    try std.std.std.testing.expectEqualStrings("prod", map.get("env").?);
    try std.std.std.testing.expectEqualStrings("us-east", map.get("region").?);
}

test "StringToIntVar supports i64" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i64) = .empty;
    var state = pflag.StringToIntState(i64){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i64, &state, "headers", 0, "header map (i64)");
    try fs.parse(&.{"--headers=x=9223372036854775807"});
    try std.std.testing.expectEqual(@as(i64, 9223372036854775807), map.get("x").?);
}

test "StringToIntVar supports u32" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(u32) = .empty;
    var state = pflag.StringToIntState(u32){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(u32, &state, "ports", 0, "port map");
    try fs.parse(&.{ "--ports=web=80", "--ports=ssl=443" });
    try std.std.testing.expectEqual(@as(u32, 80), map.get("web").?);
    try std.std.testing.expectEqual(@as(u32, 443), map.get("ssl").?);
}

test "StringToIntVar first Set replaces defaults" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    // Pre-populate with defaults
    map.put(std.testing.allocator, "old1", 100) catch {};
    map.put(std.testing.allocator, "old2", 200) catch {};
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try std.std.testing.expectEqual(@as(u32, 2), map.count());
    // First Set should replace defaults
    try fs.parse(&.{"--headers=x=10"});
    try std.std.testing.expectEqual(@as(u32, 1), map.count());
    try std.std.testing.expectEqual(@as(i32, 10), map.get("x").?);
    try std.testing.expect(map.get("old1") == null);
}

test "StringToIntVar supports comma-separated pairs" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try fs.parse(&.{"--headers=a=1,b=2,c=3"});
    try std.std.testing.expectEqual(@as(u32, 3), map.count());
    try std.std.testing.expectEqual(@as(i32, 1), map.get("a").?);
    try std.std.testing.expectEqual(@as(i32, 2), map.get("b").?);
    try std.std.testing.expectEqual(@as(i32, 3), map.get("c").?);
}

test "StringToInt64 empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i64) = .empty;
    var state = pflag.StringToIntState(i64){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i64, &state, "s2i", 0, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(u32, 0), map.count());
}

test "StringToInt64 maps key=value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i64) = .empty;
    var state = pflag.StringToIntState(i64){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i64, &state, "s2i", 0, "");
    try fs.parse(&.{"--s2i=a=1,b=2,d=4,c=3"});
    try std.std.testing.expectEqual(@as(i64, 1), map.get("a").?);
    try std.std.testing.expectEqual(@as(i64, 2), map.get("b").?);
    try std.std.testing.expectEqual(@as(i64, 4), map.get("d").?);
    try std.std.testing.expectEqual(@as(i64, 3), map.get("c").?);
}

test "StringToInt64 default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i64) = .empty;
    map.put(std.testing.allocator, "a", 1) catch {};
    map.put(std.testing.allocator, "b", 2) catch {};
    var state = pflag.StringToIntState(i64){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i64, &state, "s2i", 0, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(i64, 1), map.get("a").?);
    try std.std.testing.expectEqual(@as(i64, 2), map.get("b").?);
}

test "StringToInt64 with default overridden" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i64) = .empty;
    map.put(std.testing.allocator, "a", 1) catch {};
    map.put(std.testing.allocator, "b", 2) catch {};
    var state = pflag.StringToIntState(i64){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i64, &state, "s2i", 0, "");
    try fs.parse(&.{"--s2i=x=10"});
    // First Set replaces defaults
    try std.std.testing.expectEqual(@as(u32, 1), map.count());
    try std.std.testing.expectEqual(@as(i64, 10), map.get("x").?);
    try std.testing.expect(map.get("a") == null);
}

test "StringToInt64 called twice accumulates" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i64) = .empty;
    var state = pflag.StringToIntState(i64){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i64, &state, "s2i", 0, "");
    try fs.parse(&.{ "--s2i=a=1,b=2", "--s2i=c=3" });
    try std.std.testing.expectEqual(@as(u32, 3), map.count());
    try std.std.testing.expectEqual(@as(i64, 1), map.get("a").?);
    try std.std.testing.expectEqual(@as(i64, 2), map.get("b").?);
    try std.std.testing.expectEqual(@as(i64, 3), map.get("c").?);
}

test "StringToString empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToStringVar(&state, "s2s", "", "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(u32, 0), map.count());
}

test "StringToString default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    map.put(std.testing.allocator, "a", "1") catch {};
    map.put(std.testing.allocator, "b", "2") catch {};
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToStringVar(&state, "s2s", "", "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(u32, 2), map.count());
    try std.std.std.testing.expectEqualStrings("1", map.get("a").?);
    try std.std.std.testing.expectEqualStrings("2", map.get("b").?);
}

test "StringToString with default overridden" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    map.put(std.testing.allocator, "a", "1") catch {};
    map.put(std.testing.allocator, "b", "2") catch {};
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToStringVar(&state, "s2s", "", "");
    try fs.parse(&.{"--s2s=a=4"});
    // First Set replaces defaults
    try std.std.testing.expectEqual(@as(u32, 1), map.count());
    try std.std.std.testing.expectEqualStrings("4", map.get("a").?);
    try std.testing.expect(map.get("b") == null);
}

test "StringToString called twice accumulates" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToStringVar(&state, "s2s", "", "");
    try fs.parse(&.{ "--s2s=a=1,b=2", "--s2s=c=3", "--s2s=a=2" });
    try std.std.testing.expectEqual(@as(u32, 3), map.count());
    try std.std.std.testing.expectEqualStrings("2", map.get("a").?); // overwritten by last
    try std.std.std.testing.expectEqualStrings("2", map.get("b").?);
    try std.std.std.testing.expectEqualStrings("3", map.get("c").?);
}

test "StringToString nil default" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToStringVar(&state, "s2s", "", "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(u32, 0), map.count());
}

test "StringToString value with equals sign" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToStringVar(&state, "s2s", "", "");
    try fs.parse(&.{"--s2s=a=1="});
    try std.std.testing.expectEqual(@as(u32, 1), map.count());
    try std.std.std.testing.expectEqualStrings("1=", map.get("a").?);
}

test "StringToInt empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i32, &state, "s2i", 0, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(u32, 0), map.count());
}

test "StringToInt default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    map.put(std.testing.allocator, "a", 1) catch {};
    map.put(std.testing.allocator, "b", 2) catch {};
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i32, &state, "s2i", 0, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(u32, 2), map.count());
    try std.std.testing.expectEqual(@as(i32, 1), map.get("a").?);
    try std.std.testing.expectEqual(@as(i32, 2), map.get("b").?);
}

test "StringToInt with default overridden" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    map.put(std.testing.allocator, "a", 1) catch {};
    map.put(std.testing.allocator, "b", 2) catch {};
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i32, &state, "s2i", 0, "");
    try fs.parse(&.{"--s2i=x=10"});
    try std.std.testing.expectEqual(@as(u32, 1), map.count());
    try std.std.testing.expectEqual(@as(i32, 10), map.get("x").?);
    try std.testing.expect(map.get("a") == null);
}

test "StringToInt called twice accumulates" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToIntVar(i32, &state, "s2i", 0, "");
    try fs.parse(&.{ "--s2i=a=1,b=2", "--s2i=c=3" });
    try std.std.testing.expectEqual(@as(u32, 3), map.count());
    try std.std.testing.expectEqual(@as(i32, 1), map.get("a").?);
    try std.std.testing.expectEqual(@as(i32, 2), map.get("b").?);
    try std.std.testing.expectEqual(@as(i32, 3), map.get("c").?);
}

