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


// ── Tests ──

test "StringSlice accumulates values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringSliceVar(&state, "tag", &.{}, "");
    try fs.parse(&.{ "--tag=a", "--tag=b", "--tag=c" });

    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.std.std.testing.expectEqualStrings("a", slice.items[0]);
    try std.std.std.testing.expectEqualStrings("b", slice.items[1]);
    try std.std.std.testing.expectEqualStrings("c", slice.items[2]);
}

test "StringSlice with shorthand" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    fs.error_handling = .continue_on_error;
    try fs.stringSliceVarP(&state, "tag", "t", &.{}, "");
    try fs.parse(&.{ "-t", "x", "-t", "y" });

    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
}

test "StringSlice first Set replaces defaults" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringSliceVar(&state, "tag", &.{ "default1", "default2" }, "");
    // Before parse: defaults are populated
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    // After parse: first Set replaces defaults
    try fs.parse(&.{"--tag=gamma"});
    try std.std.testing.expectEqual(@as(usize, 1), slice.items.len);
    try std.std.std.testing.expectEqualStrings("gamma", slice.items[0]);
}

test "StringSlice supports CSV format" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringSliceVar(&state, "tag", &.{}, "");
    try fs.parse(&.{"--tag=a,b,c"});
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.std.std.testing.expectEqualStrings("a", slice.items[0]);
    try std.std.std.testing.expectEqualStrings("b", slice.items[1]);
    try std.std.std.testing.expectEqualStrings("c", slice.items[2]);
}

test "IntSlice accumulates values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i32, &state, "port", &.{}, "");
    try fs.parse(&.{ "--port=80", "--port=443", "--port=8080" });

    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.std.testing.expectEqual(@as(i32, 80), slice.items[0]);
    try std.std.testing.expectEqual(@as(i32, 443), slice.items[1]);
    try std.std.testing.expectEqual(@as(i32, 8080), slice.items[2]);
}

test "UintSlice accumulates values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.uintSliceVar(u32, &state, "port", &.{}, "");
    try fs.parse(&.{ "--port=80", "--port=443", "--port=8080" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.std.testing.expectEqual(@as(u32, 80), slice.items[0]);
    try std.std.testing.expectEqual(@as(u32, 8080), slice.items[2]);
}

test "BoolSlice accumulates values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    try fs.boolSliceVar(&state, "flag", &.{}, "");
    try fs.parse(&.{ "--flag=true", "--flag=false", "--flag" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.testing.expect(slice.items[0]);
    try std.testing.expect(!slice.items[1]);
    try std.testing.expect(slice.items[2]);
}

test "BoolSlice with shorthand" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    try fs.boolSliceVarP(&state, "flag", "f", &.{}, "");
    try fs.parse(&.{ "-f", "-f", "-f" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
}

test "FloatSlice accumulates values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    try fs.floatSliceVar(f64, &state, "rate", &.{}, "");
    try fs.parse(&.{ "--rate=1.5", "--rate=2.5", "--rate=3.14" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.testing.expectApproxEqRel(1.5, slice.items[0], @as(f64, @floatCast(0.0001)));
    try std.testing.expectApproxEqRel(3.14, slice.items[2], @as(f64, @floatCast(0.0001)));
}

test "FloatSlice f32 type" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f32) = .empty;
    var state = pflag.SliceState(f32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.floatSliceVar(f32, &state, "val", &.{}, "");
    try fs.parse(&.{ "--val=0.5", "--val=1.0" });
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
}

test "StringArray accumulates values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringArrayVar(&state, "tag", &.{}, "");
    try fs.parse(&.{ "--tag=a", "--tag=b", "--tag=c" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.std.std.testing.expectEqualStrings("a", slice.items[0]);
}

test "StringArray with default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringArrayVar(&state, "tag", &.{ "alpha", "beta" }, "");
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
}

test "StringArray first Set replaces defaults" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringArrayVar(&state, "tag", &.{ "d1", "d2" }, "");
    // Before parse: defaults are populated
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    // After parse: first Set replaces defaults
    try fs.parse(&.{"--tag=new"});
    try std.std.testing.expectEqual(@as(usize, 1), slice.items.len);
    try std.std.std.testing.expectEqualStrings("new", slice.items[0]);
}

test "Int32Slice empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i32, &state, "is", &.{}, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "Int32Slice parses values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i32, &state, "is", &.{}, "");
    try fs.parse(&.{ "--is=1", "--is=2", "--is=4", "--is=3" });
    try std.std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.std.testing.expectEqual(@as(i32, 1), slice.items[0]);
    try std.std.testing.expectEqual(@as(i32, 2), slice.items[1]);
    try std.std.testing.expectEqual(@as(i32, 4), slice.items[2]);
    try std.std.testing.expectEqual(@as(i32, 3), slice.items[3]);
}

