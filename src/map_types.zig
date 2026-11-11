//! Map flag types. Maps from pflag/string_to_*.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const internal = @import("internal.zig");
const Value = @import("value.zig").Value;

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
                    const kv = try internal.splitKeyValue(pair) orelse continue;
                    const key = try gpa.dupe(u8, kv.key);
                    errdefer gpa.free(key);
                    const val = try std.fmt.parseInt(T, kv.val, 0);
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
                    try buf.appendSlice(gpa, entry.key_ptr.*);
                    try buf.appendSlice(gpa, "=");
                    const val_str = try gpa.print("{d}", .{entry.value_ptr.*});
                    defer gpa.free(val_str);
                    try buf.appendSlice(gpa, val_str);
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
                const kv = try internal.splitKeyValue(pair) orelse continue;
                const key = try gpa.dupe(u8, kv.key);
                errdefer gpa.free(key);
                const val = try gpa.dupe(u8, kv.val);
                // val needs its own errdefer: if map.put() below fails,
                // ownership never transfers and val would leak.
                errdefer gpa.free(val);
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

test "StringToInt" {
    const TestCase = struct {
        input: []const []const u8,
        expected_count: u32,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{ "--headers=a=1", "--headers=b=2", "--headers=c=3" }, .expected_count = 3 },
        .{ .input = &.{"--headers=x=9223372036854775807"}, .expected_count = 1 },
    };

    for (testCases) |tc| {
        var map: std.StringHashMapUnmanaged(i64) = .empty;
        var state = pflag.StringToIntState(i64){ .value = &map, .gpa = std.testing.allocator };
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        fs.error_handling = .continue_on_error;
        try fs.stringToIntVar(i64, &state, "headers", 0, "header map");
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected_count, map.count());
    }
}

test "StringToInt CalledTwice - multiple Set calls merge" {
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try fs.parse(&.{ "--headers=a=1,b=2", "--headers=c=3" });
    try std.testing.expectEqual(@as(u32, 3), map.count());
    try std.testing.expectEqual(@as(i32, 1), map.get("a").?);
    try std.testing.expectEqual(@as(i32, 2), map.get("b").?);
    try std.testing.expectEqual(@as(i32, 3), map.get("c").?);
}

test "StringToInt WithDefault - preserves defaults when not set" {
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    // Pre-populate defaults
    try map.put(std.testing.allocator, "a", 1);
    try map.put(std.testing.allocator, "b", 2);
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(u32, 2), map.count());
    try std.testing.expectEqual(@as(i32, 1), map.get("a").?);
    try std.testing.expectEqual(@as(i32, 2), map.get("b").?);
}

test "StringToInt rejects non-key=value" {
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try std.testing.expectError(error.ExpectedKeyValue, fs.parse(&.{"--headers=badval"}));
}

test "StringToInt string() output" {
    // Regression: previously used bufPrint with 64-byte buffer + catch unreachable.
    // Verify string() works correctly for map values.
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try fs.parse(&.{"--headers=a=1,b=42"});
    try std.testing.expectEqual(@as(u32, 2), map.count());

    const flag = fs.lookup("headers").?;
    const str = try flag.value.string(std.testing.allocator);
    defer std.testing.allocator.free(str);
    // Output format: "key=val, key=val" — order may vary with hashmap
    try std.testing.expect(std.mem.indexOf(u8, str, "a=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "b=42") != null);
}

test "StringToString Empty - parses no args" {
    // Matches Go TestEmptyS2S
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToStringVar(&state, "s2s", "", "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(u32, 0), map.count());
}

test "StringToString WithDefault - parses value overriding defaults" {
    // Matches Go TestS2SWithDefault
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try map.put(std.testing.allocator, "a", "1");
    try map.put(std.testing.allocator, "b", "2");
    try fs.stringToStringVar(&state, "s2s", "", "");
    try fs.parse(&.{"--s2s=c=3,d=4"});
    try std.testing.expectEqual(@as(u32, 2), map.count());
    try std.testing.expectEqualStrings("3", map.get("c").?);
    try std.testing.expectEqualStrings("4", map.get("d").?);
}

test "StringToString" {
    const TestCase = struct {
        input: []const []const u8,
        expected_count: u32,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{ "--labels=env=prod", "--labels=region=us-east" }, .expected_count = 2 },
        .{ .input = &.{"--labels=a=1,b=2,c=3"}, .expected_count = 3 },
    };

    for (testCases) |tc| {
        var map: std.StringHashMapUnmanaged([]const u8) = .empty;
        var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        fs.error_handling = .continue_on_error;
        try fs.stringToStringVar(&state, "labels", "", "");
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected_count, map.count());
    }
}

test "StringToString CalledTwice - multiple Set calls merge" {
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToStringVar(&state, "labels", "", "");
    try fs.parse(&.{ "--labels=a=1,b=2", "--labels=c=3" });
    try std.testing.expectEqual(@as(u32, 3), map.count());
    try std.testing.expectEqualStrings("1", map.get("a").?);
    try std.testing.expectEqualStrings("2", map.get("b").?);
    try std.testing.expectEqualStrings("3", map.get("c").?);
}

test "StringToString WithDefault - preserves defaults when not set" {
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToStringVar(&state, "labels", "", "");
    // Pre-populate defaults
    try map.put(std.testing.allocator, "a", "1");
    try map.put(std.testing.allocator, "b", "2");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(u32, 2), map.count());
    try std.testing.expectEqualStrings("1", map.get("a").?);
    try std.testing.expectEqualStrings("2", map.get("b").?);
}

