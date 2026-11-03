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

test "CountVar" {
    const TestCase = struct {
        input: []const []const u8,
        success: bool,
        expected: i32,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{}, .success = true, .expected = 0 },
        .{ .input = &.{"-v"}, .success = true, .expected = 1 },
        .{ .input = &.{"-vvv"}, .success = true, .expected = 3 },
        .{ .input = &.{ "-v", "-v", "-v" }, .success = true, .expected = 3 },
        .{ .input = &.{ "-v", "--verbose", "-v" }, .success = true, .expected = 3 },
        .{ .input = &.{ "-v=3", "-v" }, .success = true, .expected = 4 },
        .{ .input = &.{"--verbose=0"}, .success = true, .expected = 0 },
        .{ .input = &.{"-v=0"}, .success = true, .expected = 0 },
        .{ .input = &.{"-v=a"}, .success = false, .expected = 0 },
    };

    for (testCases, 0..) |tc, i| {
        var c: i32 = 0;
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        fs.error_handling = .continue_on_error;
        try fs.countVarP(&c, "verbose", "v", 0, "a counter");

        const result = fs.parse(tc.input);

        if (tc.success) {
            if (result) |_| {
                try std.testing.expectEqual(tc.expected, c);
            } else |err| {
                std.debug.print("Test case {d}: expected success, got error {}\n", .{ i, err });
                return err;
            }
        } else {
            if (result) |_| {
                std.debug.print("Test case {d}: expected failure, got success\n", .{i});
                return error.TestExpectedError;
            } else |_| {
                // Expected failure
            }
        }
    }
}

