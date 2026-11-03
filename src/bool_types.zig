//! Bool flag type. Maps from pflag/bool.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

const boolVtable = Value.VTable{
    .set = boolSetFn,
    .string = boolStrFn,
    .typeName = boolTypeNameFn,
    .deinit = boolDeinitFn,
};
fn boolSetFn(ptr: *anyopaque, v: []const u8) !void {
    const p: *bool = @ptrCast(@alignCast(ptr));
    p.* = try parseBool(v);
}

/// Go-compatible bool parsing: accepts true/false, TRUE/FALSE, True/False,
/// T/F, t/f, 1/0, and empty string (treated as true).
pub fn parseBool(v: []const u8) !bool {
    if (v.len == 0) return true;
    if (equalsIgnoreCase(v, "true") or equalsIgnoreCase(v, "t") or std.mem.eql(u8, v, "1")) return true;
    if (equalsIgnoreCase(v, "false") or equalsIgnoreCase(v, "f") or std.mem.eql(u8, v, "0")) return false;
    return error.InvalidBoolValue;
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (toLower(ca) != toLower(cb)) return false;
    }
    return true;
}

fn toLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn boolStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
    const val = (@as(*bool, @ptrCast(@alignCast(ptr)))).*;
    return gpa.dupe(u8, if (val) "true" else "false");
}
fn boolTypeNameFn() []const u8 {
    return "bool";
}
fn boolDeinitFn(ptr: *anyopaque, gpa: std.mem.Allocator) void {
    _ = ptr;
    _ = gpa;
}

pub fn boolValue(val: bool, p: *bool) Value {
    p.* = val;
    return .{ .ptr = p, .vtable = &boolVtable };
}


// ── Tests ──

test "BoolVar and parse true" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var flag_val: bool = false;
    try fs.boolVar(&flag_val, "verbose", false, "enable verbose");
    try fs.parse(&.{"--verbose"});
    try std.testing.expect(flag_val);
    try std.std.testing.expectEqual(@as(usize, 0), fs.nArg());
}

test "BoolVar parse explicit true/false" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var a: bool = false;
    var b: bool = true;
    try fs.boolVar(&a, "a", false, "");
    try fs.boolVar(&b, "b", true, "");
    try fs.parse(&.{ "--a=true", "--b=false" });
    try std.testing.expect(a);
    try std.testing.expect(!b);
}

test "BoolVar shorthand" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var flag_val: bool = false;
    try fs.boolVarP(&flag_val, "verbose", "v", false, "verbose mode");
    try fs.parse(&.{"-v"});
    try std.testing.expect(flag_val);
}

test "BoolVar accepts 0 and 1" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var a: bool = true;
    var b: bool = false;
    try fs.boolVar(&a, "a", true, "");
    try fs.boolVar(&b, "b", false, "");
    try fs.parse(&.{ "--a=0", "--b=1" });
    try std.testing.expect(!a);
    try std.testing.expect(b);
}

test "BoolVar accepts Go-compatible forms" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var a: bool = false;
    var b: bool = true;
    var c: bool = false;
    var d: bool = true;
    try fs.boolVar(&a, "a", false, "");
    try fs.boolVar(&b, "b", true, "");
    try fs.boolVar(&c, "c", false, "");
    try fs.boolVar(&d, "d", true, "");
    try fs.parse(&.{ "--a=TRUE", "--b=FALSE", "--c=True", "--d=False" });
    try std.testing.expect(a);
    try std.testing.expect(!b);
    try std.testing.expect(c);
    try std.testing.expect(!d);
}

test "BoolVar accepts T and F shorthand forms" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var a: bool = false;
    var b: bool = true;
    try fs.boolVar(&a, "a", false, "");
    try fs.boolVar(&b, "b", true, "");
    try fs.parse(&.{ "--a=t", "--b=f" });
    try std.testing.expect(a);
    try std.testing.expect(!b);
}

test "Invalid bool value returns error" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var verbose: bool = false;
    try fs.boolVar(&verbose, "verbose", false, "");
    const result = fs.parse(&.{"--verbose=maybe"});
    try std.std.testing.expectError(error.InvalidBoolValue, result);
}

test "BoolP with shorthand" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var flag: bool = false;
    try fs.boolVarP(&flag, "bool", "b", false, "bool value");
    try fs.parse(&.{"-b"});
    try std.testing.expect(flag);
}

test "BoolP explicit true" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var flag: bool = false;
    try fs.boolVarP(&flag, "bool", "b", false, "");
    try fs.parse(&.{"--bool=true"});
    try std.testing.expect(flag);
}

test "BoolP explicit false" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var flag: bool = true;
    try fs.boolVarP(&flag, "bool", "b", true, "");
    try fs.parse(&.{"--bool=false"});
    try std.testing.expect(!flag);
}

