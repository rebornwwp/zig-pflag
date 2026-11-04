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

/// Parse CSV-formatted string into array of strings.
/// Matches Go's csv.NewReader behavior:
/// - Quoted fields: "one,two" → one,two
/// - Escaped quotes: "" → "
pub fn readAsCSV(gpa: std.mem.Allocator, val: []const u8) ![]const []const u8 {
    if (val.len == 0) return &.{};

    var result: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (result.items) |s| gpa.free(s);
        result.deinit(gpa);
    }

    var i: usize = 0;
    while (i < val.len) {
        var field: std.ArrayListUnmanaged(u8) = .empty;
        defer field.deinit(gpa);

        if (val[i] == '"') {
            // Quoted field
            i += 1; // skip opening quote
            while (i < val.len) {
                if (val[i] == '"') {
                    if (i + 1 < val.len and val[i + 1] == '"') {
                        // Escaped quote
                        try field.append(gpa, '"');
                        i += 2;
                    } else {
                        // End of quoted field
                        i += 1; // skip closing quote
                        break;
                    }
                } else {
                    try field.append(gpa, val[i]);
                    i += 1;
                }
            }
            // Skip to comma or end
            while (i < val.len and val[i] != ',') i += 1;
            if (i < val.len) i += 1; // skip comma
        } else {
            // Unquoted field
            while (i < val.len and val[i] != ',') {
                try field.append(gpa, val[i]);
                i += 1;
            }
            if (i < val.len) i += 1; // skip comma
        }

        const item = try gpa.dupe(u8, field.items);
        result.append(gpa, item) catch |err| {
            gpa.free(item);
            return err;
        };
    }

    return try result.toOwnedSlice(gpa);
}

/// Write array of strings as CSV format.
/// Matches Go's csv.Writer behavior.
pub fn writeAsCSV(gpa: std.mem.Allocator, vals: []const []const u8) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(gpa);

    for (vals, 0..) |s, i| {
        if (i > 0) try buf.appendSlice(gpa, ",");
        // Quote if contains comma, quote, or newline
        const needs_quote = std.mem.indexOfAny(u8, s, ",\"\n") != null;
        if (needs_quote) {
            try buf.appendSlice(gpa, "\"");
            for (s) |c| {
                if (c == '"') {
                    try buf.appendSlice(gpa, "\"\"");
                } else {
                    try buf.append(gpa, c);
                }
            }
            try buf.appendSlice(gpa, "\"");
        } else {
            try buf.appendSlice(gpa, s);
        }
    }

    return try buf.toOwnedSlice(gpa);
}

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
            // Use CSV parsing for comma-separated values
            const parsed = try readAsCSV(gpa, v);
            // Transfer ownership: parsed items are now owned by slice
            for (parsed) |item| {
                slice.append(gpa, item) catch |err| {
                    // Free remaining items on error
                    for (parsed) |s| gpa.free(s);
                    return err;
                };
            }
            // Free the parsed array container (but not the strings, they're now in slice)
            gpa.free(parsed);
            if (!state.changed) state.changed = true;
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
            const state: *StringSliceState = @ptrCast(@alignCast(ptr));
            const slice = state.value;
            return try writeAsCSV(gpa, slice.items);
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

// ── Tests ──

test "StringSlice" {
    const TestCase = struct {
        input: []const []const u8,
        expected_len: usize,
        expected_first: ?[]const u8 = null,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{ "--tag=a", "--tag=b", "--tag=c" }, .expected_len = 3, .expected_first = "a" },
        .{ .input = &.{ "-t", "x", "-t", "y" }, .expected_len = 2, .expected_first = "x" },
        .{ .input = &.{"--tag=a,b,c"}, .expected_len = 3, .expected_first = "a" },
    };

    for (testCases) |tc| {
        var slice: std.ArrayListUnmanaged([]const u8) = .empty;
        var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        fs.error_handling = .continue_on_error;
        try fs.stringSliceVarP(&state, "tag", "t", &.{}, "");
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected_len, slice.items.len);
        if (tc.expected_first) |first| {
            try std.testing.expectEqualStrings(first, slice.items[0]);
        }
    }
}

