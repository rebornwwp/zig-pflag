//! Example: int (i32) flag with FixedBufferAllocator.
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    var buf: [16384]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    var fs = pflag.FlagSet.init(alloc, "int-fba");
    defer fs.deinit();

    var count: i32 = 0;
    try fs.intVarP(i32, &count, "count", "c", 0, "a counter");

    const args = [_][]const u8{ "--count=99" };
    try fs.parse(&args);

    std.debug.assert(count == 99);
    std.debug.print("[int/fba] OK: count={d}\n", .{count});
}
