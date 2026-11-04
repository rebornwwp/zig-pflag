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
    try fs.boolVarP(&verbose, "verbose", "v", false, "verbose output");

    // Look up shorthand 'v' -> returns the flag with name "verbose"
    const flag = fs.shorthandLookup('v');
    if (flag) |f| {
        std.debug.print("{s}\n", .{f.name});
    }
}