test "StringSlice first Set replaces defaults" {
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "tag", &.{ "default1", "default2" }, "");
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try fs.parse(&.{"--tag=gamma"});
    try std.testing.expectEqual(@as(usize, 1), slice.items.len);
    try std.testing.expectEqualStrings("gamma", slice.items[0]);
}

test "StringSlice CalledTwice - multiple Set calls append" {
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "tag", &.{}, "");
    // First call replaces defaults (empty), second call appends
    try fs.parse(&.{ "--tag=a,b", "--tag=c,d" });
    try std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.testing.expectEqualStrings("a", slice.items[0]);
    try std.testing.expectEqualStrings("b", slice.items[1]);
    try std.testing.expectEqualStrings("c", slice.items[2]);
    try std.testing.expectEqualStrings("d", slice.items[3]);
}

test "StringSlice WithDefault - preserves defaults when not set" {
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "tag", &.{ "default1", "default2" }, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqualStrings("default1", slice.items[0]);
    try std.testing.expectEqualStrings("default2", slice.items[1]);
}

test "StringSlice SquareBrackets - quoted brackets preserved" {
    // Matches Go's TestSSWithSquareBrackets
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    // Quoted square brackets should be preserved as part of the value
    try fs.parse(&.{ "--ss=\"[a-z]\"", "--ss=\"[a-z]+\"" });
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqualStrings("[a-z]", slice.items[0]);
    try std.testing.expectEqualStrings("[a-z]+", slice.items[1]);
}

test "StringSlice WithComma - quoted commas preserved" {
    // Matches Go's TestSSWithComma
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    // Go test: in := []string{`"one,two"`, `"three"`, `"four,five",six`}
    // expected := []string{"one,two", "three", "four,five", "six"}
    try fs.parse(&.{ "--ss=\"one,two\"", "--ss=\"three\"", "--ss=\"four,five\",six" });
    try std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.testing.expectEqualStrings("one,two", slice.items[0]);
    try std.testing.expectEqualStrings("three", slice.items[1]);
    try std.testing.expectEqualStrings("four,five", slice.items[2]);
    try std.testing.expectEqualStrings("six", slice.items[3]);
}

test "readAsCSV - basic parsing" {
    const gpa = std.testing.allocator;

    // Empty string
    const empty = try readAsCSV(gpa, "");
    try std.testing.expectEqual(@as(usize, 0), empty.len);

    // Simple comma-separated
    const simple = try readAsCSV(gpa, "a,b,c");
    try std.testing.expectEqual(@as(usize, 3), simple.len);
    try std.testing.expectEqualStrings("a", simple[0]);
    try std.testing.expectEqualStrings("b", simple[1]);
    try std.testing.expectEqualStrings("c", simple[2]);
    for (simple) |s| gpa.free(s);

    // Quoted field with comma
    const quoted = try readAsCSV(gpa, "\"one,two\",three");
    try std.testing.expectEqual(@as(usize, 2), quoted.len);
    try std.testing.expectEqualStrings("one,two", quoted[0]);
    try std.testing.expectEqualStrings("three", quoted[1]);
    for (quoted) |s| gpa.free(s);

    // Escaped quotes
    const escaped = try readAsCSV(gpa, "\"a\"\"b\",c");
    try std.testing.expectEqual(@as(usize, 2), escaped.len);
    try std.testing.expectEqualStrings("a\"b", escaped[0]);
    try std.testing.expectEqualStrings("c", escaped[1]);
    for (escaped) |s| gpa.free(s);
}