test "Int32Slice default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i32, &state, "is", &.{ @as(i32, 0), @as(i32, 1) }, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.testing.expectEqual(@as(i32, 0), slice.items[0]);
    try std.std.testing.expectEqual(@as(i32, 1), slice.items[1]);
}

test "Int64Slice empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i64) = .empty;
    var state = pflag.SliceState(i64){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i64, &state, "is", &.{}, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "Int64Slice default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i64) = .empty;
    var state = pflag.SliceState(i64){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i64, &state, "is", &.{ @as(i64, 0), @as(i64, 1) }, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.testing.expectEqual(@as(i64, 0), slice.items[0]);
    try std.std.testing.expectEqual(@as(i64, 1), slice.items[1]);
}

test "UintSlice empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.uintSliceVar(u32, &state, "uis", &.{}, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "UintSlice default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.uintSliceVar(u32, &state, "uis", &.{ @as(u32, 0), @as(u32, 1) }, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.testing.expectEqual(@as(u32, 0), slice.items[0]);
    try std.std.testing.expectEqual(@as(u32, 1), slice.items[1]);
}

test "Float32Slice empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f32) = .empty;
    var state = pflag.SliceState(f32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.floatSliceVar(f32, &state, "fs", &.{}, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "Float32Slice default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f32) = .empty;
    var state = pflag.SliceState(f32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.floatSliceVar(f32, &state, "fs", &.{ @as(f32, 0.0), @as(f32, 1.0) }, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.testing.expectEqual(@as(f32, 0.0), slice.items[0]);
    try std.std.testing.expectEqual(@as(f32, 1.0), slice.items[1]);
}

test "Float64Slice empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    try fs.floatSliceVar(f64, &state, "fs", &.{}, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "Float64Slice default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    try fs.floatSliceVar(f64, &state, "fs", &.{ @as(f64, 0.0), @as(f64, 1.0) }, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.testing.expectEqual(@as(f64, 0.0), slice.items[0]);
    try std.std.testing.expectEqual(@as(f64, 1.0), slice.items[1]);
}

test "BoolSlice empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    try fs.boolSliceVar(&state, "bs", &.{}, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "BoolSlice default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    try fs.boolSliceVar(&state, "bs", &.{ false, true }, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.testing.expectEqual(false, slice.items[0]);
    try std.std.testing.expectEqual(true, slice.items[1]);
}

test "StringSlice empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "StringSlice default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringSliceVar(&state, "ss", &.{ "default", "values" }, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.std.testing.expectEqualStrings("default", slice.items[0]);
    try std.std.std.testing.expectEqualStrings("values", slice.items[1]);
}

test "StringSlice with default overridden" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringSliceVar(&state, "ss", &.{ "default", "values" }, "");
    try fs.parse(&.{"--ss=one"});
    // First Set replaces defaults
    try std.std.testing.expectEqual(@as(usize, 1), slice.items.len);
    try std.std.std.testing.expectEqualStrings("one", slice.items[0]);
}

test "StringSlice called twice accumulates" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    try fs.parse(&.{ "--ss=one,two", "--ss=three" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.std.std.testing.expectEqualStrings("one", slice.items[0]);
    try std.std.std.testing.expectEqualStrings("two", slice.items[1]);
    try std.std.std.testing.expectEqualStrings("three", slice.items[2]);
}

test "StringArray empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "StringArray called twice accumulates" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{ "--sa=one,two", "--sa=three" });
    // StringArray does NOT split on commas — each --sa is one element
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.std.testing.expectEqualStrings("one,two", slice.items[0]);
    try std.std.std.testing.expectEqualStrings("three", slice.items[1]);
}

test "StringArray with special characters" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{"--sa=one,two"});
    // StringArray treats the whole value as one element (no CSV split)
    try std.std.testing.expectEqual(@as(usize, 1), slice.items.len);
    try std.std.std.testing.expectEqualStrings("one,two", slice.items[0]);
}

test "StringArray with square brackets" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringArrayVar(&state, "sa", &.{}, "");
    try fs.parse(&.{"--sa=[a-z]"});
    try std.std.testing.expectEqual(@as(usize, 1), slice.items.len);
    try std.std.std.testing.expectEqualStrings("[a-z]", slice.items[0]);
}

test "IntSlice empty parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i32, &state, "is", &.{}, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 0), slice.items.len);
}

test "IntSlice default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i32, &state, "is", &.{ @as(i32, 0), @as(i32, 1) }, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.testing.expectEqual(@as(i32, 0), slice.items[0]);
    try std.std.testing.expectEqual(@as(i32, 1), slice.items[1]);
}

