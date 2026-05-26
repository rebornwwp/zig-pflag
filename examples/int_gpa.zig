//! Example: int (i32) flag with GeneralPurposeAllocator.
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const alloc = gpa_state.allocator();

    var fs = pflag.FlagSet.init(alloc, "int-gpa");
    defer fs.deinit();

    var count: i32 = 0;
    try fs.intVarP(i32, &count, "count", "c", 0, "a counter");

    const args = [_][]const u8{"--count=99"};
    try fs.parse(&args);

    std.debug.assert(count == 99);
    std.debug.print("[int/gpa] OK: count={d}\n", .{count});
}
