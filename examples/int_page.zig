//! Example: int (i32) flag with page_allocator.
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var fs = pflag.FlagSet.init(alloc, "int-page");
    defer fs.deinit();

    var count: i32 = 0;
    try fs.intVarP(i32, &count, "count", "c", 0, "a counter");

    const args = [_][]const u8{"--count=99"};
    try fs.parse(&args);

    std.debug.assert(count == 99);
    std.debug.print("[int/page] OK: count={d}\n", .{count});
}
