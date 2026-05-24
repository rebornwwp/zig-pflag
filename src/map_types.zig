//! Map flag types. Maps from pflag/string_to_*.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

// ─── String → Int (comptime-generic: i8-i64, u8-u64) ───

fn strToIntVtableGen(comptime T: type) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                const map: *std.StringHashMapUnmanaged(T) = @ptrCast(@alignCast(ptr));
                const eq = std.mem.indexOfScalar(u8, v, '=') orelse return error.ExpectedKeyValue;
                const key = v[0..eq];
                const val_str = v[eq + 1 ..];
                const val = try std.fmt.parseInt(T, val_str, 0);
                try map.put(std.heap.page_allocator, key, val);
            }
        }.set,
        .string = struct {
            fn string(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
                const map: *std.StringHashMapUnmanaged(T) = @ptrCast(@alignCast(ptr));
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
                return "stringTo" ++ @typeName(T);
            }
        }.tn,
        .deinit = struct {
            fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
                _ = ptr;
                _ = gpa;
            }
        }.di,
    };
}

const strToI32Vtable = strToIntVtableGen(i32);
const strToI64Vtable = strToIntVtableGen(i64);
const strToU32Vtable = strToIntVtableGen(u32);
const strToU64Vtable = strToIntVtableGen(u64);

pub fn stringToIntValue(comptime T: type, p: *std.StringHashMapUnmanaged(T)) Value {
    const vt: *const Value.VTable = switch (T) {
        i32 => &strToI32Vtable,
        i64 => &strToI64Vtable,
        u32 => &strToU32Vtable,
        u64 => &strToU64Vtable,
        else => @compileError("Unsupported stringToInt type: " ++ @typeName(T)),
    };
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = vt };
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
            return buf.toOwnedSlice(gpa) catch return "{}";
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "stringToString";
        }
    }.tn,
    .deinit = struct {
        fn di(ptr: *anyopaque, gpa: std.mem.Allocator) void {
            _ = ptr;
            _ = gpa;
        }
    }.di,
};

pub fn stringToStringValue(p: *std.StringHashMapUnmanaged([]const u8)) Value {
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = &strToStrVtable };
}
