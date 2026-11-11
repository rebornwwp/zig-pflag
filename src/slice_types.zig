//! Slice flag types. Maps from pflag/`*_slice.go`, string_array.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const internal = @import("internal.zig");
const Value = @import("value.zig").Value;

// ─── Generic Slice State ───

/// Wrapper struct to track allocator and changed state for slice values.
/// Used by int/uint/float/bool slice types.
///
/// changed flag: tracks whether set() has been called at least once.
/// Before the first Set, the slice contains user-provided defaults.
/// The first Set clears and replaces defaults; subsequent Sets append.
pub fn SliceState(comptime T: type) type {
    return struct {
        value: *std.ArrayListUnmanaged(T),
        gpa: std.mem.Allocator,
        changed: bool = false,
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

// File-local aliases; the public paths are `pflag.readAsCSV`/`pflag.writeAsCSV`,
// both canonically defined in internal.zig (upstream keeps these in string_slice.go).
const readAsCSV = @import("internal.zig").readAsCSV;
const writeAsCSV = @import("internal.zig").writeAsCSV;

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
            // Transfer ownership: parsed items are now owned by slice.
            // Transfer one-by-one so on OOM we only free un-transferred items
            // (avoids double-free between this loop and the errdefer above).
            var transferred: usize = 0;
            errdefer {
                for (parsed[transferred..]) |s| gpa.free(s);
                gpa.free(parsed);
            }
            for (parsed) |item| {
                try slice.append(gpa, item);
                transferred += 1;
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

/// CSV-semantic string slice Value over `state` (first Set replaces defaults).
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
            // Dupe first, then append. If append fails we must free `duped`,
            // otherwise it leaks (ownership was never transferred to the slice).
            const duped = try gpa.dupe(u8, v);
            errdefer gpa.free(duped);
            try slice.append(gpa, duped);
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

/// Array-semantic string slice Value: whole raw value = ONE element, no CSV.
pub fn stringArrayValue(state: *StringSliceState) Value {
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = &stringArrayVtable };
}

// ─── Shared numeric-slice vtable core ───

fn parseIntBase0(comptime T: type, s: []const u8) !T {
    return std.fmt.parseInt(T, s, 0);
}

fn parseFloat(comptime T: type, s: []const u8) !T {
    return std.fmt.parseFloat(T, s);
}

/// Body shared by the int/uint/float numeric slices: first-Set replace
/// semantics, comma split through `parse`, output joined with ", " under the
/// `@typeName(T) ++ "s"` name. Bool slices keep their own vtable because
/// upstream bool_slice.go quotes-strip + CSV reads (different semantics).
/// `parse` is a comptime-known shim `fn (comptime Ty: type, s: []const u8) !Ty`
/// — fn *types* cannot carry inferred error sets, hence the anytype.
fn makeNumSliceVtable(
    comptime T: type,
    comptime parse: anytype,
) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                // Parse the whole list into a temporary buffer BEFORE touching
                // the committed slice or the `changed` flag (upstream builds a
                // local `out []int`): a bad element mid-list must leave
                // previously-parsed values and untouched defaults intact.
                var out: std.ArrayListUnmanaged(T) = .empty;
                defer out.deinit(state.gpa);
                var it = std.mem.splitScalar(u8, v, ',');
                while (it.next()) |part| {
                    const trimmed = std.mem.trim(u8, part, " \t");
                    if (trimmed.len > 0) {
                        try out.append(state.gpa, try parse(T, trimmed));
                    }
                }
                // First Set replaces defaults; subsequent Sets append (matches Go)
                if (!state.changed) {
                    state.value.clearRetainingCapacity();
                    state.changed = true;
                }
                try state.value.appendSlice(state.gpa, out.items);
            }
        }.set,
        .string = struct {
            fn string(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
                const state: *SliceState(T) = @ptrCast(@alignCast(ptr));
                const slice = state.value;
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                for (slice.items, 0..) |v, i| {
                    if (i > 0) try buf.appendSlice(gpa, ", ");
                    const formatted = try gpa.print("{d}", .{v});
                    defer gpa.free(formatted);
                    try buf.appendSlice(gpa, formatted);
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

// ─── Int Slice ───

fn intSliceVtable(comptime T: type) Value.VTable {
    return makeNumSliceVtable(T, parseIntBase0);
}
const i32SliceVtable = intSliceVtable(i32);
const i64SliceVtable = intSliceVtable(i64);

/// Signed numeric slice Value via the shared makeNumSliceVtable (i8..i64).
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
    return makeNumSliceVtable(T, parseIntBase0);
}
const u8SliceVtable = uintSliceVtable(u8);
const u16SliceVtable = uintSliceVtable(u16);
const u32SliceVtable = uintSliceVtable(u32);
const u64SliceVtable = uintSliceVtable(u64);

/// Unsigned numeric slice Value (u8..u64), same comma-split semantics.
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
            const gpa = state.gpa;

            // Remove all quote characters (matches Go: strings.NewReplacer(`"`, "", `'`, "", "`", ""))
            var unquoted: std.ArrayListUnmanaged(u8) = .empty;
            defer unquoted.deinit(gpa);
            for (v) |c| {
                if (c != '"' and c != '\'' and c != '`') {
                    try unquoted.append(gpa, c);
                }
            }

            // Parse with CSV reader
            const parsed = try readAsCSV(gpa, unquoted.items);
            defer {
                for (parsed) |s| gpa.free(s);
                gpa.free(parsed);
            }

            // Parse boolean values into slice
            // Parse the whole list locally first (upstream matches): a bad
            // element must leave the committed slice untouched.
            var out: std.ArrayListUnmanaged(bool) = .empty;
            defer out.deinit(gpa);
            for (parsed) |bool_str| {
                const trimmed = std.mem.trim(u8, bool_str, " \t");
                try out.append(gpa, try internal.parseBool(trimmed));
            }
            // First Set replaces defaults; subsequent Sets append (matches Go)
            if (!state.changed) {
                state.value.clearRetainingCapacity();
                state.changed = true;
            }
            try state.value.appendSlice(gpa, out.items);
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

/// Bool slice Value: quote-stripped CSV input, then parseBool per element.
pub fn boolSliceValue(state: *SliceState(bool)) Value {
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = &boolSliceVtable };
}

// ─── Float Slice ───

fn floatSliceVtable(comptime T: type) Value.VTable {
    return makeNumSliceVtable(T, parseFloat);
}
const f32SliceVtable = floatSliceVtable(f32);
const f64SliceVtable = floatSliceVtable(f64);

/// Float slice Value (f32/f64).
pub fn floatSliceValue(comptime T: type, state: *SliceState(T)) Value {
    const vt: *const Value.VTable = switch (T) {
        f32 => &f32SliceVtable,
        f64 => &f64SliceVtable,
        else => @compileError("Unsupported float slice type: " ++ @typeName(T)),
    };
    return .{ .ptr = @ptrCast(@alignCast(state)), .vtable = vt };
}

// ── Tests ──

test "StringSlice Empty - parses no args" {
    // Matches Go TestEmptySS
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "StringSlice Empty value - parses --ss=" {
    // Matches Go TestEmptySSValue
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    try fs.parse(&.{"--ss="});
    try std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "StringSlice Default - preserves defaults" {
    // Matches Go TestSSDefault
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "ss", &.{ "default", "values" }, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqualStrings("default", slice.items[0]);
    try std.testing.expectEqualStrings("values", slice.items[1]);
}

test "StringSlice WithDefault - parses value overriding defaults" {
    // Matches Go TestSSWithDefault
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "ss", &.{ "default", "values" }, "");
    try fs.parse(&.{"--ss=one,two,4,3"});
    try std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.testing.expectEqualStrings("one", slice.items[0]);
    try std.testing.expectEqualStrings("two", slice.items[1]);
    try std.testing.expectEqualStrings("4", slice.items[2]);
    try std.testing.expectEqualStrings("3", slice.items[3]);
}

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
    gpa.free(simple);

    // Quoted field with comma
    const quoted = try readAsCSV(gpa, "\"one,two\",three");
    try std.testing.expectEqual(@as(usize, 2), quoted.len);
    try std.testing.expectEqualStrings("one,two", quoted[0]);
    try std.testing.expectEqualStrings("three", quoted[1]);
    for (quoted) |s| gpa.free(s);
    gpa.free(quoted);

    // Escaped quotes
    const escaped = try readAsCSV(gpa, "\"a\"\"b\",c");
    try std.testing.expectEqual(@as(usize, 2), escaped.len);
    try std.testing.expectEqualStrings("a\"b", escaped[0]);
    try std.testing.expectEqualStrings("c", escaped[1]);
    for (escaped) |s| gpa.free(s);
    gpa.free(escaped);
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

test "StringSlice string() output" {
    // Verify string() works correctly for string slice values (uses writeAsCSV)
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    try fs.parse(&.{"--ss=hello,world"});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);

    const flag = fs.lookup("ss").?;
    const str = try flag.value.string(std.testing.allocator);
    defer std.testing.allocator.free(str);
    try std.testing.expect(std.mem.indexOf(u8, str, "hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "world") != null);
}

test "IntSlice Empty - parses no args" {
    // Matches Go TestEmptyIS
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.intSliceVar(i32, &state, "num", &.{}, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 0), slice.items.len);
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
        .{ .input = &.{"--num=0x10,1_000,-5"}, .expected_len = 3, .expected_first = 16 }, // radix-0 + underscore + negative
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

test "IntSlice WithDefault - parses value overriding defaults" {
    // Matches Go TestISWithDefault
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.intSliceVar(i32, &state, "num", &.{ 0, 1 }, "");
    try fs.parse(&.{"--num=1,2"});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqual(@as(i32, 1), slice.items[0]);
    try std.testing.expectEqual(@as(i32, 2), slice.items[1]);
}

test "IntSlice string() output" {
    // Verify string() works correctly for int slice values
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.intSliceVar(i32, &state, "num", &.{}, "");
    try fs.parse(&.{"--num=1,-42,100"});
    try std.testing.expectEqual(@as(usize, 3), slice.items.len);

    const flag = fs.lookup("num").?;
    const str = try flag.value.string(std.testing.allocator);
    defer std.testing.allocator.free(str);
    try std.testing.expect(std.mem.indexOf(u8, str, "1") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "100") != null);
}

test "BoolSlice Empty - parses no args" {
    // Matches Go TestEmptyBS
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.boolSliceVar(&state, "flags", &.{}, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "BoolSlice" {
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.boolSliceVar(&state, "flags", &.{}, "");
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
    try fs.boolSliceVar(&state, "flags", &.{}, "");
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
    try fs.boolSliceVar(&state, "flags", &.{ false, true }, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expect(!slice.items[0]);
    try std.testing.expect(slice.items[1]);
}

test "BoolSlice WithDefault - parses value overriding defaults" {
    // Matches Go TestBSWithDefault
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.boolSliceVar(&state, "flags", &.{ false, true }, "");
    try fs.parse(&.{"--flags=FALSE,1"});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expect(!slice.items[0]);
    try std.testing.expect(slice.items[1]);
}

test "BoolSlice BadQuoting - handles quotes and spaces like Go" {
    // Matches Go's TestBSBadQuoting
    const TestCase = struct {
        input: []const u8,
        expected: []const bool,
    };

    const testCases = [_]TestCase{
        .{ .input = "1,0,true", .expected = &.{ true, false, true } },
        .{ .input = "True,F", .expected = &.{ true, false } },
        .{ .input = "T,0", .expected = &.{ true, false } },
        .{ .input = "1,0", .expected = &.{ true, false } },
        .{ .input = "true,false,false", .expected = &.{ true, false, false } },
        .{ .input = "\"true,false,false,1,0,     T\", false ", .expected = &.{ true, false, false, true, false, true, false } },
        .{ .input = "\"0, False,  T,false  , true,F\",true", .expected = &.{ false, false, true, false, true, false, true } },
    };

    for (testCases) |tc| {
        var slice: std.ArrayListUnmanaged(bool) = .empty;
        var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.boolSliceVar(&state, "flags", &.{}, "");
        const arg = try std.fmt.allocPrint(std.testing.allocator, "--flags={s}", .{tc.input});
        defer std.testing.allocator.free(arg);
        try fs.parse(&.{arg});
        try std.testing.expectEqual(tc.expected.len, slice.items.len);
        for (tc.expected, 0..) |exp, i| {
            try std.testing.expectEqual(exp, slice.items[i]);
        }
    }
}

test "BoolSlice string() output" {
    // Verify string() works correctly for bool slice values
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.boolSliceVar(&state, "flags", &.{}, "");
    try fs.parse(&.{"--flags=true,false,1"});
    try std.testing.expectEqual(@as(usize, 3), slice.items.len);

    const flag = fs.lookup("flags").?;
    const str = try flag.value.string(std.testing.allocator);
    defer std.testing.allocator.free(str);
    // Output format: "true, false, true"
    try std.testing.expect(std.mem.indexOf(u8, str, "true") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "false") != null);
}

test "FloatSlice Empty - parses no args" {
    // Matches Go TestEmptyF32S (f64 in Zig)
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.floatSliceVar(f64, &state, "vals", &.{}, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 0), slice.items.len);
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
    // second Set appends; exponent and negative forms parse fine
    try fs.parse(&.{"--vals=1e3,-2.5"});
    try std.testing.expectApproxEqRel(@as(f64, 1000), slice.items[3], 0.001);
    try std.testing.expectApproxEqRel(@as(f64, -2.5), slice.items[4], 0.001);
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

test "FloatSlice WithDefault - parses value overriding defaults" {
    // Matches Go TestF32SWithDefault
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.floatSliceVar(f64, &state, "vals", &.{ 1.0, 2.0 }, "");
    try fs.parse(&.{"--vals=3.14,2.71"});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectApproxEqRel(@as(f64, 3.14), slice.items[0], 0.001);
    try std.testing.expectApproxEqRel(@as(f64, 2.71), slice.items[1], 0.001);
}

test "FloatSlice string() output handles large values" {
    // Regression: previously used bufPrint with 32-byte buffer + catch unreachable.
    // f64 values like 1.7976931348623157e+308 exceed 32 chars in decimal form.
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.floatSliceVar(f64, &state, "vals", &.{}, "");
    try fs.parse(&.{ "--vals=1.5", "--vals=1.7976931348623157e+308", "--vals=-0.0000001" });
    try std.testing.expectEqual(@as(usize, 3), slice.items.len);

    // Verify string() output doesn't crash (the old code would panic with catch unreachable)
    const flag = fs.lookup("vals").?;
    const str = try flag.value.string(std.testing.allocator);
    defer std.testing.allocator.free(str);
    // Just verify it contains the values in some form
    try std.testing.expect(std.mem.indexOf(u8, str, "1.5") != null);
    try std.testing.expect(str.len > 10); // large number produces long string
    try std.testing.expect(std.mem.indexOf(u8, str, "-0.0000001") != null);
}

test "UintSlice Empty - parses no args" {
    // Matches Go TestEmptyUIS
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.uintSliceVar(u32, &state, "nums", &.{}, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 0), slice.items.len);
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
    // second Set appends; radix-0 and underscores honored by makeNumSliceVtable
    try fs.parse(&.{"--nums=0x10,1_000"});
    try std.testing.expectEqual(@as(u32, 16), slice.items[3]);
    try std.testing.expectEqual(@as(u32, 1000), slice.items[4]);
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

test "UintSlice WithDefault - parses value overriding defaults" {
    // Matches Go TestUISWithDefault
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.uintSliceVar(u32, &state, "nums", &.{ 0, 1 }, "");
    try fs.parse(&.{"--nums=1,2"});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqual(@as(u32, 1), slice.items[0]);
    try std.testing.expectEqual(@as(u32, 2), slice.items[1]);
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

test "UintSlice string() output" {
    // Verify string() works correctly for uint slice values
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.uintSliceVar(u32, &state, "nums", &.{}, "");
    try fs.parse(&.{"--nums=10,42,8080"});
    try std.testing.expectEqual(@as(usize, 3), slice.items.len);

    const flag = fs.lookup("nums").?;
    const str = try flag.value.string(std.testing.allocator);
    defer std.testing.allocator.free(str);
    try std.testing.expect(std.mem.indexOf(u8, str, "10") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "8080") != null);
}

test "StringArray Empty - parses no args" {
    // Matches Go TestEmptySA
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "StringArray Default - preserves defaults when not set" {
    // Matches Go TestSADefault
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringArrayVar(&state, "sa", &.{ "default", "values" }, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.testing.expectEqualStrings("default", slice.items[0]);
    try std.testing.expectEqualStrings("values", slice.items[1]);
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

test "StringArray Empty value - parses --sa= as empty string" {
    // StringArray appends empty string for --sa= (matches Go source behavior)
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{"--sa="});
    try std.testing.expectEqual(@as(usize, 1), slice.items.len);
    try std.testing.expectEqualStrings("", slice.items[0]);
}

test "StringArray WithDefault - parses value overriding defaults" {
    // Matches Go TestSAWithDefault
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringArrayVar(&state, "sa", &.{ "default", "values" }, "");
    try fs.parse(&.{"--sa=one"});
    try std.testing.expectEqual(@as(usize, 1), slice.items.len);
    try std.testing.expectEqualStrings("one", slice.items[0]);
}

test "StringArray WithSpecialChar - preserves commas and quotes" {
    // Matches Go TestSAWithSpecialChar
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{ "--sa=one,two", "--sa=\"three\"", "--sa=\"four,five\",six", "--sa=seven eight" });
    try std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.testing.expectEqualStrings("one,two", slice.items[0]);
    try std.testing.expectEqualStrings("\"three\"", slice.items[1]);
    try std.testing.expectEqualStrings("\"four,five\",six", slice.items[2]);
    try std.testing.expectEqualStrings("seven eight", slice.items[3]);
}

test "StringArray WithSquareBrackets - preserves brackets" {
    // Matches Go TestSAWithSquareBrackets
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{ "--sa=][]-[", "--sa=[a-z]", "--sa=[a-z]+" });
    try std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.testing.expectEqualStrings("][]-[", slice.items[0]);
    try std.testing.expectEqualStrings("[a-z]", slice.items[1]);
    try std.testing.expectEqualStrings("[a-z]+", slice.items[2]);
}

test "StringArray string() output" {
    // Verify string() works correctly for string array values
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{ "--sa=hello", "--sa=world" });
    try std.testing.expectEqual(@as(usize, 2), slice.items.len);

    const flag = fs.lookup("sa").?;
    const str = try flag.value.string(std.testing.allocator);
    defer std.testing.allocator.free(str);
    // StringArray uses comma separator (not CSV)
    try std.testing.expect(std.mem.indexOf(u8, str, "hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "world") != null);
}

test "StringToInt Empty - parses no args" {
    // Matches Go TestEmptyS2I
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try fs.stringToIntVar(i32, &state, "s2i", 0, "");
    try fs.parse(&.{});
    try std.testing.expectEqual(@as(u32, 0), map.count());
}

test "StringToInt WithDefault - parses value overriding defaults" {
    // Matches Go TestS2IWithDefault
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = std.testing.allocator };
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    try map.put(std.testing.allocator, "a", 1);
    try map.put(std.testing.allocator, "b", 2);
    try fs.stringToIntVar(i32, &state, "s2i", 0, "");
    try fs.parse(&.{"--s2i=a=3,b=4"});
    try std.testing.expectEqual(@as(u32, 2), map.count());
    try std.testing.expectEqual(@as(i32, 3), map.get("a").?);
    try std.testing.expectEqual(@as(i32, 4), map.get("b").?);
}

test "numeric slices parse errors and state preservation" {
    // Gap 1: a failing element must surface the vtable error type through
    // fs.parse (continue_on_error, no process exit) AND leave the committed
    // slice untouched — both previously parsed values and untouched defaults
    // (makeNumSliceVtable/boolSlice now build the parsed list locally first).
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;

    var i32s: std.ArrayListUnmanaged(i32) = .empty;
    var i32_state = pflag.SliceState(i32){ .value = &i32s, .gpa = std.testing.allocator };
    try fs.intSliceVar(i32, &i32_state, "num", &.{}, "");

    var i64s: std.ArrayListUnmanaged(i64) = .empty;
    var i64_state = pflag.SliceState(i64){ .value = &i64s, .gpa = std.testing.allocator };
    try fs.intSliceVar(i64, &i64_state, "big", &.{ 7, 8 }, "");

    var u32s: std.ArrayListUnmanaged(u32) = .empty;
    var u32_state = pflag.SliceState(u32){ .value = &u32s, .gpa = std.testing.allocator };
    try fs.uintSliceVar(u32, &u32_state, "nums", &.{}, "");

    var f64s: std.ArrayListUnmanaged(f64) = .empty;
    var f64_state = pflag.SliceState(f64){ .value = &f64s, .gpa = std.testing.allocator };
    try fs.floatSliceVar(f64, &f64_state, "vals", &.{}, "");

    var bools: std.ArrayListUnmanaged(bool) = .empty;
    var bool_state = pflag.SliceState(bool){ .value = &bools, .gpa = std.testing.allocator };
    try fs.boolSliceVar(&bool_state, "on", &.{}, "");

    // bad element after a good one: same error type as the scalar path,
    // nothing committed, flag not marked changed (default replacement deferred)
    try std.testing.expectError(error.InvalidCharacter, fs.parse(&.{"--num=1,x"}));
    try std.testing.expectEqual(@as(usize, 0), i32s.items.len);
    var flag = fs.lookup("num").?;
    try std.testing.expect(!flag.changed);
    // a clean parse afterward still works: first Set replaces defaults
    try fs.parse(&.{"--num=1"});
    try std.testing.expect(flag.changed);
    try std.testing.expectEqual(@as(usize, 1), i32s.items.len);
    // failure AFTER success keeps the previously committed values
    try std.testing.expectError(error.InvalidCharacter, fs.parse(&.{"--num=2,3,bad"}));
    try std.testing.expectEqual(@as(usize, 1), i32s.items.len);
    try std.testing.expectEqual(@as(i32, 1), i32s.items[0]);

    // width overflow surfaces as Overflow (not InvalidCharacter); the
    // untouched defaults of another flag survive the failed parse
    try std.testing.expectError(error.Overflow, fs.parse(&.{"--big=9223372036854775808,7"}));
    flag = fs.lookup("big").?;
    try std.testing.expect(!flag.changed);
    try std.testing.expectEqual(@as(usize, 2), i64s.items.len);
    try std.testing.expectEqual(@as(i64, 7), i64s.items[0]);
    try std.testing.expectEqual(@as(i64, 8), i64s.items[1]);

    // uint slices: "-0" lands on zero (Zig radix-0 + Go ParseUint agree), but
    // a real negative is Overflow (same convention as the scalar widths).
    try fs.parse(&.{"--nums=-0"});
    try std.testing.expectEqual(@as(usize, 1), u32s.items.len);
    try std.testing.expectEqual(@as(u32, 0), u32s.items[0]);
    try std.testing.expectError(error.Overflow, fs.parse(&.{"--nums=-3"}));
    try std.testing.expectEqual(@as(usize, 1), u32s.items.len); // failed element not appended
    try std.testing.expectEqual(@as(u32, 0), u32s.items[0]);

    // float slice elements: bad token is InvalidCharacter
    try std.testing.expectError(error.InvalidCharacter, fs.parse(&.{"--vals=1.5,zz"}));
    try std.testing.expectEqual(@as(usize, 0), f64s.items.len);

    // bool slice elements go through parseBool: InvalidBoolValue
    try std.testing.expectError(error.InvalidBoolValue, fs.parse(&.{"--on=t,x"}));
    try std.testing.expectEqual(@as(usize, 0), bools.items.len);

    // empty fields between commas are skipped
    try fs.parse(&.{"--num=2,,3"});
    try std.testing.expectEqual(@as(usize, 3), i32s.items.len);
    try std.testing.expectEqual(@as(i32, 3), i32s.items[2]);
}

// ── Allocation-failure tests ──
//
// These use std.testing.checkAllAllocationFailures, which induces OOM at every
// possible allocation site one at a time and asserts allocated_bytes ==
// freed_bytes. This is the ONLY way to exercise the errdefer cleanup paths in
// the set() implementations — a plain test never hits them.
//
// error_handling MUST be .continue_on_error: the default .exit_on_error would
// call std.process.exit(2) on OOM and kill the test process.

fn stringSliceSetImpl(gpa: std.mem.Allocator) !void {
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = gpa };
    var fs = pflag.FlagSet.init(gpa, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    // Two Set calls: exercises both the "first Set replaces defaults" path and
    // the "subsequent Set appends" path of the transferred-counter cleanup.
    try fs.parse(&.{ "--ss=a,b,c", "--ss=d" });
}

test "StringSlice set leaks nothing under allocation failure" {
    // Regression: the original code freed ALL of `parsed` in a catch while the
    // outer errdefer also freed items already appended from `parsed` → double free.
    try std.testing.checkAllAllocationFailures(std.testing.allocator, stringSliceSetImpl, .{});
}

fn stringArraySetImpl(gpa: std.mem.Allocator) !void {
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = gpa };
    var fs = pflag.FlagSet.init(gpa, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{ "--sa=one", "--sa=two" });
}

test "StringArray set leaks nothing under allocation failure" {
    // Regression: `try slice.append(gpa, try gpa.dupe(u8, v))` leaked the duped
    // string when append failed, because ownership never transferred.
    try std.testing.checkAllAllocationFailures(std.testing.allocator, stringArraySetImpl, .{});
}
