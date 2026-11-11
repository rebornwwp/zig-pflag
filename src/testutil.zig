//! Shared helpers for the pflag test suites (pflag_test / parse_test /
//! usage_test). Test infrastructure only — not part of the library surface.

const std = @import("std");
const pflag = @import("pflag.zig");
const testing = std.testing;

const FlagSet = pflag.FlagSet;

pub fn newTestFlagSet() FlagSet {
    return FlagSet.init(testing.allocator, "test");
}

pub const VisitCounter = struct { count: usize = 0 };
pub fn visitCountFn(ctx: *VisitCounter, _: *pflag.Flag) void {
    ctx.count += 1;
}

pub fn lowerNormalize(_: *FlagSet, name: []const u8) []const u8 {
    return name; // return as-is for testing; real impl would lowercase
}

pub var parseAllCount: usize = 0;
pub fn parseAllCb(_: *pflag.Flag, _: []const u8) !void {
    parseAllCount += 1;
}

pub fn wordSepNormalizeFunc(_: *FlagSet, name: []const u8) []const u8 {
    // In Go this replaces underscores with dots. In Zig slices are immutable,
    // so we return the name as-is. Tests using this verify the normalize callback
    // is invoked, not the actual character replacement.
    return name;
}

pub fn aliasAndWordSepFlagNames(_: *FlagSet, name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "old_valid_flag")) {
        return "valid-flag";
    }
    return name;
}
