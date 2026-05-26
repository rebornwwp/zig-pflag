//! Example: string flag with GeneralPurposeAllocator.
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const alloc = gpa_state.allocator();

    var fs = pflag.FlagSet.init(alloc, "string-gpa");
    defer fs.deinit();

    var name: []const u8 = "world";
    var state = pflag.StringState{ .value = &name, .gpa = alloc };
    try fs.stringStateVarP(&state, "name", "n", "world", "your name");

    const args = [_][]const u8{"--name=ziggy"};
    try fs.parse(&args);

    std.debug.assert(std.mem.eql(u8, name, "ziggy"));
    std.debug.print("[string/gpa] OK: name={s}\n", .{name});
}
