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
    const testing = std.testing;
    
    // Test 1: increments on each use (-v -v -v)
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        fs.error_handling = .continue_on_error;
        var c: i32 = 0;
        try fs.countVarP(&c, "verbose", "v", 0, "verbosity level");
        try fs.parse(&.{ "-v", "-v", "-v" });
        try testing.expectEqual(@as(i32, 3), c);
    }
    
    // Test 2: explicit value (--count=5)
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        var c: i32 = 0;
        try fs.countVar(&c, "count", 0, "");
        try fs.parse(&.{"--count=5"});
        try testing.expectEqual(@as(i32, 5), c);
    }
    
    // Test 3: default value with increment (--count with default 10)
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        var c: i32 = 10;
        try fs.countVar(&c, "count", 10, "");
        try fs.parse(&.{"--count"});
        try testing.expectEqual(@as(i32, 11), c);
    }
    
    // Test 4: explicit value assigns not accumulates
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        var c: i32 = 10;
        try fs.countVar(&c, "count", 10, "");
        try fs.parse(&.{"--count=5"});
        try testing.expectEqual(@as(i32, 5), c); // Should be 5 (assigned), not 15 (accumulated)
    }
    
    // Test 5: empty args keeps default
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        var c: i32 = 0;
        try fs.countVarP(&c, "verbose", "v", 0, "");
        try fs.parse(&.{});
        try testing.expectEqual(@as(i32, 0), c);
    }
    
    // Test 6: single short flag (-v)
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        var c: i32 = 0;
        try fs.countVarP(&c, "verbose", "v", 0, "");
        try fs.parse(&.{"-v"});
        try testing.expectEqual(@as(i32, 1), c);
    }
    
    // Test 7: combined short flags (-vvv)
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        var c: i32 = 0;
        try fs.countVarP(&c, "verbose", "v", 0, "");
        try fs.parse(&.{"-vvv"});
        try testing.expectEqual(@as(i32, 3), c);
    }
    
    // Test 8: mixed long and short flags (-v --verbose -v)
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        fs.error_handling = .continue_on_error;
        var c: i32 = 0;
        try fs.countVarP(&c, "verbose", "v", 0, "");
        try fs.parse(&.{ "-v", "--verbose", "-v" });
        try testing.expectEqual(@as(i32, 3), c);
    }
    
    // Test 9: explicit value with short flag (-v=0)
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        var c: i32 = 0;
        try fs.countVarP(&c, "verbose", "v", 0, "");
        try fs.parse(&.{"-v=0"});
        try testing.expectEqual(@as(i32, 0), c);
    }
    
    // Test 10: invalid value returns error (-v=a)
    {
        var fs = pflag.FlagSet.init(testing.allocator, "test");
        defer fs.deinit();
        fs.error_handling = .continue_on_error;
        var c: i32 = 0;
        try fs.countVarP(&c, "verbose", "v", 0, "");
        try testing.expectError(error.InvalidCharacter, fs.parse(&.{"-v=a"}));
    }
}

