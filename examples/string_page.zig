//! Example: string flag with page_allocator.
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var fs = pflag.FlagSet.init(alloc, "string-page");
    defer fs.deinit();

    var name: []const u8 = "world";
    var state = pflag.StringState{ .value = &name, .gpa = alloc };
    try fs.stringStateVarP(&state, "name", "n", "world", "your name");

    const args = [_][]const u8{"--name=ziggy"};
    try fs.parse(&args);

    std.debug.assert(std.mem.eql(u8, name, "ziggy"));
    std.debug.print("[string/page] OK: name={s}\n", .{name});
}
