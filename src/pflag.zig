//! pflag — POSIX/GNU-style --flags for Zig.
//! Port of Go's spf13/pflag v1.0.9 to Zig 0.16.0.
//!
//! File layout mirrors Go pflag structure:
//!   value.zig        — Value interface (ptr + vtable)
//!   internal.zig     — shared leaf helpers (CSV, bool parse, key=value)
//!   usage.zig        — usage/help line rendering + word wrap
//!   parse.zig        — argument parsing engine (argLoop/longArg/shortArg)
//!   cmdline.zig      — global CommandLine singleton (*CL helpers)
//!   pflag.zig        — Flag, FlagSet, parse logic
//!   errors.zig       — Error types
//!   bool_types.zig   — Bool flag type
//!   int_types.zig    — Int flag types (comptime-generic)
//!   float_types.zig  — Float flag types (comptime-generic)
//!   string_types.zig — String flag type
//!   count_types.zig  — Count flag type
//!   duration_types.zig — Duration flag type
//!   slice_types.zig  — String/Int slice types
//!   map_types.zig    — String→Int / String→String map types

// When building tests, pull in pflag_test.zig so its test blocks are collected.
// builtin.is_test is true only when compiling via `zig test`.
comptime {
    if (@import("builtin").is_test) {
        _ = @import("pflag_test.zig");
        _ = @import("parse_test.zig");
        _ = @import("usage_test.zig");
        _ = @import("count_types.zig");
    }
}

const std = @import("std");
const usage_fmt = @import("usage.zig");
const parse_engine = @import("parse.zig");

// ─── Error types ───
pub const errors = @import("errors.zig");
pub const ErrorHandling = errors.ErrorHandling;
pub const ParseErrorsAllowlist = errors.ParseErrorsAllowlist;
pub const ParseError = errors.ParseError;

// ─── Shared leaf helpers (CSV / bool parsing / key=value) ───
pub const internal = @import("internal.zig");

// ─── Value Interface ───
// The interface itself lives in value.zig (no dependency on this file), so
// concrete types in *_types.zig can import it without a cycle. Re-exported
// here as `pflag.Value` for API compatibility.

pub const Value = @import("value.zig").Value;

// ─── Built-in Value Types ───

pub const bool_types = @import("bool_types.zig");
pub const int_types = @import("int_types.zig");
pub const uint_types = @import("uint_types.zig");
pub const float_types = @import("float_types.zig");
pub const string_types = @import("string_types.zig");
pub const count_types = @import("count_types.zig");
pub const duration_types = @import("duration_types.zig");
pub const slice_types = @import("slice_types.zig");
pub const map_types = @import("map_types.zig");

pub const boolValue = bool_types.boolValue;
pub const intValue = int_types.intValue;
pub const uintValue = uint_types.uintValue;
pub const floatValue = float_types.floatValue;
pub const stringValue = string_types.stringValue;
pub const stringStateValue = string_types.stringStateValue;
pub const StringState = string_types.StringState;
pub const countValue = count_types.countValue;
pub const durationValue = duration_types.durationValue;
pub const parseDuration = duration_types.parseDuration;
pub const formatDuration = duration_types.formatDuration;
pub const stringSliceValue = slice_types.stringSliceValue;
pub const StringSliceState = slice_types.StringSliceState;
pub const stringArrayValue = slice_types.stringArrayValue;
pub const StringArrayState = slice_types.StringArrayState;
pub const intSliceValue = slice_types.intSliceValue;
pub const uintSliceValue = slice_types.uintSliceValue;
pub const boolSliceValue = slice_types.boolSliceValue;
pub const floatSliceValue = slice_types.floatSliceValue;
pub const SliceState = slice_types.SliceState;
pub const stringToIntValue = map_types.stringToIntValue;
pub const StringToIntState = map_types.StringToIntState;
pub const stringToStringValue = map_types.stringToStringValue;
pub const StringToStringState = map_types.StringToStringState;

// ─── Flag ───

