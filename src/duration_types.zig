//! Duration flag type. Maps from pflag/duration.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

const durationVtable = Value.VTable{
    .set = durationSetFn,
    .string = durationStrFn,
    .typeName = struct {
        fn tn() []const u8 {
            return "duration";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            _ = ptr;
            _ = gpa;
        }
    }.di,
};
fn durationSetFn(ptr: *anyopaque, v: []const u8) !void {
    const p: *i64 = @ptrCast(@alignCast(ptr));
    p.* = try parseDuration(v);
}
fn durationStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) anyerror![]const u8 {
    const p: *i64 = @ptrCast(@alignCast(ptr));
    return formatDuration(p.*, gpa);
}

pub fn parseDuration(s: []const u8) !i64 {
    if (s.len < 2) return error.InvalidDuration;

    // Check for multi-character units first (ms, us, ns)
    if (s.len >= 3) {
        const last2 = s[s.len - 2 ..];
        if (std.mem.eql(u8, last2, "ms")) {
            const val = try std.fmt.parseInt(i64, s[0 .. s.len - 2], 10);
            return val * std.time.ns_per_ms;
        }
        if (std.mem.eql(u8, last2, "us")) {
            const val = try std.fmt.parseInt(i64, s[0 .. s.len - 2], 10);
            return val * std.time.ns_per_us;
        }
        if (std.mem.eql(u8, last2, "ns")) {
            const val = try std.fmt.parseInt(i64, s[0 .. s.len - 2], 10);
            return val;
        }
    }

    // Single-character units
    const val_str = s[0 .. s.len - 1];
    const unit = s[s.len - 1];
    const val = try std.fmt.parseInt(i64, val_str, 10);
    return switch (unit) {
        's' => val * std.time.ns_per_s,
        'm' => val * std.time.ns_per_min,
        'h' => val * std.time.ns_per_hour,
        'd' => val * std.time.ns_per_day,
        else => error.InvalidDuration,
    };
}

pub fn formatDuration(ns: i64, gpa: std.mem.Allocator) ![]const u8 {
    if (@rem(ns, std.time.ns_per_day) == 0) return gpa.print("{d}d", .{@divFloor(ns, std.time.ns_per_day)});
    if (@rem(ns, std.time.ns_per_hour) == 0) return gpa.print("{d}h", .{@divFloor(ns, std.time.ns_per_hour)});
    if (@rem(ns, std.time.ns_per_min) == 0) return gpa.print("{d}m", .{@divFloor(ns, std.time.ns_per_min)});
    if (@rem(ns, std.time.ns_per_s) == 0) return gpa.print("{d}s", .{@divFloor(ns, std.time.ns_per_s)});
    if (@rem(ns, std.time.ns_per_ms) == 0) return gpa.print("{d}ms", .{@divFloor(ns, std.time.ns_per_ms)});
    if (@rem(ns, std.time.ns_per_us) == 0) return gpa.print("{d}us", .{@divFloor(ns, std.time.ns_per_us)});
    return gpa.print("{d}ns", .{ns});
}

pub fn durationValue(val: i64, p: *i64) Value {
    p.* = val;
    return .{ .ptr = p, .vtable = &durationVtable };
}


// ── Tests ──

test "DurationVar parses seconds" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=30s"});

    try std.std.testing.expectEqual(30 * std.time.ns_per_s, d);
}

test "DurationVar parses minutes" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=5m"});

    try std.std.testing.expectEqual(5 * std.time.ns_per_min, d);
}

test "DurationVar parses hours" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=2h"});

    try std.std.testing.expectEqual(2 * std.time.ns_per_hour, d);
}

test "DurationVar parses days" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=1d"});

    try std.std.testing.expectEqual(std.time.ns_per_day, d);
}

test "DurationVar parses milliseconds" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=500ms"});

    try std.std.testing.expectEqual(500 * std.time.ns_per_ms, d);
}

test "DurationVar parses microseconds" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=100us"});

    try std.std.testing.expectEqual(100 * std.time.ns_per_us, d);
}

test "DurationVar parses nanoseconds" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=200ns"});

    try std.std.testing.expectEqual(@as(i64, 200), d);
}

test "Invalid duration format returns error" {
    var fs = pflag.FlagSet.init(std.std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var timeout: i64 = 0;
    try fs.durationVar(&timeout, "timeout", 0, "");
    const result = fs.parse(&.{"--timeout=invalid"});
    try std.std.testing.expectError(error.InvalidCharacter, result);
}

