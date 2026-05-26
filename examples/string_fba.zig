//! Example: string flag with FixedBufferAllocator.
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    var buf: [16384]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    var fs = pflag.FlagSet.init(alloc, "string-fba");
    defer fs.deinit();

    var name: []const u8 = "world";
    var state = pflag.StringState{ .value = &name, .gpa = alloc };
    try fs.stringStateVarP(&state, "name", "n", "world", "your name");

    const args = [_][]const u8{ "--name=ziggy" };
    try fs.parse(&args);

    std.debug.assert(std.mem.eql(u8, name, "ziggy"));
    std.debug.print("[string/fba] OK: name={s}\n", .{name});
}
