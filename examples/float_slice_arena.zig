//! Example: floatSlice (f64) flag with ArenaAllocator.
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var fs = pflag.FlagSet.init(alloc, "float-slice-arena");
    defer fs.deinit();

    var scores: std.ArrayListUnmanaged(f64) = .empty;
    var state = pflag.SliceState(f64){ .value = &scores, .gpa = alloc };
    try fs.floatSliceVar(f64, &state, "score", &.{}, "score values");

    const args = [_][]const u8{ "--score=1.5", "--score=2.7", "--score=3.14" };
    try fs.parse(&args);

    std.debug.assert(scores.items.len == 3);
    std.debug.assert(scores.items[0] == 1.5);
    std.debug.assert(scores.items[1] == 2.7);
std.debug.assert(scores.items[2] == 3.14);
std.debug.print("[float_slice/arena] OK: {d} items: [", .{scores.items.len});
for (scores.items, 0..) |v, i| {
    if (i > 0) std.debug.print(", ", .{});
    std.debug.print("{d}", .{v});
}
std.debug.print("]\n", .{});
}
