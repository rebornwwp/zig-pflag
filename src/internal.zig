//! Shared leaf helpers for concrete flag types — pure text/number plumbing that
//! multiple `*_types.zig` files need, with no knowledge of Flag/FlagSet.
//!
//! Leaf module: imports only `std`. The original homes of these helpers were
//! bool_types.zig (parseBool, needed by boolSlice) and slice_types.zig
//! (CSV, the upstream location is string_slice.go — we factor it out because
//! bool/int slices need it too and to keep the dependency graph acyclic).

const std = @import("std");

// ─── Bool parsing ───

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (toLower(ca) != toLower(cb)) return false;
    }
    return true;
}

fn toLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

/// Go-compatible bool parsing: accepts true/false, TRUE/FALSE, True/False,
/// T/F, t/f, 1/0, and empty string (treated as true).
pub fn parseBool(v: []const u8) !bool {
    if (v.len == 0) return true;
    if (equalsIgnoreCase(v, "true") or equalsIgnoreCase(v, "t") or std.mem.eql(u8, v, "1")) return true;
    if (equalsIgnoreCase(v, "false") or equalsIgnoreCase(v, "f") or std.mem.eql(u8, v, "0")) return false;
    return error.InvalidBoolValue;
}

// ─── CSV (stringSlice semantics) ───

/// Parse CSV-formatted string into array of strings.
/// Matches Go's csv.NewReader behavior:
/// - Quoted fields: "one,two" → one,two
/// - Escaped quotes: "" → "
pub fn readAsCSV(gpa: std.mem.Allocator, val: []const u8) ![]const []const u8 {
    if (val.len == 0) return &.{};

    var result: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (result.items) |s| gpa.free(s);
        result.deinit(gpa);
    }

    var i: usize = 0;
    while (i < val.len) {
        var field: std.ArrayListUnmanaged(u8) = .empty;
        defer field.deinit(gpa);

        if (val[i] == '"') {
            // Quoted field
            i += 1; // skip opening quote
            while (i < val.len) {
                if (val[i] == '"') {
                    if (i + 1 < val.len and val[i + 1] == '"') {
                        // Escaped quote
                        try field.append(gpa, '"');
                        i += 2;
                    } else {
                        // End of quoted field
                        i += 1; // skip closing quote
                        break;
                    }
                } else {
                    try field.append(gpa, val[i]);
                    i += 1;
                }
            }
            // Skip to comma or end
            while (i < val.len and val[i] != ',') i += 1;
            if (i < val.len) i += 1; // skip comma
        } else {
            // Unquoted field
            while (i < val.len and val[i] != ',') {
                try field.append(gpa, val[i]);
                i += 1;
            }
            if (i < val.len) i += 1; // skip comma
        }

        const item = try gpa.dupe(u8, field.items);
        result.append(gpa, item) catch |err| {
            gpa.free(item);
            return err;
        };
    }

    return try result.toOwnedSlice(gpa);
}

/// Write array of strings as CSV format.
/// Matches Go's csv.Writer behavior.
pub fn writeAsCSV(gpa: std.mem.Allocator, vals: []const []const u8) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(gpa);

    for (vals, 0..) |s, i| {
        if (i > 0) try buf.appendSlice(gpa, ",");
        // Quote if contains comma, quote, or newline
        const needs_quote = std.mem.indexOfAny(u8, s, ",\"\n") != null;
        if (needs_quote) {
            try buf.appendSlice(gpa, "\"");
            for (s) |c| {
                if (c == '"') {
                    try buf.appendSlice(gpa, "\"\"");
                } else {
                    try buf.append(gpa, c);
                }
            }
            try buf.appendSlice(gpa, "\"");
        } else {
            try buf.appendSlice(gpa, s);
        }
    }

    return try buf.toOwnedSlice(gpa);
}

// ─── key=value pairs (stringToInt / stringToString semantics) ───

/// Split one `key=value` map entry: trims surrounding blanks, yields null for
/// empty chunks (caller skips them), raises error.ExpectedKeyValue when no
/// '=' is present. Returned slices BORROW from `pair` — duplication and
/// error-path freeing stay with the caller, per the ownership rules in AGENTS.md.
pub fn splitKeyValue(pair: []const u8) !?struct { key: []const u8, val: []const u8 } {
    const trimmed = std.mem.trim(u8, pair, " \t");
    if (trimmed.len == 0) return null;
    const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse return error.ExpectedKeyValue;
    return .{ .key = trimmed[0..eq], .val = trimmed[eq + 1 ..] };
}
