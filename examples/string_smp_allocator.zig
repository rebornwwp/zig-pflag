//! Example: string flag with SmpAllocator.
//!
//! `std.heap.smp_allocator` is a thread-safe, general-purpose allocator
//! optimized for ReleaseFast builds. It is a process-wide singleton: there is
//! no `init`/`deinit`, and it performs no leak or bounds checking. Use
//! `SafeAllocator` (see `examples/string_gpa.zig`) when you need those checks.
//!
//! Try the intended release mode with:
//!   zig build run-string_smp_allocator -Doptimize=ReleaseFast
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    const alloc = std.heap.smp_allocator;

    var fs = pflag.FlagSet.init(alloc, "string-smp");
    defer fs.deinit();

    var name: []const u8 = "world";
    var state = pflag.StringState{ .value = &name, .gpa = alloc };
    try fs.stringStateVarP(&state, "name", "n", "world", "your name");

    const args = [_][]const u8{"--name=ziggy"};
    try fs.parse(&args);

    std.debug.assert(std.mem.eql(u8, name, "ziggy"));
    std.debug.print("[string/smp_allocator] OK: name={s}\n", .{name});
}
