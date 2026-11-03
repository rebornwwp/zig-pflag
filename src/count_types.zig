//! Count flag type. Maps from pflag/count.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

const countVtable = Value.VTable{
    .set = countSetFn,
    .string = countStrFn,
    .typeName = struct {
        fn tn() []const u8 {
            return "count";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            _ = ptr;
            _ = gpa;
        }
    }.di,
};
fn countSetFn(ptr: *anyopaque, v: []const u8) !void {
    const p: *i32 = @ptrCast(@alignCast(ptr));
    // "+1" means no specific value was passed (shorthand without value), so increment
    if (std.mem.eql(u8, v, "+1")) {
        p.* += 1;
        return;
    }
    // Otherwise, parse and assign the value
    const n = try std.fmt.parseInt(i32, v, 0);
    p.* = n;
}
fn countStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
    const p: *i32 = @ptrCast(@alignCast(ptr));
    return gpa.print("{d}", .{p.*});
}

pub fn countValue(val: i32, p: *i32) Value {
    p.* = val;
    return .{ .ptr = p, .vtable = &countVtable };
}


// ── Tests ──

test "CountVar increments on each use" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var c: i32 = 0;
    try fs.countVarP(&c, "verbose", "v", 0, "verbosity level");
    try fs.parse(&.{ "-v", "-v", "-v" });

    try std.std.testing.expectEqual(@as(i32, 3), c);
}

test "CountVar with value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var c: i32 = 0;
    try fs.countVar(&c, "count", 0, "");
    try fs.parse(&.{"--count=5"});

    try std.std.testing.expectEqual(@as(i32, 5), c);
}

test "CountVar default value" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var c: i32 = 10;
    try fs.countVar(&c, "count", 10, "");
    try fs.parse(&.{"--count"});

    try std.std.testing.expectEqual(@as(i32, 11), c);
}

test "CountVar explicit value assigns not accumulates" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var c: i32 = 10;
    try fs.countVar(&c, "count", 10, "");
    try fs.parse(&.{"--count=5"});

    // Should be 5 (assigned), not 15 (accumulated)
    try std.std.testing.expectEqual(@as(i32, 5), c);
}

test "CountVar empty args keeps default" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var c: i32 = 0;
    try fs.countVarP(&c, "verbose", "v", 0, "");
    try fs.parse(&.{});

    try std.std.testing.expectEqual(@as(i32, 0), c);
}

test "CountVar single short flag" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var c: i32 = 0;
    try fs.countVarP(&c, "verbose", "v", 0, "");
    try fs.parse(&.{"-v"});

    try std.std.testing.expectEqual(@as(i32, 1), c);
}

test "CountVar combined short flags -vvv" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var c: i32 = 0;
    try fs.countVarP(&c, "verbose", "v", 0, "");
    try fs.parse(&.{"-vvv"});

    try std.std.testing.expectEqual(@as(i32, 3), c);
}

test "CountVar mixed long and short flags" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var c: i32 = 0;
    try fs.countVarP(&c, "verbose", "v", 0, "");
    try fs.parse(&.{ "-v", "--verbose", "-v" });

    try std.std.testing.expectEqual(@as(i32, 3), c);
}

test "CountVar explicit value with short flag -v=0" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var c: i32 = 0;
    try fs.countVarP(&c, "verbose", "v", 0, "");
    try fs.parse(&.{"-v=0"});

    try std.std.testing.expectEqual(@as(i32, 0), c);
}

test "CountVar invalid value returns error" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var c: i32 = 0;
    try fs.countVarP(&c, "verbose", "v", 0, "");
    try std.std.testing.expectError(error.InvalidCharacter, fs.parse(&.{"-v=a"}));
}

