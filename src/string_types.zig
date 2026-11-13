//! String flag type. Maps from pflag/string.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = @import("value.zig").Value;

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

/// DEPRECATED: Use `stringStateValue` instead for safe memory management.
///
/// This legacy form stores the pointer `p` directly without copying.
/// On `set()`, it stores the caller's slice pointer without `gpa.dupe()`.
/// The caller MUST ensure the slice outlives the FlagSet — otherwise
/// dangling pointer. `deinit()` is a no-op (library doesn't own the memory).
/// LEGACY raw-pointer string Value: set() stores the CALLER's slice without
/// duplicating (it must outlive the FlagSet). Prefer `stringStateValue`.
pub fn stringValue(val: []const u8, p: *[]const u8) Value {
    p.* = val;
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = &stringVtableLegacy };
}

/// Library-managed string Value: every set() dupes via `state.gpa`, deinit frees.
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

test "StringVar" {
    const TestCase = struct {
        input: []const []const u8,
        expected: []const u8,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{"--name=Alice"}, .expected = "Alice" },
        .{ .input = &.{ "-n", "Bob" }, .expected = "Bob" },
        .{ .input = &.{"--name="}, .expected = "" },
        .{ .input = &.{"--name=你好世界"}, .expected = "你好世界" },
        .{ .input = &.{"--name=hello world"}, .expected = "hello world" },
    };

    for (testCases) |tc| {
        var name: []const u8 = "";
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.stringVarP(&name, "name", "n", "", "your name");
        try fs.parse(tc.input);
        try std.testing.expectEqualStrings(tc.expected, name);
    }
}

test "StringStateVar copies input on set" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    var name: []const u8 = "";
    var state = pflag.StringState{ .value = &name, .gpa = std.testing.allocator };
    try fs.stringStateVar(&state, "name", "", "");
    try fs.parse(&.{"--name=copied"});
    try std.testing.expectEqualStrings("copied", name);
}

test "StringToStringVar supports CSV format" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var state = pflag.StringToStringState{ .value = &map, .gpa = std.testing.allocator };
    try fs.stringToStringVar(&state, "labels", "", "");
    try fs.parse(&.{"--labels=a=1,b=2,c=3"});
    try std.testing.expectEqual(@as(u32, 3), map.count());
    try std.testing.expectEqualStrings("1", map.get("a").?);
    try std.testing.expectEqualStrings("2", map.get("b").?);
    try std.testing.expectEqualStrings("3", map.get("c").?);
}

test "stringVarOwned managed lifecycle" {
    const TestCase = struct {
        input: []const []const u8,
        expected: []const u8,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{}, .expected = "world" }, // default is duped, kept alive
        .{ .input = &.{"--name=Alice"}, .expected = "Alice" },
        .{ .input = &.{ "-n", "Bob" }, .expected = "Bob" },
        .{ .input = &.{ "--name=", "--name=Dup" }, .expected = "Dup" }, // replace frees old
    };

    for (testCases) |tc| {
        // Args are parsed from individually-owned buffers that get poisoned
        // right after parse: if the bound value were borrowed (legacy-style)
        // the assertion below would read 0xAA garbage instead of `expected`.
        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(std.testing.allocator);
        var owned: std.ArrayListUnmanaged([]u8) = .empty;
        defer {
            for (owned.items) |b| std.testing.allocator.free(b);
            owned.deinit(std.testing.allocator);
        }
        for (tc.input) |arg| {
            const b = try std.testing.allocator.dupe(u8, arg);
            try owned.append(std.testing.allocator, b);
            try argv.append(std.testing.allocator, b);
        }

        var name: []const u8 = "sentinel-not-the-default";
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.stringVarOwnedP(&name, "name", "n", "world", "name to greet");
        try std.testing.expectEqualStrings("world", name); // registration dupes the default
        try fs.parse(argv.items);
        for (owned.items) |b| @memset(b, 0xAA);
        try std.testing.expectEqualStrings(tc.expected, name);
        // fs.deinit + testing.allocator leak-check verify the state shell,
        // the duped default and every duped set() value are all freed.
    }
}

test "stringVarOwned coexists with explicit state and legacy stringVar" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();

    var owned_val: []const u8 = "";
    var state_val: []const u8 = "";
    var legacy_val: []const u8 = "";
    var state = pflag.StringState{ .value = &state_val, .gpa = std.testing.allocator };
    try fs.stringStateVar(&state, "explicit", "d1", "caller-owned state");
    try fs.stringVar(&legacy_val, "legacy", "d2", "borrow-style");
    try fs.stringVarOwned(&owned_val, "managed", "d3", "FlagSet-owned state");

    try fs.parse(&.{ "--explicit=e1", "--legacy=l1", "--managed=m1" });
    try std.testing.expectEqualStrings("e1", state_val);
    try std.testing.expectEqualStrings("l1", legacy_val); // points into the literals above
    try std.testing.expectEqualStrings("m1", owned_val);
    // deinit frees explicit's + managed's dupes; managed's state shell dies
    // via managed_states, explicit's stays caller-owned. Leak checker decides.
}

test "stringVarOwned registration errors leave no trace" {
    const ErrCase = struct {
        name: []const u8,
        shorthand: []const u8,
        expected_err: anyerror,
    };

    // Each case attempts to collide with the seed flag "n"/"z" registered
    // below. The failure lands inside stringStateVarP AFTER the default has
    // already been duped — so every rejection exercises the full errdefer
    // chain: registry pop, dupe free, *p restore.
    const errCases = [_]ErrCase{
        .{ .name = "n", .shorthand = "", .expected_err = error.FlagRedefined },
        .{ .name = "t", .shorthand = "ab", .expected_err = error.ShorthandTooLong },
        .{ .name = "u", .shorthand = "z", .expected_err = error.ShorthandRedefined },
    };

    for (errCases) |ec| {
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        var seed: []const u8 = "";
        try fs.stringVarOwnedP(&seed, "n", "z", "first", "");

        var dup: []const u8 = "orig";
        try std.testing.expectError(ec.expected_err, fs.stringVarOwnedP(&dup, ec.name, ec.shorthand, "v", ""));
        try std.testing.expectEqualStrings("orig", dup); // binding restored
        try std.testing.expectEqual(@as(usize, 1), fs.formal.count()); // nothing leaked into the set
        // deinit + leak checker prove the failed registration left no state
        // behind in managed_states (fs.destroy on a popped/dangling entry would
        // double-free or UAF here).
    }
}

fn ownedRegistrationImpl(gpa: std.mem.Allocator) !void {
    var name: []const u8 = "default";
    var host: []const u8 = "";
    var fs = pflag.FlagSet.init(gpa, "test");
    defer fs.deinit();
    // Mandatory: injected OOM during parse would otherwise hit
    // .exit_on_error and kill the test process with exit(2).
    fs.error_handling = .continue_on_error;
    try fs.stringVarOwned(&name, "name", "default", "an owned string");
    try fs.stringVarOwnedP(&host, "host", "H", "", "empty-string default");
    try fs.parse(&.{ "--name=oom-test", "-H", "localhost" });
}

test "stringVarOwned allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, ownedRegistrationImpl, .{});
}
