//! Example: string flag with ArenaAllocator.
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var fs = pflag.FlagSet.init(alloc, "string-arena");
    defer fs.deinit();

    var name: []const u8 = "world";
    var state = pflag.StringState{ .value = &name, .gpa = alloc };
    try fs.stringStateVarP(&state, "name", "n", "world", "your name");

    const args = [_][]const u8{"--name=ziggy"};
    try fs.parse(&args);

    std.debug.assert(std.mem.eql(u8, name, "ziggy"));
    std.debug.print("[string/arena] OK: name={s}\n", .{name});
}