test "Int32Slice parses multiple values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i32, &state, "is", &.{}, "");
    try fs.parse(&.{ "--is=1", "--is=2", "--is=4", "--is=3" });
    try std.std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.std.testing.expectEqual(@as(i32, 1), slice.items[0]);
    try std.std.testing.expectEqual(@as(i32, 2), slice.items[1]);
    try std.std.testing.expectEqual(@as(i32, 4), slice.items[2]);
    try std.std.testing.expectEqual(@as(i32, 3), slice.items[3]);
}

test "Int64Slice parses multiple values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i64) = .empty;
    var state = pflag.SliceState(i64){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i64, &state, "is", &.{}, "");
    try fs.parse(&.{ "--is=100", "--is=200", "--is=300" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.std.testing.expectEqual(@as(i64, 100), slice.items[0]);
    try std.std.testing.expectEqual(@as(i64, 200), slice.items[1]);
    try std.std.testing.expectEqual(@as(i64, 300), slice.items[2]);
}

test "UintSlice parses multiple values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.uintSliceVar(u32, &state, "uis", &.{}, "");
    try fs.parse(&.{ "--uis=10", "--uis=20", "--uis=30" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.std.testing.expectEqual(@as(u32, 10), slice.items[0]);
    try std.std.testing.expectEqual(@as(u32, 20), slice.items[1]);
    try std.std.testing.expectEqual(@as(u32, 30), slice.items[2]);
}

test "Float32Slice parses multiple values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f32) = .empty;
    var state = pflag.SliceState(f32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.floatSliceVar(f32, &state, "fs", &.{}, "");
    try fs.parse(&.{ "--fs=1.5", "--fs=2.5", "--fs=3.5" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), slice.items[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), slice.items[1], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 3.5), slice.items[2], 0.01);
}

test "Float64Slice parses multiple values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = std.testing.allocator };
    try fs.floatSliceVar(f64, &state, "fs", &.{}, "");
    try fs.parse(&.{ "--fs=1.1", "--fs=2.2", "--fs=3.3" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.testing.expectApproxEqAbs(@as(f64, 1.1), slice.items[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 2.2), slice.items[1], 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 3.3), slice.items[2], 0.01);
}

test "BoolSlice parses multiple values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = std.testing.allocator };
    try fs.boolSliceVar(&state, "bs", &.{}, "");
    try fs.parse(&.{ "--bs=true", "--bs=false", "--bs=1", "--bs=0" });
    try std.std.testing.expectEqual(@as(usize, 4), slice.items.len);
    try std.std.testing.expectEqual(true, slice.items[0]);
    try std.std.testing.expectEqual(false, slice.items[1]);
    try std.std.testing.expectEqual(true, slice.items[2]);
    try std.std.testing.expectEqual(false, slice.items[3]);
}

test "IntSlice parses multiple values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = std.testing.allocator };
    try fs.intSliceVar(i32, &state, "is", &.{}, "");
    try fs.parse(&.{ "--is=10", "--is=20", "--is=30" });
    try std.std.testing.expectEqual(@as(usize, 3), slice.items.len);
    try std.std.testing.expectEqual(@as(i32, 10), slice.items[0]);
    try std.std.testing.expectEqual(@as(i32, 20), slice.items[1]);
    try std.std.testing.expectEqual(@as(i32, 30), slice.items[2]);
}

test "StringSlice with comma in value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    try fs.parse(&.{"--ss=one,two"});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.std.testing.expectEqualStrings("one", slice.items[0]);
    try std.std.std.testing.expectEqualStrings("two", slice.items[1]);
}

test "StringSlice with square brackets" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringSliceVar(&state, "ss", &.{}, "");
    try fs.parse(&.{ "--ss=[a-z]", "--ss=[0-9]" });
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.std.testing.expectEqualStrings("[a-z]", slice.items[0]);
    try std.std.std.testing.expectEqualStrings("[0-9]", slice.items[1]);
}

test "StringArray default values" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringArrayVar(&state, "sa", &.{ "default1", "default2" }, "");
    try fs.parse(&.{});
    try std.std.testing.expectEqual(@as(usize, 2), slice.items.len);
    try std.std.std.testing.expectEqualStrings("default1", slice.items[0]);
    try std.std.std.testing.expectEqualStrings("default2", slice.items[1]);
}

test "StringArray with default overridden" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = std.testing.allocator };
    try fs.stringArrayVar(&state, "sa", &.{ "default1", "default2" }, "");
    try fs.parse(&.{"--sa=new"});
    try std.std.testing.expectEqual(@as(usize, 1), slice.items.len);
    try std.std.std.testing.expectEqualStrings("new", slice.items[0]);
}

