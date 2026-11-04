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

    var verbose: bool = false;
    try fs.boolVar(&verbose, "verbose", false, "verbose output");
    fs.setInterspersed(false);

    try fs.parse(&.{ "--verbose", "echo", "--verbose", "hello" });

    std.debug.print("verbose: {}\n", .{verbose});
    std.debug.print("args: ", .{});
    for (fs.args.items) |arg| {
        std.debug.print("{s} ", .{arg});
    }
    std.debug.print("\n", .{});
}
