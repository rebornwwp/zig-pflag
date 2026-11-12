//! Example: int (i32) flag with SmpAllocator.
//!
//! `std.heap.smp_allocator` is a thread-safe, general-purpose allocator
//! optimized for ReleaseFast builds. It is a process-wide singleton: there is
//! no `init`/`deinit`, and it performs no leak or bounds checking. Use
//! `SafeAllocator` (see `examples/int_gpa.zig`) when you need those checks.
//!
//! Try the intended release mode with:
//!   zig build run-int_smp_allocator -Doptimize=ReleaseFast
const std = @import("std");
const pflag = @import("pflag");

pub fn main() !void {
    const alloc = std.heap.smp_allocator;

    var fs = pflag.FlagSet.init(alloc, "int-smp");
    defer fs.deinit();

    var count: i32 = 0;
    try fs.intVarP(i32, &count, "count", "c", 0, "a counter");

    const args = [_][]const u8{"--count=99"};
    try fs.parse(&args);

    std.debug.assert(count == 99);
    std.debug.print("[int/smp_allocator] OK: count={d}\n", .{count});
}
