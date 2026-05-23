//! Map flag types. Maps from pflag/string_to_*.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

// ─── String → Int ───

const strToIntVtable = Value.VTable{
    .set = struct {
        fn set(ptr: *anyopaque, v: []const u8) !void {
            const map: *std.StringHashMapUnmanaged(i32) = @ptrCast(@alignCast(ptr));
            const eq = std.mem.indexOfScalar(u8, v, '=') orelse return error.ExpectedKeyValue;
            const key = v[0..eq];
            const val_str = v[eq + 1 ..];
            const val = try std.fmt.parseInt(i32, val_str, 0);
            try map.put(std.heap.page_allocator, key, val);
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
            const map: *std.StringHashMapUnmanaged(i32) = @ptrCast(@alignCast(ptr));
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            var it = map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) buf.appendSlice(gpa, ", ") catch break;
                first = false;
                var tmp: [64]u8 = undefined;
                buf.appendSlice(gpa, entry.key_ptr.*) catch break;
                buf.appendSlice(gpa, "=") catch break;
                buf.appendSlice(gpa, std.fmt.bufPrint(&tmp, "{d}", .{entry.value_ptr.*}) catch "?") catch break;
            }
            return buf.toOwnedSlice(gpa) catch return "[]";
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "stringToInt";
        }
    }.tn,
};

pub fn stringToIntValue(p: *std.StringHashMapUnmanaged(i32)) Value {
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = &strToIntVtable };
}

// ─── String → String ───

const strToStrVtable = Value.VTable{
    .set = struct {
        fn set(ptr: *anyopaque, v: []const u8) !void {
            const map: *std.StringHashMapUnmanaged([]const u8) = @ptrCast(@alignCast(ptr));
            const eq = std.mem.indexOfScalar(u8, v, '=') orelse return error.ExpectedKeyValue;
            const key = v[0..eq];
            const val = v[eq + 1 ..];
            try map.put(std.heap.page_allocator, key, std.heap.page_allocator.dupe(u8, val) catch return);
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
            const map: *std.StringHashMapUnmanaged([]const u8) = @ptrCast(@alignCast(ptr));
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            var it = map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) buf.appendSlice(gpa, ", ") catch break;
                first = false;
                buf.appendSlice(gpa, entry.key_ptr.*) catch break;
                buf.appendSlice(gpa, "=") catch break;
                buf.appendSlice(gpa, entry.value_ptr.*) catch break;
            }
            return buf.toOwnedSlice(gpa) catch return "[]";
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "stringToString";
        }
    }.tn,
};

pub fn stringToStringValue(p: *std.StringHashMapUnmanaged([]const u8)) Value {
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = &strToStrVtable };
}
