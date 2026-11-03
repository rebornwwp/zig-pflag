//! String flag type. Maps from pflag/string.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

/// Wrapper struct to track allocator for string values.
/// Ensures set() duplicates the input so it doesn't dangle.
/// The value pointed to must always be heap-allocated (or empty with allocated=false).
///
/// allocated flag: tracks whether the current value was created by the library
/// via gpa.dupe(). Default values (string literals, stack buffers) are NOT owned
/// by the library, so deinit() only frees the value when allocated == true.
/// set() transitions allocated=true after the first successful dupe and frees
/// the old value if it was previously allocated, preventing leaks on re-parse.
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
            const state: *StringState = @ptrCast(@alignCast(ptr));
            if (state.allocated) {
                gpa.free(state.value.*);
            }
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


// ── Tests ──

test "StringVar and parse" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVar(&name, "name", "default", "your name");
    try fs.parse(&.{"--name=Alice"});
    try std.std.std.testing.expectEqualStrings("Alice", name);
}

test "StringVar shorthand" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVarP(&name, "name", "n", "default", "your name");
    try fs.parse(&.{ "-n", "Bob" });
    try std.std.std.testing.expectEqualStrings("Bob", name);
}

test "StringToStringVar supports CSV format" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToStringVar(&state, "labels", "", "");
    try fs.parse(&.{"--labels=a=1,b=2,c=3"});
    try std.std.testing.expectEqual(@as(u32, 3), map.count());
    try std.std.std.testing.expectEqualStrings("1", map.get("a").?);
    try std.std.std.testing.expectEqualStrings("2", map.get("b").?);
    try std.std.std.testing.expectEqualStrings("3", map.get("c").?);
}

test "StringStateVar copies input on set" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var name: []const u8 = "";
    var state = pflag.StringState{ .value = &name, .gpa = std.testing.allocator };
    try fs.stringStateVar(&state, "name", "", "");
    try fs.parse(&.{"--name=copied"});
    try std.std.std.testing.expectEqualStrings("copied", name);
}

test "Empty string value is valid" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var name: []const u8 = "default";
    try fs.stringVar(&name, "name", "default", "");
    try fs.parse(&.{"--name="});
    try std.std.std.testing.expectEqualStrings("", name);
}

test "Unicode string value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVar(&name, "name", "", "");
    try fs.parse(&.{"--name=你好世界"});
    try std.std.std.testing.expectEqualStrings("你好世界", name);
}

test "String with spaces" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVar(&name, "name", "", "");
    try fs.parse(&.{"--name=hello world"});
    try std.std.std.testing.expectEqualStrings("hello world", name);
}

