//! Process-global FlagSet convenience layer — the port of the package-level
//! `CommandLine` / `Parse` / `BoolVar` / `Args` globals from the tail of Go
//! pflag's flag.go.
//!
//! Zig has no implicit package init: seed the singleton with
//! initCommandLine(gpa), or let getCommandLine create it lazily. The `*CL`
//! helpers mirror Go's default behavior of using std.heap.page_allocator.
//! This layer only calls public FlagSet methods; `pflag.zig` re-exports every
//! symbol here so `pflag.boolCL(...)` etc. keep working unchanged.

const std = @import("std");
const FlagSet = @import("pflag.zig").FlagSet;

var commandLine: ?FlagSet = null;

pub fn initCommandLine(gpa: std.mem.Allocator) void {
    commandLine = FlagSet.init(gpa, "program");
}
pub fn getCommandLine(gpa: std.mem.Allocator) *FlagSet {
    if (commandLine == null) initCommandLine(gpa);
    return &commandLine.?;
}
pub fn deinitCommandLine() void {
    if (commandLine) |*cl| {
        cl.deinit();
        commandLine = null;
    }
}
pub fn boolCL(p: *bool, name: []const u8, value: bool, usage: []const u8) !void {
    const cl = getCommandLine(std.heap.page_allocator);
    try cl.boolVar(p, name, value, usage);
}
pub fn intCL(comptime T: type, p: *T, name: []const u8, value: T, usage: []const u8) !void {
    const cl = getCommandLine(std.heap.page_allocator);
    try cl.intVar(T, p, name, value, usage);
}
pub fn stringCL(p: *[]const u8, name: []const u8, value: []const u8, usage: []const u8) !void {
    const cl = getCommandLine(std.heap.page_allocator);
    try cl.stringVar(p, name, value, usage);
}
pub fn parseCL(arguments: []const []const u8) !void {
    const cl = getCommandLine(std.heap.page_allocator);
    try cl.parse(arguments);
}
pub fn argsCL() []const []const u8 {
    if (commandLine) |*cl| return cl.argList() else return &.{};
}
pub fn nArgCL() usize {
    if (commandLine) |*cl| return cl.nArg() else return 0;
}
pub fn nFlagCL() usize {
    if (commandLine) |*cl| return cl.nFlag() else return 0;
}