test "writeAsCSV - basic output" {
    const gpa = std.testing.allocator;

    // Empty
    const empty = try writeAsCSV(gpa, &.{});
    try std.testing.expectEqualStrings("", empty);
    gpa.free(empty);

    // Simple
    const simple = try writeAsCSV(gpa, &.{ "a", "b", "c" });
    try std.testing.expectEqualStrings("a,b,c", simple);
    gpa.free(simple);

    // With comma (needs quoting)
    const quoted = try writeAsCSV(gpa, &.{ "one,two", "three" });
    try std.testing.expectEqualStrings("\"one,two\",three", quoted);
    gpa.free(quoted);

    // With quote (needs escaping)
    const escaped = try writeAsCSV(gpa, &.{ "a\"b", "c" });
    try std.testing.expectEqualStrings("\"a\"\"b\",c", escaped);
    gpa.free(escaped);
}

test "IntSlice" {
    const TestCase = struct {
        input: []const []const u8,
        expected_len: usize,
        expected_first: ?i32 = null,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{ "--num=1", "--num=2", "--num=3" }, .expected_len = 3, .expected_first = 1 },
        .{ .input = &.{"--num=10,20,30"}, .expected_len = 3, .expected_first = 10 },
    };

    for (testCases) |tc| {
        var slice: std.ArrayListUnmanaged(i32) = .empty;
        var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.intSliceVar(i32, &state, "num", &.{}, "");
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected_len, slice.items.len);
        if (tc.expected_first) |first| {
            try std.testing.expectEqual(first, slice.items[0]);
        }
    }
}

test "IntSlice CalledTwice - multiple Set calls append" {
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.intSliceVar(i32, &state, "num", &.{}, "");
    try fs.parse(&.{ "--num=1,2", "--num=3,4" });
    try std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.testing.expectEqual(@as(i32, 1), slice.items[0]);
    try std.testing.expectEqual(@as(i32, 2), slice.items[1]);
    try std.testing.expectEqual(@as(i32, 3), slice.items[2]);
    try std.testing.expectEqual(@as(i32, 4), slice.items[3]);
}