pub const Flag = struct {
    name: []const u8,
    shorthand: []const u8 = "",
    usage: []const u8 = "",
    value: Value,
    def_value: []const u8,
    /// True if this flag was explicitly set on the command line.
    /// Used by FlagSet.changed(name), Lookup, and Get functions.
    /// Distinct from VTable-level changed/allocated flags which track
    /// memory ownership of dupe'd data items.
    changed: bool = false,
    no_opt_def_val: []const u8 = "",
    deprecated: []const u8 = "",
    shorthand_deprecated: []const u8 = "",
    hidden: bool = false,
    annotations: std.StringArrayHashMapUnmanaged([]const []const u8) = .empty,

    pub fn deinit(self: *Flag, gpa: std.mem.Allocator) void {
        self.annotations.deinit(gpa);
        self.value.deinit(gpa);
    }
};

// ─── FlagSet ───

pub const FlagSet = struct {
    name: []const u8,
    usage_callback: ?*const fn (*FlagSet) void = null,
    sort_flags: bool = false,
    parse_errors_allowlist: ParseErrorsAllowlist = .{},

    gpa: std.mem.Allocator,
    formal: std.StringHashMapUnmanaged(*Flag) = .empty,
    ordered_formal: std.ArrayListUnmanaged(*Flag) = .empty,
    shorthands: std.AutoHashMapUnmanaged(u8, *Flag) = .empty,
    actual: std.StringHashMapUnmanaged(*Flag) = .empty,
    ordered_actual: std.ArrayListUnmanaged(*Flag) = .empty,
    args: std.ArrayListUnmanaged([]const u8) = .empty,
    args_len_at_dash: isize = -1,
    parsed: bool = false,
    error_handling: ErrorHandling = .exit_on_error,
    out_writer: ?*std.Io.Writer = null,
    interspersed: bool = true,
    normalize_name_callback: ?*const fn (*FlagSet, []const u8) []const u8 = null,
    _parse_callback: ?*const fn (*Flag, []const u8) anyerror!void = null,
    _last_error: ParseError = .{ .kind = .help },
    _shorthand_err_buf: [1]u8 = undefined,

    pub fn init(gpa: std.mem.Allocator, name: []const u8) FlagSet {
        return .{ .gpa = gpa, .name = name };
    }

    pub fn deinit(self: *FlagSet) void {
        const gpa = self.gpa;
        for (self.ordered_formal.items) |f| {
            f.deinit(gpa);
            gpa.free(f.def_value);
            gpa.destroy(f);
        }
        self.formal.deinit(gpa);
        self.ordered_formal.deinit(gpa);
        self.shorthands.deinit(gpa);
        self.actual.deinit(gpa);
        self.ordered_actual.deinit(gpa);
        self.args.deinit(gpa);
    }

    fn normalizeFlagName(self: *FlagSet, name: []const u8) []const u8 {
        if (self.normalize_name_callback) |cb| return cb(self, name);
        return name;
    }

    pub fn addFlag(self: *FlagSet, flag: *Flag) !void {
        const gpa = self.gpa;
        const nname = self.normalizeFlagName(flag.name);
        if (self.formal.contains(nname)) return error.FlagRedefined;
        // Validate shorthand before inserting to avoid partial state
        if (flag.shorthand.len > 1) return error.ShorthandTooLong;
        if (flag.shorthand.len > 0 and self.shorthands.contains(flag.shorthand[0])) return error.ShorthandRedefined;
        flag.name = nname;
        try self.formal.put(gpa, nname, flag);
        errdefer _ = self.formal.remove(nname);
        try self.ordered_formal.append(gpa, flag);
        errdefer _ = self.ordered_formal.pop();
        if (flag.shorthand.len > 0) {
            try self.shorthands.put(gpa, flag.shorthand[0], flag);
            errdefer _ = self.shorthands.remove(flag.shorthand[0]);
        }
    }

    pub fn addFlagSet(self: *FlagSet, new_set: *FlagSet) !void {
        for (new_set.ordered_formal.items) |flag| {
            if (self.lookup(flag.name) == null) {
                const added = try self.varP(flag.value, flag.name, flag.shorthand, flag.usage);
                added.no_opt_def_val = flag.no_opt_def_val;
                added.deprecated = flag.deprecated;
                added.shorthand_deprecated = flag.shorthand_deprecated;
                added.hidden = flag.hidden;
                // Copy annotations
                var ann_it = flag.annotations.iterator();
                while (ann_it.next()) |entry| {
                    try added.annotations.put(self.gpa, entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }
    }

    pub fn varP(self: *FlagSet, value: Value, name: []const u8, shorthand: []const u8, usage: []const u8) !*Flag {
        const gpa = self.gpa;
        const flag = try gpa.create(Flag);
        errdefer gpa.destroy(flag);
        const def_value = try value.string(gpa);
        flag.* = .{ .name = name, .shorthand = shorthand, .usage = usage, .value = value, .def_value = def_value };
        errdefer gpa.free(flag.def_value);
        try self.addFlag(flag);
        return flag;
    }

    pub fn boolVar(self: *FlagSet, p: *bool, name: []const u8, value: bool, usage: []const u8) !void {
        try self.boolVarP(p, name, "", value, usage);
    }
    pub fn boolVarP(self: *FlagSet, p: *bool, name: []const u8, shorthand: []const u8, value: bool, usage: []const u8) !void {
        const flag = try self.varP(boolValue(value, p), name, shorthand, usage);
        flag.no_opt_def_val = "true";
    }

    pub fn intVar(self: *FlagSet, comptime T: type, p: *T, name: []const u8, value: T, usage: []const u8) !void {
        try self.intVarP(T, p, name, "", value, usage);
    }
    pub fn intVarP(self: *FlagSet, comptime T: type, p: *T, name: []const u8, shorthand: []const u8, value: T, usage: []const u8) !void {
        _ = try self.varP(intValue(T, value, p), name, shorthand, usage);
    }

    pub fn floatVar(self: *FlagSet, comptime T: type, p: *T, name: []const u8, value: T, usage: []const u8) !void {
        try self.floatVarP(T, p, name, "", value, usage);
    }
    pub fn floatVarP(self: *FlagSet, comptime T: type, p: *T, name: []const u8, shorthand: []const u8, value: T, usage: []const u8) !void {
        _ = try self.varP(floatValue(T, value, p), name, shorthand, usage);
    }

    pub fn uintVar(self: *FlagSet, comptime T: type, p: *T, name: []const u8, value: T, usage: []const u8) !void {
        try self.uintVarP(T, p, name, "", value, usage);
    }
    pub fn uintVarP(self: *FlagSet, comptime T: type, p: *T, name: []const u8, shorthand: []const u8, value: T, usage: []const u8) !void {
        _ = try self.varP(uintValue(T, value, p), name, shorthand, usage);
    }

    /// DEPRECATED: Use `stringStateVar` instead. This legacy form does NOT
    /// duplicate the string on `set()` — the caller's slice must outlive the FlagSet.
    pub fn stringVar(self: *FlagSet, p: *[]const u8, name: []const u8, value: []const u8, usage: []const u8) !void {
        try self.stringVarP(p, name, "", value, usage);
    }
    /// DEPRECATED: Use `stringStateVarP` instead. See `stringVar` for details.
    pub fn stringVarP(self: *FlagSet, p: *[]const u8, name: []const u8, shorthand: []const u8, value: []const u8, usage: []const u8) !void {
        _ = try self.varP(stringValue(value, p), name, shorthand, usage);
    }

    pub fn stringStateVar(self: *FlagSet, state: *StringState, name: []const u8, value: []const u8, usage: []const u8) !void {
        try self.stringStateVarP(state, name, "", value, usage);
    }
    pub fn stringStateVarP(self: *FlagSet, state: *StringState, name: []const u8, shorthand: []const u8, value: []const u8, usage: []const u8) !void {
        state.value.* = try state.gpa.dupe(u8, value);
        state.allocated = true;
        _ = try self.varP(stringStateValue(state), name, shorthand, usage);
    }

    pub fn countVar(self: *FlagSet, p: *i32, name: []const u8, value: i32, usage: []const u8) !void {
        try self.countVarP(p, name, "", value, usage);
    }
    pub fn countVarP(self: *FlagSet, p: *i32, name: []const u8, shorthand: []const u8, value: i32, usage: []const u8) !void {
        const flag = try self.varP(countValue(value, p), name, shorthand, usage);
        flag.no_opt_def_val = "+1";
    }

    pub fn durationVar(self: *FlagSet, p: *i64, name: []const u8, value: i64, usage: []const u8) !void {
        try self.durationVarP(p, name, "", value, usage);
    }
    pub fn durationVarP(self: *FlagSet, p: *i64, name: []const u8, shorthand: []const u8, value: i64, usage: []const u8) !void {
        _ = try self.varP(durationValue(value, p), name, shorthand, usage);
    }

    pub fn stringSliceVar(self: *FlagSet, state: *StringSliceState, name: []const u8, value: []const []const u8, usage: []const u8) !void {
        try self.stringSliceVarP(state, name, "", value, usage);
    }
    pub fn stringSliceVarP(self: *FlagSet, state: *StringSliceState, name: []const u8, shorthand: []const u8, value: []const []const u8, usage: []const u8) !void {
        // Pre-populate defaults into the ArrayList if provided
        if (value.len > 0) {
            try state.value.appendSlice(self.gpa, value);
        }
        _ = try self.varP(stringSliceValue(state), name, shorthand, usage);
    }

    pub fn intSliceVar(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, value: []const T, usage: []const u8) !void {
        try self.intSliceVarP(T, state, name, "", value, usage);
    }
    pub fn intSliceVarP(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, shorthand: []const u8, value: []const T, usage: []const u8) !void {
        try state.value.appendSlice(self.gpa, value);
        _ = try self.varP(intSliceValue(T, state), name, shorthand, usage);
    }

    pub fn uintSliceVar(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, value: []const T, usage: []const u8) !void {
        try self.uintSliceVarP(T, state, name, "", value, usage);
    }
    pub fn uintSliceVarP(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, shorthand: []const u8, value: []const T, usage: []const u8) !void {
        try state.value.appendSlice(self.gpa, value);
        _ = try self.varP(uintSliceValue(T, state), name, shorthand, usage);
    }

    pub fn boolSliceVar(self: *FlagSet, state: *slice_types.SliceState(bool), name: []const u8, value: []const bool, usage: []const u8) !void {
        try self.boolSliceVarP(state, name, "", value, usage);
    }
    pub fn boolSliceVarP(self: *FlagSet, state: *slice_types.SliceState(bool), name: []const u8, shorthand: []const u8, value: []const bool, usage: []const u8) !void {
        try state.value.appendSlice(self.gpa, value);
        const flag = try self.varP(boolSliceValue(state), name, shorthand, usage);
        flag.no_opt_def_val = "true";
    }

    pub fn floatSliceVar(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, value: []const T, usage: []const u8) !void {
        try self.floatSliceVarP(T, state, name, "", value, usage);
    }
    pub fn floatSliceVarP(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, shorthand: []const u8, value: []const T, usage: []const u8) !void {
        try state.value.appendSlice(self.gpa, value);
        _ = try self.varP(floatSliceValue(T, state), name, shorthand, usage);
    }

    pub fn stringArrayVar(self: *FlagSet, state: *StringArrayState, name: []const u8, value: []const []const u8, usage: []const u8) !void {
        try self.stringArrayVarP(state, name, "", value, usage);
    }
    pub fn stringArrayVarP(self: *FlagSet, state: *StringArrayState, name: []const u8, shorthand: []const u8, value: []const []const u8, usage: []const u8) !void {
        // Pre-populate defaults into the ArrayList if provided
        if (value.len > 0) {
            try state.value.appendSlice(self.gpa, value);
        }
        _ = try self.varP(stringArrayValue(state), name, shorthand, usage);
    }

    pub fn stringToIntVar(self: *FlagSet, comptime T: type, state: *StringToIntState(T), name: []const u8, value: T, usage: []const u8) !void {
        try self.stringToIntVarP(T, state, name, "", value, usage);
    }
    pub fn stringToIntVarP(self: *FlagSet, comptime T: type, state: *StringToIntState(T), name: []const u8, shorthand: []const u8, value: T, usage: []const u8) !void {
        _ = value; // TODO: pre-populate map from value if non-empty
        _ = try self.varP(stringToIntValue(T, state), name, shorthand, usage);
    }

    pub fn stringToStringVar(self: *FlagSet, state: *StringToStringState, name: []const u8, value: []const u8, usage: []const u8) !void {
        try self.stringToStringVarP(state, name, "", value, usage);
    }
    pub fn stringToStringVarP(self: *FlagSet, state: *StringToStringState, name: []const u8, shorthand: []const u8, value: []const u8, usage: []const u8) !void {
        _ = value; // TODO: pre-populate map from CSV value if non-empty
        _ = try self.varP(stringToStringValue(state), name, shorthand, usage);
    }

    pub fn lookup(self: *FlagSet, name: []const u8) ?*Flag {
        return self.formal.get(self.normalizeFlagName(name));
    }
    pub fn shorthandLookup(self: *FlagSet, shorthand: u8) ?*Flag {
        return self.shorthands.get(shorthand);
    }

    pub fn set(self: *FlagSet, name: []const u8, value: []const u8) !void {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        try flag.value.set(value);
        try parse_engine.markParsed(self, flag);
    }

    pub fn parsedFlag(self: *const FlagSet) bool {
        return self.parsed;
    }
    pub fn nArg(self: *const FlagSet) usize {
        return self.args.items.len;
    }
    pub fn argList(self: *const FlagSet) []const []const u8 {
        return self.args.items;
    }
    pub fn nFlag(self: *const FlagSet) usize {
        return self.actual.count();
    }
    pub fn hasFlags(self: *const FlagSet) bool {
        return self.ordered_formal.items.len > 0;
    }
    pub fn argsLenAtDash(self: *const FlagSet) isize {
        return self.args_len_at_dash;
    }

    pub fn visit(self: *const FlagSet, context: anytype, cb: *const fn (@TypeOf(context), *Flag) void) void {
        for (self.ordered_actual.items) |f| cb(context, f);
    }
    pub fn visitAll(self: *const FlagSet, context: anytype, cb: *const fn (@TypeOf(context), *Flag) void) void {
        for (self.ordered_formal.items) |f| cb(context, f);
    }

    pub fn getBool(self: *FlagSet, name: []const u8) !bool {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (!std.mem.eql(u8, flag.value.typeName(), "bool")) return error.TypeMismatch;
        return (@as(*bool, @ptrCast(@alignCast(flag.value.ptr)))).*;
    }
    pub fn getInt(self: *FlagSet, comptime T: type, name: []const u8) !T {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (!std.mem.eql(u8, flag.value.typeName(), @typeName(T))) return error.TypeMismatch;
        return (@as(*T, @ptrCast(@alignCast(flag.value.ptr)))).*;
    }
    pub fn getFloat(self: *FlagSet, comptime T: type, name: []const u8) !T {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (!std.mem.eql(u8, flag.value.typeName(), @typeName(T))) return error.TypeMismatch;
        return (@as(*T, @ptrCast(@alignCast(flag.value.ptr)))).*;
    }
    pub fn getString(self: *FlagSet, name: []const u8) ![]const u8 {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (!std.mem.eql(u8, flag.value.typeName(), "string")) return error.TypeMismatch;
        return try flag.value.string(self.gpa);
    }

    pub fn nameFn(self: *const FlagSet) []const u8 {
        return self.name;
    }
    pub fn arg(self: *const FlagSet, i: usize) []const u8 {
        if (i >= self.args.items.len) return "";
        return self.args.items[i];
    }

    pub fn changed(self: *FlagSet, name: []const u8) bool {
        const flag = self.lookup(name) orelse return false;
        return flag.changed;
    }

    pub fn markHidden(self: *FlagSet, name: []const u8) !void {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        flag.hidden = true;
    }

    pub fn hasAvailableFlags(self: *const FlagSet) bool {
        for (self.ordered_formal.items) |f| if (!f.hidden) return true;
        return false;
    }

    pub fn setAnnotation(self: *FlagSet, name: []const u8, key: []const u8, values: ?[]const []const u8) !void {
        const gpa = self.gpa;
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (values) |vals| try flag.annotations.put(gpa, key, vals) else _ = flag.annotations.swapRemove(key);
    }

    pub fn getAnnotation(self: *FlagSet, name: []const u8, key: []const u8) ?[]const []const u8 {
        const flag = self.lookup(name) orelse return null;
        return flag.annotations.get(key);
    }

    pub fn getNormalizeFunc(self: *const FlagSet) ?*const fn (*FlagSet, []const u8) []const u8 {
        return self.normalize_name_callback;
    }

    pub fn flagUsages(self: *const FlagSet) []const u8 {
        return self.flagUsagesWrapped(80);
    }

    pub fn flagUsagesWrapped(self: *const FlagSet, cols: usize) []const u8 {
        const gpa = self.gpa;
        var allocating = std.Io.Writer.Allocating.init(gpa);
        for (self.ordered_formal.items) |f| {
            if (f.hidden) continue;
            usage_fmt.formatFlag(f, cols, &allocating.writer) catch continue;
        }
        return allocating.toOwnedSlice() catch return "?";
    }

    pub fn parseAll(self: *FlagSet, arguments: []const []const u8, callback: *const fn (*Flag, []const u8) anyerror!void) !void {
        const gpa = self.gpa;
        self.parsed = true;
        // Reset args on re-parse
        self.args.clearRetainingCapacity();
        self.args_len_at_dash = -1;
        if (arguments.len == 0) return;
        var remaining = try std.ArrayListUnmanaged([]const u8).initCapacity(gpa, arguments.len);
        defer remaining.deinit(gpa);
        try remaining.appendSlice(gpa, arguments);
        const saved_cb = self._parse_callback;
        self._parse_callback = callback;
        defer self._parse_callback = saved_cb;
        parse_engine.argLoop(self, &remaining) catch |err| {
            return switch (self.error_handling) {
                .continue_on_error => err,
                .exit_on_error => std.process.exit(2),
                .panic_on_error => @panic(@errorName(err)),
            };
        };
    }

    pub fn markDeprecated(self: *FlagSet, name: []const u8, msg: []const u8) !void {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        flag.deprecated = msg;
    }
    pub fn markShorthandDeprecated(self: *FlagSet, name: []const u8, msg: []const u8) !void {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        flag.shorthand_deprecated = msg;
    }
    pub fn setName(self: *FlagSet, name: []const u8) void {
        self.name = name;
    }
    pub fn setNormalizeFunc(self: *FlagSet, cb: *const fn (*FlagSet, []const u8) []const u8) void {
        self.normalize_name_callback = cb;
    }
    pub fn setInterspersed(self: *FlagSet, b: bool) void {
        self.interspersed = b;
    }

    pub fn lastError(self: *const FlagSet) ParseError {
        return self._last_error;
    }
    pub fn printUsage(self: *FlagSet) void {
        if (self.usage_callback) |cb| cb(self) else defaultUsage(self);
    }

    /// Entry shell: tokenization itself lives in parse.zig (argLoop).
    pub fn parse(self: *FlagSet, arguments: []const []const u8) !void {
        const gpa = self.gpa;
        self.parsed = true;
        // Reset args on re-parse
        self.args.clearRetainingCapacity();
        self.args_len_at_dash = -1;
        if (arguments.len == 0) return;

        var remaining = try std.ArrayListUnmanaged([]const u8).initCapacity(gpa, arguments.len);
        defer remaining.deinit(gpa);
        try remaining.appendSlice(gpa, arguments);

        parse_engine.argLoop(self, &remaining) catch |err| {
            return switch (self.error_handling) {
                .continue_on_error => err,
                .exit_on_error => std.process.exit(2),
                .panic_on_error => @panic(@errorName(err)),
            };
        };
    }

    pub fn printDefaults(self: *FlagSet) void {
        if (self.out_writer == null) return;
        const w = self.out_writer.?;
        for (self.ordered_formal.items) |f| {
            if (f.hidden) continue;
            usage_fmt.formatFlag(f, 0, w) catch return;
        }
    }
};

fn defaultUsage(fs: *FlagSet) void {
    if (fs.out_writer == null) return;
    const w = fs.out_writer.?;
    w.print("Usage of {s}:\n", .{fs.name}) catch return;
    for (fs.ordered_formal.items) |f| {
        if (f.hidden) continue;
        usage_fmt.formatFlag(f, 0, w) catch return;
    }
}

// ─── Global Helpers ───

pub fn newFlagSet(gpa: std.mem.Allocator, name: []const u8) FlagSet {
    return FlagSet.init(gpa, name);
}

// The process-global CommandLine singleton lives in cmdline.zig; re-exported
// flat so historical `pflag.boolCL(...)` style calls keep resolving.
pub const cmdline = @import("cmdline.zig");
pub const initCommandLine = cmdline.initCommandLine;
pub const getCommandLine = cmdline.getCommandLine;
pub const deinitCommandLine = cmdline.deinitCommandLine;
pub const boolCL = cmdline.boolCL;
pub const intCL = cmdline.intCL;
pub const stringCL = cmdline.stringCL;
pub const parseCL = cmdline.parseCL;
pub const argsCL = cmdline.argsCL;
pub const nArgCL = cmdline.nArgCL;
pub const nFlagCL = cmdline.nFlagCL;
