//! Slice flag types. Maps from pflag/*_slice.go, string_array.go v1.0.9.

const std = @import("std");
const pflag = @import("pflag.zig");
const Value = pflag.Value;

// ─── String Slice ───

const stringSliceVtable = Value.VTable{
    .set = struct {
        fn set(ptr: *anyopaque, v: []const u8) !void {
            const slice: *std.ArrayListUnmanaged([]const u8) = @ptrCast(@alignCast(ptr));
            slice.append(std.heap.page_allocator, std.heap.page_allocator.dupe(u8, v) catch return) catch return;
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
            const slice: *std.ArrayListUnmanaged([]const u8) = @ptrCast(@alignCast(ptr));
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            for (slice.items, 0..) |s, i| {
                if (i > 0) buf.appendSlice(gpa, ", ") catch break;
                buf.appendSlice(gpa, s) catch break;
            }
            return buf.toOwnedSlice(gpa) catch return "[strings]";
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "strings";
        }
    }.tn,
};

pub fn stringSliceValue(p: *std.ArrayListUnmanaged([]const u8)) Value {
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = &stringSliceVtable };
}

// ─── String Array ───
// Like stringSlice but Replace/GetSlice are separate. In Zig, we unify.

const stringArrayVtable = Value.VTable{
    .set = struct {
        fn set(ptr: *anyopaque, v: []const u8) !void {
            const slice: *std.ArrayListUnmanaged([]const u8) = @ptrCast(@alignCast(ptr));
            slice.append(std.heap.page_allocator, std.heap.page_allocator.dupe(u8, v) catch return) catch return;
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
            const slice: *std.ArrayListUnmanaged([]const u8) = @ptrCast(@alignCast(ptr));
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            for (slice.items, 0..) |s, i| {
                if (i > 0) buf.appendSlice(gpa, ",") catch break;
                buf.appendSlice(gpa, s) catch break;
            }
            return buf.toOwnedSlice(gpa) catch return "[]";
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "stringArray";
        }
    }.tn,
};

pub fn stringArrayValue(p: *std.ArrayListUnmanaged([]const u8)) Value {
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = &stringArrayVtable };
}

// ─── Int Slice ───

fn intSliceVtable(comptime T: type) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                const slice: *std.ArrayListUnmanaged(T) = @ptrCast(@alignCast(ptr));
                slice.append(std.heap.page_allocator, try std.fmt.parseInt(T, v, 0)) catch return;
            }
        }.set,
        .string = struct {
            fn string(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
                const slice: *std.ArrayListUnmanaged(T) = @ptrCast(@alignCast(ptr));
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                for (slice.items, 0..) |v, i| {
                    if (i > 0) buf.appendSlice(gpa, ", ") catch break;
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch "?";
                    buf.appendSlice(gpa, s) catch break;
                }
                return buf.toOwnedSlice(gpa) catch return "[ints]";
            }
        }.string,
        .typeName = struct {
            fn tn() []const u8 {
                return @typeName(T) ++ "s";
            }
        }.tn,
    };
}
const i32SliceVtable = intSliceVtable(i32);
const i64SliceVtable = intSliceVtable(i64);

pub fn intSliceValue(comptime T: type, p: *std.ArrayListUnmanaged(T)) Value {
    const vt: *const Value.VTable = switch (T) {
        i32 => &i32SliceVtable,
        i64 => &i64SliceVtable,
        else => @compileError("Unsupported int slice type: " ++ @typeName(T)),
    };
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = vt };
}

// ─── Uint Slice ───

