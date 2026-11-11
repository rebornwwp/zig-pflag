//! Argument parsing engine — the token-consuming loop behind FlagSet.parse.
//!
//! Mirrors parseArgs / parseLongArg / parseShortArg / parseSingleShortArg from
//! Go pflag's flag.go (upstream keeps these as FlagSet methods; port-side
//! layering moves them here as free functions taking `*FlagSet`).
//!
//! This module may touch FlagSet's non-pub struct fields (`_last_error`,
//! `_parse_callback`, `_shorthand_err_buf`, `actual`/`ordered_actual`, ...) —
//! field access through the pub container is legal cross-file, and it is
//! deliberate: parse.zig is the engine room, pflag.zig the registry.
//! Non-pub methods are NOT reachable across files in Zig 0.17 (lazy
//! analysis hid this from probes), so the only bookkeeping the engine needs
//! (`markParsed`) lives here; the public surface (`parse`/`parseAll`
//! shells, `lastError`, `printUsage`) stays in FlagSet.

const std = @import("std");
const Flag = @import("pflag.zig").Flag;
const FlagSet = @import("pflag.zig").FlagSet;
const ParseError = @import("errors.zig").ParseError;

/// Deliver `value` to the flag: through the parseAll callback when mounted,
/// otherwise straight into the Value vtable.
fn applyValue(fs: *FlagSet, flag: *Flag, value: []const u8) !void {
    if (fs._parse_callback) |cb| try cb(flag, value) else try flag.value.set(value);
}

/// Record a structured ParseError, print usage when the app is interactive,
/// and return the Zig error to propagate.
fn doFailWith(fs: *FlagSet, kind: ParseError.ErrorKind, name: []const u8, err: anyerror) anyerror {
    fs._last_error = ParseError.init(kind, name);
    if (fs.error_handling != .continue_on_error) fs.printUsage();
    return err;
}

/// Bookkeeping after a value lands: first Set moves the flag into
/// actual/ordered_actual and marks it changed. (Exposed for pflag.zig's
/// FlagSet.set(); not re-exported from the pflag module.)
pub fn markParsed(fs: *FlagSet, flag: *Flag) !void {
    const gpa = fs.gpa;
    if (!fs.actual.contains(flag.name)) {
        try fs.actual.put(gpa, flag.name, flag);
        errdefer _ = fs.actual.remove(flag.name);
        try fs.ordered_actual.append(gpa, flag);
    }
    flag.changed = true;
}

pub fn longArg(fs: *FlagSet, s: []const u8, remaining: *[]const []const u8) !void {
    var name: []const u8 = undefined;
    var value: []const u8 = undefined;
    var has_value: bool = false;

    if (std.mem.indexOfScalar(u8, s[2..], '=')) |eq_idx| {
        name = s[2 .. eq_idx + 2];
        value = s[eq_idx + 3 ..];
        has_value = true;
    } else {
        name = s[2..];
    }

    const flag = fs.lookup(name);
    if (flag == null) {
        if (name.len > 0 and fs.parse_errors_allowlist.unknown_flags) {
            return;
        }
        return doFailWith(fs, .unknown_flag, name, error.NoSuchFlag);
    }
    const f = flag.?;

    if (f.deprecated.len > 0) {
        if (fs.out_writer) |w| w.print("Flag --{s} has been deprecated, {s}\n", .{ f.name, f.deprecated }) catch {};
    }

    if (!has_value) {
        if (f.no_opt_def_val.len > 0) {
            // Flag has a default value for when no option is provided (bool=true, count=+1)
            value = f.no_opt_def_val;
        } else if (remaining.len > 0) {
            value = remaining.*[0];
            remaining.* = remaining.*[1..];
        } else return doFailWith(fs, .value_required, f.name, error.ValueRequired);
    }
    try applyValue(fs, f, value);
    try markParsed(fs, f);
}

fn singleShortArg(fs: *FlagSet, shorthands: *[]const u8, remaining: *[]const []const u8) !void {
    const c = shorthands.*[0];
    const flag = fs.shorthandLookup(c);
    if (flag == null) {
        if (fs.parse_errors_allowlist.unknown_flags) {
            shorthands.* = shorthands.*[1..];
            return;
        }
        return doFailWith(fs, .unknown_shorthand, blk: {
            fs._shorthand_err_buf[0] = c;
            break :blk &fs._shorthand_err_buf;
        }, error.NoSuchFlag);
    }
    const f = flag.?;

    if (f.shorthand_deprecated.len > 0) {
        if (fs.out_writer) |w| w.print("Flag shorthand -{s} has been deprecated, {s}\n", .{ f.shorthand, f.shorthand_deprecated }) catch {};
    }

    var value: []const u8 = undefined;
    if (shorthands.len > 2 and shorthands.*[1] == '=') {
        value = shorthands.*[2..];
        shorthands.* = "";
    } else if (f.no_opt_def_val.len > 0) {
        value = f.no_opt_def_val;
        shorthands.* = shorthands.*[1..];
    } else if (shorthands.len > 1) {
        value = shorthands.*[1..];
        shorthands.* = "";
    } else if (remaining.len > 0) {
        value = remaining.*[0];
        remaining.* = remaining.*[1..];
        shorthands.* = "";
    } else return doFailWith(fs, .value_required, f.name, error.ValueRequired);

    try applyValue(fs, f, value);
    try markParsed(fs, f);
}

fn shortArg(fs: *FlagSet, s: []const u8, remaining: *[]const []const u8) !void {
    var sh: []const u8 = s[1..];
    while (sh.len > 0) try singleShortArg(fs, &sh, remaining);
}

/// Consume `remaining` in place: flags bind through the vtable, positional
/// tokens land in fs.args. `--` records args_len_at_dash then flushes the
/// tail; interspersed=false stops parsing at the first positional token.
pub fn argLoop(fs: *FlagSet, remaining: *std.ArrayListUnmanaged([]const u8)) !void {
    const gpa = fs.gpa;
    var i: usize = 0;
    while (i < remaining.items.len) {
        const s = remaining.items[i];
        i += 1;
        if (s.len == 0 or s[0] != '-' or s.len == 1) {
            if (!fs.interspersed) {
                try fs.args.append(gpa, s);
                try fs.args.appendSlice(gpa, remaining.items[i..]);
                remaining.clearAndFree(gpa);
                return;
            }
            try fs.args.append(gpa, s);
            continue;
        }
        if (s[1] == '-') {
            if (s.len == 2) {
                fs.args_len_at_dash = @intCast(fs.args.items.len);
                try fs.args.appendSlice(gpa, remaining.items[i..]);
                remaining.clearAndFree(gpa);
                break;
            }
            var rest: []const []const u8 = remaining.items[i..];
            try longArg(fs, s, &rest);
            const consumed = (remaining.items.len - i) - rest.len;
            i += consumed;
        } else {
            var rest: []const []const u8 = remaining.items[i..];
            try shortArg(fs, s, &rest);
            const consumed = (remaining.items.len - i) - rest.len;
            i += consumed;
        }
    }
}