test "IntSlice WithDefault - preserves defaults when not set" {
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.intSliceVar(i32, &state, "num", &.{ 0, 1 }, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqual(@as(i32, 0), slice.items[0]);
    try std.testing.expectEqual(@as(i32, 1), slice.items[1]);
}

test "BoolSlice" {
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.boolSliceVar(bool, &state, "flags", &.{}, "");
    try fs.parse(&.{ "--flags=true", "--flags=false", "--flags=1" });
    try std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.testing.expect(slice.items[0]);
    try std.testing.expect(!slice.items[1]);
    try std.testing.expect(slice.items[2]);
}

test "BoolSlice CalledTwice - multiple Set calls append" {
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.boolSliceVar(bool, &state, "flags", &.{}, "");
    try fs.parse(&.{ "--flags=true,false", "--flags=1,0" });
    try std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.testing.expect(slice.items[0]);
    try std.testing.expect(!slice.items[1]);
    try std.testing.expect(slice.items[2]);
    try std.testing.expect(!slice.items[3]);
}

test "BoolSlice WithDefault - preserves defaults when not set" {
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.boolSliceVar(bool, &state, "flags", &.{ false, true }, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expect(!slice.items[0]);
    try std.testing.expect(slice.items[1]);
}

test "FloatSlice" {
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.floatSliceVar(f64, &state, "vals", &.{}, "");
    try fs.parse(&.{ "--vals=1.5", "--vals=2.7", "--vals=3.14" });
    try std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.testing.expectApproxEqRel(@as(f64, 1.5), slice.items[0], 0.001);
    try std.testing.expectApproxEqRel(@as(f64, 2.7), slice.items[1], 0.001);
    try std.testing.expectApproxEqRel(@as(f64, 3.14), slice.items[2], 0.001);
}

test "FloatSlice CalledTwice - multiple Set calls append" {
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.floatSliceVar(f64, &state, "vals", &.{}, "");
    try fs.parse(&.{ "--vals=1.5,2.7", "--vals=3.14,4.0" });
    try std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.testing.expectApproxEqRel(@as(f64, 1.5), slice.items[0], 0.001);
    try std.testing.expectApproxEqRel(@as(f64, 2.7), slice.items[1], 0.001);
    try std.testing.expectApproxEqRel(@as(f64, 3.14), slice.items[2], 0.001);
    try std.testing.expectApproxEqRel(@as(f64, 4.0), slice.items[3], 0.001);
}

test "FloatSlice WithDefault - preserves defaults when not set" {
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.floatSliceVar(f64, &state, "vals", &.{ 1.0, 2.0 }, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), slice.items[0], 0.001);
    try std.testing.expectApproxEqRel(@as(f64, 2.0), slice.items[1], 0.001);
}

test "UintSlice" {
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.uintSliceVar(u32, &state, "nums", &.{}, "");
    try fs.parse(&.{ "--nums=10", "--nums=20", "--nums=30" });
    try std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.testing.expectEqual(@as(u32, 10), slice.items[0]);
    try std.testing.expectEqual(@as(u32, 20), slice.items[1]);
    try std.testing.expectEqual(@as(u32, 30), slice.items[2]);
}

test "UintSlice CalledTwice - multiple Set calls append" {
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.uintSliceVar(u32, &state, "nums", &.{}, "");
    try fs.parse(&.{ "--nums=1,2", "--nums=3,4" });
    try std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.testing.expectEqual(@as(u32, 1), slice.items[0]);
    try std.testing.expectEqual(@as(u32, 2), slice.items[1]);
    try std.testing.expectEqual(@as(u32, 3), slice.items[2]);
    try std.testing.expectEqual(@as(u32, 4), slice.items[3]);
}

test "UintSlice WithDefault - preserves defaults when not set" {
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.uintSliceVar(u32, &state, "nums", &.{ 0, 1 }, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqual(@as(u32, 0), slice.items[0]);
    try std.testing.expectEqual(@as(u32, 1), slice.items[1]);
}

test "UintSlice Hex - parses 0x prefixed values" {
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.uintSliceVar(u32, &state, "nums", &.{}, "");
    try fs.parse(&.{"--nums=0x1,0x2,0x10"});
    try std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.testing.expectEqual(@as(u32, 1), slice.items[0]);
    try std.testing.expectEqual(@as(u32, 2), slice.items[1]);
    try std.testing.expectEqual(@as(u32, 16), slice.items[2]);
}

test "StringArray" {
    const TestCase = struct {
        input: []const []const u8,
        expected_len: usize,
        expected_first: ?[]const u8 = null,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{ "--arr=a", "--arr=b" }, .expected_len = 2, .expected_first = "a" },
        .{ .input = &.{"--arr=one,two"}, .expected_len = 1, .expected_first = "one,two" },
    };

    for (testCases) |tc| {
        var slice: std.ArrayListUnmanaged([]const u8) = .empty;
        var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.stringArrayVar(&state, "arr", &.{}, "");
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected_len, slice.items.len);
        if (tc.expected_first) |first| {
            try std.testing.expectEqualStrings(first, slice.items[0]);
        }
    }
}

test "StringArray CalledTwice - multiple Set calls append" {
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringArrayVar(&state, "arr", &.{}, "");
    try fs.parse(&.{ "--arr=a,b", "--arr=c" });
    // StringArray: first Set replaces defaults, subsequent Set appends
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqualStrings("a,b", slice.items[0]);
    try std.testing.expectEqualStrings("c", slice.items[1]);
}

test "StringArray WithDefault - preserves defaults when not set" {
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringArrayVar(&state, "arr", &.{ "default1", "default2" }, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqualStrings("default1", slice.items[0]);
    try std.testing.expectEqualStrings("default2", slice.items[1]);
}