test "StringToString NilDefault - empty map default works like Go nil" {
    // Matches Go's TestS2SNilDefault
    // In Go: f.StringToStringVar(&s2s, "s2s", nil, "Command separated ls!")
    // In Zig: we use empty map .{} instead of nil - behavior is equivalent
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToStringVar(&state, "s2s", "", "Command separated ls!");
    try fs.parse(&.{"--s2s=a=1,b=2"});
    try std.testing.expectEqual(@as(u32, 2), map.count());
    try std.testing.expectEqualStrings("1", map.get("a").?);
    try std.testing.expectEqualStrings("2", map.get("b").?);
}

test "StringToString string() output" {
    // Verify string() works correctly for string-to-string map values
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToStringVar(&state, "labels", "", "");
    try fs.parse(&.{"--labels=env=prod,region=us"});
    try std.testing.expectEqual(@as(u32, 2), map.count());

    const flag = fs.lookup("labels").?;
    const str = try flag.value.string(std.testing.allocator);
    defer std.testing.allocator.free(str);
    // Output format: "key=val, key=val" — order may vary with hashmap
    try std.testing.expect(std.mem.indexOf(u8, str, "env=prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "region=us") != null);
}

test "StringToInt NilDefault - empty map default works like Go nil" {
    // Same as StringToString NilDefault - empty map replaces nil
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToIntVar(i32, &state, "s2i", 0, "Command separated list!");
    try fs.parse(&.{"--s2i=a=1,b=2"});
    try std.testing.expectEqual(@as(u32, 2), map.count());
    try std.testing.expectEqual(@as(i32, 1), map.get("a").?);
    try std.testing.expectEqual(@as(i32, 2), map.get("b").?);
}

// ── Allocation-failure tests ──
//
// See the note in slice_types.zig. error_handling MUST be .continue_on_error,
// otherwise OOM routes to std.process.exit(2) and kills the test process.

fn strToStrSetImpl(gpa: std.mem.Allocator) !void {
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = gpa };
    var fs = pflag.FlagSet.init(gpa, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    try fs.stringToStringVar(&state, "labels", "", "");
    // Second Set reuses key "a" so the duplicate-key branch (manual key free +
    // old value free + in-place value swap) is exercised too.
    try fs.parse(&.{ "--labels=a=1,b=2", "--labels=a=3,c=4" });
}

test "StringToString set leaks nothing under allocation failure" {
    // Regression: `key` had an errdefer but `val` did not, so a failed map.put
    // leaked the duped value string.
    try std.testing.checkAllAllocationFailures(std.testing.allocator, strToStrSetImpl, .{});
}

fn strToIntSetImpl(gpa: std.mem.Allocator) !void {
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = gpa };
    var fs = pflag.FlagSet.init(gpa, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try fs.parse(&.{ "--headers=a=1,b=2", "--headers=a=3,c=4" });
}

test "StringToInt set leaks nothing under allocation failure" {
    // Validates the errdefer gpa.free(key) path, including the duplicate-key
    // branch where the fresh duped key is freed and the value updated in place.
    try std.testing.checkAllAllocationFailures(std.testing.allocator, strToIntSetImpl, .{});
}
