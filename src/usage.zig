//! Usage/help rendering for flags: one formatted flag line plus the
//! word-wrap of its usage text.
//!
//! Mirrors the rendering machinery of Go pflag's flag.go (PrintDefaults /
//! FlagUsages family), factored out as a port-side layering improvement.
//! Pure reader/formatter: it only READS `Flag` fields, emits into a
//! caller-supplied std.Io.Writer, allocates nothing itself — no FlagSet
//! state is involved.

const std = @import("std");
const Flag = @import("pflag.zig").Flag;

/// Format a single flag line directly to a writer (for flagUsagesWrapped /
/// printDefaults / defaultUsage).
pub fn formatFlag(f: *const Flag, cols: usize, w: *std.Io.Writer) !void {
    if (f.shorthand.len > 0) {
        try w.print("  -{s}, --{s}", .{ f.shorthand, f.name });
    } else {
        try w.print("      --{s}", .{f.name});
    }
    if (showDefault(f)) try w.print("={s}", .{f.def_value});
    if (f.usage.len > 0) {
        try w.print("\n", .{});
        if (cols > 0) {
            try wrapUsage(f.usage, cols, 8, w);
        } else {
            try w.print("        {s}", .{f.usage});
        }
    }
    if (f.deprecated.len > 0) try w.print(" (deprecated: {s})", .{f.deprecated});
    try w.print("\n", .{});
}

/// Whether a flag line should display its default value (`=def`). Omits empty
/// and "false" defaults, and flags whose no-option default is "true" (bools).
fn showDefault(f: *const Flag) bool {
    const has_default = !std.mem.eql(u8, f.def_value, "false") and !std.mem.eql(u8, f.def_value, "");
    const needs_default = !std.mem.eql(u8, f.no_opt_def_val, "true");
    return has_default and needs_default;
}

/// Word-wrap usage text to a std.Io.Writer at `cols` boundary.
fn wrapUsage(
    usage: []const u8,
    cols: usize,
    indent: usize,
    w: *std.Io.Writer,
) !void {
    var line_len: usize = 0;
    var remaining = usage;

    // First line gets indent
    try w.print("        ", .{});
    line_len = 8;

    while (remaining.len > 0) {
        while (remaining.len > 0 and (remaining[0] == ' ' or remaining[0] == '\t')) {
            remaining = remaining[1..];
        }
        if (remaining.len == 0) break;

        const word_end = std.mem.indexOfAny(u8, remaining, " \t\n") orelse remaining.len;
        const word = remaining[0..word_end];

        if (line_len > 0 and line_len + word.len > cols) {
            try w.print("\n", .{});
            var i: usize = 0;
            while (i < indent) : (i += 1) try w.print(" ", .{});
            line_len = indent;
        } else if (line_len > indent) {
            try w.print(" ", .{});
            line_len += 1;
        }

        try w.print("{s}", .{word});
        line_len += word.len;
        remaining = remaining[word_end..];
    }
}
