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

/// (Re)creates the global "program" FlagSet with the given allocator. Must be
/// called once before using any other function here if you need a custom
/// allocator; the `*CL` helpers lazily self-init with page_allocator otherwise.
pub fn initCommandLine(gpa: std.mem.Allocator) void {
    commandLine = FlagSet.init(gpa, "program");
}
/// The global FlagSet, created on first access with `gpa`. Pointer stays
/// valid until deinitCommandLine() (or a re-init).
pub fn getCommandLine(gpa: std.mem.Allocator) *FlagSet {
    if (commandLine == null) initCommandLine(gpa);
    return &commandLine.?;
}
/// Release the global FlagSet entirely (flags, values, tables) and reset the
/// singleton to null. Typically deferred from main().
pub fn deinitCommandLine() void {
    if (commandLine) |*cl| {
        cl.deinit();
        commandLine = null;
    }
}
/// Global-set shorthand for `FlagSet.boolVar` (page_allocator-owned singleton).
pub fn boolCL(p: *bool, name: []const u8, value: bool, usage: []const u8) !void {
    const cl = getCommandLine(std.heap.page_allocator);
    try cl.boolVar(p, name, value, usage);
}
/// Global-set shorthand for `FlagSet.intVar`.
pub fn intCL(comptime T: type, p: *T, name: []const u8, value: T, usage: []const u8) !void {
    const cl = getCommandLine(std.heap.page_allocator);
    try cl.intVar(T, p, name, value, usage);
}
/// Global-set shorthand for the LEGACY `FlagSet.stringVar` (caller-owned slice!).
pub fn stringCL(p: *[]const u8, name: []const u8, value: []const u8, usage: []const u8) !void {
    const cl = getCommandLine(std.heap.page_allocator);
    try cl.stringVar(p, name, value, usage);
}
/// Parse against the global set (pass `argv[1..]`); Go's `pflag.Parse()`.
pub fn parseCL(arguments: []const []const u8) !void {
    const cl = getCommandLine(std.heap.page_allocator);
    try cl.parse(arguments);
}
/// Global-set positional args after parse (empty slice before it exists).
pub fn argsCL() []const []const u8 {
    if (commandLine) |*cl| return cl.argList() else return &.{};
}
/// Global-set `nArg()` (count of positionals).
pub fn nArgCL() usize {
    if (commandLine) |*cl| return cl.nArg() else return 0;
}
/// Global-set `nFlag()` (count of distinct flags set).
pub fn nFlagCL() usize {
    if (commandLine) |*cl| return cl.nFlag() else return 0;
}
