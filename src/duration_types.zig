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
};
fn durationSetFn(ptr: *anyopaque, v: []const u8) !void {
    const p: *i64 = @ptrCast(@alignCast(ptr));
    p.* = try parseDuration(v);
}
fn durationStrFn(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
    const p: *i64 = @ptrCast(@alignCast(ptr));
    return std.fmt.allocPrint(gpa, "{d}s", .{@divFloor(p.*, std.time.ns_per_s)}) catch "?";
}

pub fn parseDuration(s: []const u8) !i64 {
    if (s.len < 2) return error.InvalidDuration;
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
    if (ns % std.time.ns_per_day == 0) return std.fmt.allocPrint(gpa, "{d}d", .{@divFloor(ns, std.time.ns_per_day)});
    if (ns % std.time.ns_per_hour == 0) return std.fmt.allocPrint(gpa, "{d}h", .{@divFloor(ns, std.time.ns_per_hour)});
    if (ns % std.time.ns_per_min == 0) return std.fmt.allocPrint(gpa, "{d}m", .{@divFloor(ns, std.time.ns_per_min)});
    return std.fmt.allocPrint(gpa, "{d}s", .{@divFloor(ns, std.time.ns_per_s)});
}

pub fn durationValue(val: i64, p: *i64) Value {
    p.* = val;
    return .{ .ptr = p, .vtable = &durationVtable };
}