fn uintSliceVtable(comptime T: type) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                const slice: *std.ArrayListUnmanaged(T) = @ptrCast(@alignCast(ptr));
                slice.append(std.heap.page_allocator, try std.fmt.parseInt(T, v, 0)) catch return;
            }
        }.set,
        .string = struct {
            fn string(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
                const slice: *std.ArrayListUnmanaged(T) = @ptrCast(@alignCast(ptr));
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                for (slice.items, 0..) |v, i| {
                    if (i > 0) buf.appendSlice(gpa, ", ") catch break;
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch "?";
                    buf.appendSlice(gpa, s) catch break;
                }
                return buf.toOwnedSlice(gpa) catch return "[uints]";
            }
        }.string,
        .typeName = struct {
            fn tn() []const u8 {
                return @typeName(T) ++ "s";
            }
        }.tn,
    };
}
const u8SliceVtable = uintSliceVtable(u8);
const u16SliceVtable = uintSliceVtable(u16);
const u32SliceVtable = uintSliceVtable(u32);
const u64SliceVtable = uintSliceVtable(u64);

pub fn uintSliceValue(comptime T: type, p: *std.ArrayListUnmanaged(T)) Value {
    const vt: *const Value.VTable = switch (T) {
        u8 => &u8SliceVtable,
        u16 => &u16SliceVtable,
        u32 => &u32SliceVtable,
        u64 => &u64SliceVtable,
        else => @compileError("Unsupported uint slice type: " ++ @typeName(T)),
    };
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = vt };
}

// ─── Bool Slice ───

const boolSliceVtable = Value.VTable{
    .set = struct {
        fn set(ptr: *anyopaque, v: []const u8) !void {
            const slice: *std.ArrayListUnmanaged(bool) = @ptrCast(@alignCast(ptr));
            const b = if (std.mem.eql(u8, v, "true") or std.mem.eql(u8, v, "1") or v.len == 0) true else if (std.mem.eql(u8, v, "false") or std.mem.eql(u8, v, "0")) false else return error.InvalidBoolValue;
            slice.append(std.heap.page_allocator, b) catch return;
        }
    }.set,
    .string = struct {
        fn string(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
            const slice: *std.ArrayListUnmanaged(bool) = @ptrCast(@alignCast(ptr));
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            for (slice.items, 0..) |v, i| {
                if (i > 0) buf.appendSlice(gpa, ", ") catch break;
                buf.appendSlice(gpa, if (v) "true" else "false") catch break;
            }
            return buf.toOwnedSlice(gpa) catch return "[bools]";
        }
    }.string,
    .typeName = struct {
        fn tn() []const u8 {
            return "bools";
        }
    }.tn,
};

pub fn boolSliceValue(p: *std.ArrayListUnmanaged(bool)) Value {
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = &boolSliceVtable };
}

// ─── Float Slice ───

fn floatSliceVtable(comptime T: type) Value.VTable {
    return .{
        .set = struct {
            fn set(ptr: *anyopaque, v: []const u8) !void {
                const slice: *std.ArrayListUnmanaged(T) = @ptrCast(@alignCast(ptr));
                slice.append(std.heap.page_allocator, try std.fmt.parseFloat(T, v)) catch return;
            }
        }.set,
        .string = struct {
            fn string(ptr: *anyopaque, gpa: std.mem.Allocator) []const u8 {
                const slice: *std.ArrayListUnmanaged(T) = @ptrCast(@alignCast(ptr));
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                for (slice.items, 0..) |v, i| {
                    if (i > 0) buf.appendSlice(gpa, ", ") catch break;
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch "?";
                    buf.appendSlice(gpa, s) catch break;
                }
                return buf.toOwnedSlice(gpa) catch return "[floats]";
            }
        }.string,
        .typeName = struct {
            fn tn() []const u8 {
                return @typeName(T) ++ "s";
            }
        }.tn,
    };
}
const f32SliceVtable = floatSliceVtable(f32);
const f64SliceVtable = floatSliceVtable(f64);

pub fn floatSliceValue(comptime T: type, p: *std.ArrayListUnmanaged(T)) Value {
    const vt: *const Value.VTable = switch (T) {
        f32 => &f32SliceVtable,
        f64 => &f64SliceVtable,
        else => @compileError("Unsupported float slice type: " ++ @typeName(T)),
    };
    return .{ .ptr = @ptrCast(@alignCast(p)), .vtable = vt };
}
