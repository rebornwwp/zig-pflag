//! Example: int (i32) flag with ArenaAllocator.
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var fs = pflag.FlagSet.init(alloc, "int-arena");
    defer fs.deinit();

    var count: i32 = 0;
    try fs.intVarP(i32, &count, "count", "c", 0, "a counter");

    const args = [_][]const u8{"--count=99"};
    try fs.parse(&args);

    std.debug.assert(count == 99);
    std.debug.print("[int/arena] OK: count={d}\n", .{count});
}
