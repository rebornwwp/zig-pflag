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
        else => error.UnknownDurationUnit,
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

test "DurationVar" {
    const TestCase = struct {
        input: []const u8,
        expected: i64,
    };

    const testCases = [_]TestCase{
        .{ .input = "30s", .expected = 30 * std.time.ns_per_s },
        .{ .input = "5m", .expected = 5 * std.time.ns_per_min },
        .{ .input = "2h", .expected = 2 * std.time.ns_per_hour },
        .{ .input = "1d", .expected = std.time.ns_per_day },
        .{ .input = "500ms", .expected = 500 * std.time.ns_per_ms },
        .{ .input = "100us", .expected = 100 * std.time.ns_per_us },
        .{ .input = "200ns", .expected = 200 },
    };

    for (testCases) |tc| {
        var d: i64 = 0;
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.durationVar(&d, "timeout", 0, "");
        const arg = try std.fmt.allocPrint(std.testing.allocator, "--timeout={s}", .{tc.input});
        defer std.testing.allocator.free(arg);
        try fs.parse(&.{arg});
        try std.testing.expectEqual(tc.expected, d);
    }
}

test "DurationVar invalid format returns error" {
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var timeout: i64 = 0;
    try fs.durationVar(&timeout, "timeout", 0, "");
    try std.testing.expectError(error.InvalidCharacter, fs.parse(&.{"--timeout=invalid"}));
}

test "DurationVar unknown unit returns error" {
    // Regression: previously returned InvalidDuration for unknown units.
    // Now returns UnknownDurationUnit for clarity.
    var fs = pflag.FlagSet.init(std.testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var timeout: i64 = 0;
    try fs.durationVar(&timeout, "timeout", 0, "");
    try std.testing.expectError(error.UnknownDurationUnit, fs.parse(&.{"--timeout=5x"}));
}
