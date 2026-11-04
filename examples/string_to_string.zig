const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    var gpa_state: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    defer {
        const leaks = gpa_state.deinit();
        if (leaks != 0) @panic("Memory leak detected!");
    }
    const gpa = gpa_state.allocator();

    var fs = pflag.FlagSet.init(gpa, "example");
    defer fs.deinit();

    var labels = std.StringHashMapUnmanaged([]const u8).empty;
    var state = pflag.StringToStringState{ .value = &labels, .gpa = gpa };
    try fs.stringToStringVar(&state, "arg", "", "string-to-string arg accepting key=value pairs");

    try fs.parse(&.{ "--arg", "a=1,b=2", "--arg", "a=2", "--arg=d=4" });

    var iter = labels.iterator();
    while (iter.next()) |entry| {
        std.debug.print("{s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
