//! pflag — POSIX/GNU-style --flags for Zig.
//! Port of Go's spf13/pflag v1.0.9 to Zig 0.16.0.
//!
//! File layout mirrors Go pflag structure:
//!   pflag.zig        — Value, Flag, FlagSet, parse logic
//!   errors.zig       — Error types
//!   bool_types.zig   — Bool flag type
//!   int_types.zig    — Int flag types (comptime-generic)
//!   float_types.zig  — Float flag types (comptime-generic)
//!   string_types.zig — String flag type
//!   count_types.zig  — Count flag type
//!   duration_types.zig — Duration flag type
//!   slice_types.zig  — String/Int slice types
//!   map_types.zig    — String→Int / String→String map types

const std = @import("std");

// ─── Error types ───
pub const errors = @import("errors.zig");
pub const ErrorHandling = errors.ErrorHandling;
pub const ParseErrorsAllowlist = errors.ParseErrorsAllowlist;
pub const ParseError = errors.ParseError;

// ─── Value Interface ───

pub const Value = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        set: *const fn (ptr: *anyopaque, val: []const u8) anyerror!void,
        string: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator) []const u8,
        typeName: *const fn () []const u8,
        deinit: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator) void,
    };

    pub fn set(self: Value, val: []const u8) anyerror!void {
        return self.vtable.set(self.ptr, val);
    }
    pub fn string(self: Value, gpa: std.mem.Allocator) []const u8 {
        return self.vtable.string(self.ptr, gpa);
    }
    pub fn typeName(self: Value) []const u8 {
        return self.vtable.typeName();
    }
    pub fn deinit(self: Value, gpa: std.mem.Allocator) void {
        return self.vtable.deinit(self.ptr, gpa);
    }
};

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
pub const countValue = count_types.countValue;
pub const durationValue = duration_types.durationValue;
pub const parseDuration = duration_types.parseDuration;
pub const formatDuration = duration_types.formatDuration;
pub const stringSliceValue = slice_types.stringSliceValue;
pub const stringArrayValue = slice_types.stringArrayValue;
pub const intSliceValue = slice_types.intSliceValue;
pub const uintSliceValue = slice_types.uintSliceValue;
pub const boolSliceValue = slice_types.boolSliceValue;
pub const floatSliceValue = slice_types.floatSliceValue;
pub const stringToIntValue = map_types.stringToIntValue;
pub const stringToStringValue = map_types.stringToStringValue;

// ─── Flag ───

pub const Flag = struct {
    name: []const u8,
    shorthand: []const u8 = "",
    usage: []const u8 = "",
    value: Value,
    def_value: []const u8,
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
        flag.name = nname;
        try self.formal.put(gpa, nname, flag);
        try self.ordered_formal.append(gpa, flag);
        if (flag.shorthand.len > 0) {
            if (flag.shorthand.len > 1) return error.ShorthandTooLong;
            try self.shorthands.put(gpa, flag.shorthand[0], flag);
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
            }
        }
    }

    pub fn varP(self: *FlagSet, value: Value, name: []const u8, shorthand: []const u8, usage: []const u8) !*Flag {
        const gpa = self.gpa;
        const flag = try gpa.create(Flag);
        flag.* = .{ .name = name, .shorthand = shorthand, .usage = usage, .value = value, .def_value = value.string(gpa) };
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

    pub fn stringVar(self: *FlagSet, p: *[]const u8, name: []const u8, value: []const u8, usage: []const u8) !void {
        try self.stringVarP(p, name, "", value, usage);
    }
    pub fn stringVarP(self: *FlagSet, p: *[]const u8, name: []const u8, shorthand: []const u8, value: []const u8, usage: []const u8) !void {
        _ = try self.varP(stringValue(value, p), name, shorthand, usage);
    }

    pub fn countVar(self: *FlagSet, p: *i32, name: []const u8, value: i32, usage: []const u8) !void {
        try self.countVarP(p, name, "", value, usage);
    }
    pub fn countVarP(self: *FlagSet, p: *i32, name: []const u8, shorthand: []const u8, value: i32, usage: []const u8) !void {
        const flag = try self.varP(countValue(value, p), name, shorthand, usage);
        flag.no_opt_def_val = "1";
    }

    pub fn durationVar(self: *FlagSet, p: *i64, name: []const u8, value: i64, usage: []const u8) !void {
        try self.durationVarP(p, name, "", value, usage);
    }
    pub fn durationVarP(self: *FlagSet, p: *i64, name: []const u8, shorthand: []const u8, value: i64, usage: []const u8) !void {
        _ = try self.varP(durationValue(value, p), name, shorthand, usage);
    }

    pub fn stringSliceVar(self: *FlagSet, p: *std.ArrayListUnmanaged([]const u8), name: []const u8, value: []const []const u8, usage: []const u8) !void {
        try self.stringSliceVarP(p, name, "", value, usage);
    }
    pub fn stringSliceVarP(self: *FlagSet, p: *std.ArrayListUnmanaged([]const u8), name: []const u8, shorthand: []const u8, value: []const []const u8, usage: []const u8) !void {
        // Caller owns the ArrayList — pre-populate defaults themselves if needed.
        _ = value;
        _ = try self.varP(stringSliceValue(p), name, shorthand, usage);
    }

    pub fn intSliceVar(self: *FlagSet, comptime T: type, p: *std.ArrayListUnmanaged(T), name: []const u8, value: []const T, usage: []const u8) !void {
        try self.intSliceVarP(T, p, name, "", value, usage);
    }
    pub fn intSliceVarP(self: *FlagSet, comptime T: type, p: *std.ArrayListUnmanaged(T), name: []const u8, shorthand: []const u8, value: []const T, usage: []const u8) !void {
        p.appendSlice(self.gpa, value) catch {};
        _ = try self.varP(intSliceValue(T, p), name, shorthand, usage);
    }

    pub fn uintSliceVar(self: *FlagSet, comptime T: type, p: *std.ArrayListUnmanaged(T), name: []const u8, value: []const T, usage: []const u8) !void {
        try self.uintSliceVarP(T, p, name, "", value, usage);
    }
    pub fn uintSliceVarP(self: *FlagSet, comptime T: type, p: *std.ArrayListUnmanaged(T), name: []const u8, shorthand: []const u8, value: []const T, usage: []const u8) !void {
        p.appendSlice(self.gpa, value) catch {};
        _ = try self.varP(uintSliceValue(T, p), name, shorthand, usage);
    }

    pub fn boolSliceVar(self: *FlagSet, p: *std.ArrayListUnmanaged(bool), name: []const u8, value: []const bool, usage: []const u8) !void {
        try self.boolSliceVarP(p, name, "", value, usage);
    }
    pub fn boolSliceVarP(self: *FlagSet, p: *std.ArrayListUnmanaged(bool), name: []const u8, shorthand: []const u8, value: []const bool, usage: []const u8) !void {
        p.appendSlice(self.gpa, value) catch {};
        const flag = try self.varP(boolSliceValue(p), name, shorthand, usage);
        flag.no_opt_def_val = "true";
    }

    pub fn floatSliceVar(self: *FlagSet, comptime T: type, p: *std.ArrayListUnmanaged(T), name: []const u8, value: []const T, usage: []const u8) !void {
        try self.floatSliceVarP(T, p, name, "", value, usage);
    }
    pub fn floatSliceVarP(self: *FlagSet, comptime T: type, p: *std.ArrayListUnmanaged(T), name: []const u8, shorthand: []const u8, value: []const T, usage: []const u8) !void {
        p.appendSlice(self.gpa, value) catch {};
        _ = try self.varP(floatSliceValue(T, p), name, shorthand, usage);
    }

    pub fn stringArrayVar(self: *FlagSet, p: *std.ArrayListUnmanaged([]const u8), name: []const u8, value: []const []const u8, usage: []const u8) !void {
        try self.stringArrayVarP(p, name, "", value, usage);
    }
    pub fn stringArrayVarP(self: *FlagSet, p: *std.ArrayListUnmanaged([]const u8), name: []const u8, shorthand: []const u8, value: []const []const u8, usage: []const u8) !void {
        _ = value;
        _ = try self.varP(stringArrayValue(p), name, shorthand, usage);
    }

    pub fn stringToIntVar(self: *FlagSet, p: *std.StringHashMapUnmanaged(i32), name: []const u8, value: i32, usage: []const u8) !void {
        try self.stringToIntVarP(p, name, "", value, usage);
    }
    pub fn stringToIntVarP(self: *FlagSet, p: *std.StringHashMapUnmanaged(i32), name: []const u8, shorthand: []const u8, value: i32, usage: []const u8) !void {
        _ = value;
        _ = try self.varP(stringToIntValue(p), name, shorthand, usage);
    }

    pub fn stringToStringVar(self: *FlagSet, p: *std.StringHashMapUnmanaged([]const u8), name: []const u8, value: []const u8, usage: []const u8) !void {
        try self.stringToStringVarP(p, name, "", value, usage);
    }
    pub fn stringToStringVarP(self: *FlagSet, p: *std.StringHashMapUnmanaged([]const u8), name: []const u8, shorthand: []const u8, value: []const u8, usage: []const u8) !void {
        _ = value;
        _ = try self.varP(stringToStringValue(p), name, shorthand, usage);
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
        try self.markAsParsed(flag);
    }

    fn markAsParsed(self: *FlagSet, flag: *Flag) !void {
        const gpa = self.gpa;
        if (!self.actual.contains(flag.name)) {
            try self.actual.put(gpa, flag.name, flag);
            try self.ordered_actual.append(gpa, flag);
        }
        flag.changed = true;
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

    pub fn visit(self: *const FlagSet, context: anytype, cb: *const fn (@TypeOf(context), *Flag) void) void {
        for (self.ordered_actual.items) |f| cb(context, f);
    }
    pub fn visitAll(self: *const FlagSet, context: anytype, cb: *const fn (@TypeOf(context), *Flag) void) void {
        for (self.ordered_formal.items) |f| cb(context, f);
    }

    pub fn getBool(self: *FlagSet, name: []const u8) !bool {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        return (@as(*bool, @ptrCast(@alignCast(flag.value.ptr)))).*;
    }
    pub fn getInt(self: *FlagSet, comptime T: type, name: []const u8) !T {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        return (@as(*T, @ptrCast(@alignCast(flag.value.ptr)))).*;
    }
    pub fn getFloat(self: *FlagSet, comptime T: type, name: []const u8) !T {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        return (@as(*T, @ptrCast(@alignCast(flag.value.ptr)))).*;
    }
    pub fn getString(self: *FlagSet, name: []const u8) ![]const u8 {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        return (@as(*[]const u8, @ptrCast(@alignCast(flag.value.ptr)))).*;
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
        _ = cols;
        const gpa = self.gpa;
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        for (self.ordered_formal.items) |f| {
            if (f.hidden) continue;
            if (f.shorthand.len > 0) {
                const line = std.fmt.allocPrint(gpa, "  -{s}, --{s}", .{ f.shorthand, f.name }) catch continue;
                defer gpa.free(line);
                buf.appendSlice(gpa, line) catch continue;
            } else {
                const line = std.fmt.allocPrint(gpa, "      --{s}", .{f.name}) catch continue;
                defer gpa.free(line);
                buf.appendSlice(gpa, line) catch continue;
            }
            const hasDefault = !std.mem.eql(u8, f.def_value, "false") and !std.mem.eql(u8, f.def_value, "");
            const needsDefault = !std.mem.eql(u8, f.no_opt_def_val, "true");
            if (hasDefault and needsDefault) {
                const dv = std.fmt.allocPrint(gpa, "={s}", .{f.def_value}) catch continue;
                defer gpa.free(dv);
                buf.appendSlice(gpa, dv) catch continue;
            }
            if (f.usage.len > 0) {
                const u = std.fmt.allocPrint(gpa, "\n    \t{s}", .{f.usage}) catch continue;
                defer gpa.free(u);
                buf.appendSlice(gpa, u) catch continue;
            }
            if (f.deprecated.len > 0) buf.appendSlice(gpa, " (deprecated)") catch continue;
            buf.appendSlice(gpa, "\n") catch continue;
        }
        return buf.toOwnedSlice(gpa) catch return "?";
    }

    pub fn parseAll(self: *FlagSet, arguments: []const []const u8, callback: *const fn (*Flag, []const u8) anyerror!void) !void {
        const gpa = self.gpa;
        self.parsed = true;
        if (arguments.len == 0) return;
        var remaining = try std.ArrayListUnmanaged([]const u8).initCapacity(gpa, arguments.len);
        defer remaining.deinit(gpa);
        try remaining.appendSlice(gpa, arguments);
        const saved_cb = self._parse_callback;
        self._parse_callback = callback;
        defer self._parse_callback = saved_cb;
        self.parseArgLoop(&remaining) catch |err| {
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

    fn applyValue(self: *FlagSet, flag: *Flag, value: []const u8) !void {
        if (self._parse_callback) |cb| try cb(flag, value) else try flag.value.set(value);
    }

    fn doFailWith(self: *FlagSet, kind: ParseError.ErrorKind, name: []const u8, err: anyerror) anyerror {
        self._last_error = ParseError.init(kind, name);
        if (self.error_handling != .continue_on_error) self.printUsage();
        return err;
    }

    pub fn lastError(self: *const FlagSet) ParseError {
        return self._last_error;
    }
    pub fn printUsage(self: *FlagSet) void {
        if (self.usage_callback) |cb| cb(self) else defaultUsage(self);
    }

    fn parseLongArg(self: *FlagSet, s: []const u8, remaining: *std.ArrayListUnmanaged([]const u8)) !void {
        const gpa = self.gpa;
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

        const flag = self.lookup(name);
        if (flag == null) {
            if (name.len > 0 and self.parse_errors_allowlist.unknown_flags) {
                if (!has_value) return;
                try remaining.insert(gpa, 0, value);
                return;
            }
            return self.doFailWith(.unknown_flag, name, error.NoSuchFlag);
        }
        const f = flag.?;

        if (f.deprecated.len > 0) {
            if (self.out_writer) |w| w.print("Flag --{s} has been deprecated, {s}\n", .{ f.name, f.deprecated }) catch {};
        }

        if (!has_value) {
            if (std.mem.eql(u8, f.no_opt_def_val, "true")) {
                value = f.no_opt_def_val;
            } else if (remaining.items.len > 0) {
                value = remaining.orderedRemove(0);
            } else if (f.no_opt_def_val.len > 0) {
                value = f.no_opt_def_val;
            } else return self.doFailWith(.value_required, f.name, error.ValueRequired);
        }
        try applyValue(self, f, value);
        try self.markAsParsed(f);
    }

    fn parseSingleShortArg(self: *FlagSet, shorthands: *[]const u8, remaining: *std.ArrayListUnmanaged([]const u8)) !void {
        const c = shorthands.*[0];
        const flag = self.shorthandLookup(c);
        if (flag == null) {
            if (self.parse_errors_allowlist.unknown_flags) {
                shorthands.* = shorthands.*[1..];
                return;
            }
            return self.doFailWith(.unknown_shorthand, &.{c}, error.NoSuchFlag);
        }
        const f = flag.?;

        if (f.shorthand_deprecated.len > 0) {
            if (self.out_writer) |w| w.print("Flag shorthand -{s} has been deprecated, {s}\n", .{ f.shorthand, f.shorthand_deprecated }) catch {};
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
        } else if (remaining.items.len > 0) {
            value = remaining.orderedRemove(0);
            shorthands.* = "";
        } else return self.doFailWith(.value_required, f.name, error.ValueRequired);

        try applyValue(self, f, value);
        try self.markAsParsed(f);
    }

    fn parseShortArg(self: *FlagSet, s: []const u8, remaining: *std.ArrayListUnmanaged([]const u8)) !void {
        var sh: []const u8 = s[1..];
        while (sh.len > 0) try self.parseSingleShortArg(&sh, remaining);
    }

    fn parseArgLoop(self: *FlagSet, remaining: *std.ArrayListUnmanaged([]const u8)) !void {
        const gpa = self.gpa;
        while (remaining.items.len > 0) {
            const s = remaining.orderedRemove(0);
            if (s.len == 0 or s[0] != '-' or s.len == 1) {
                if (!self.interspersed) {
                    try self.args.append(gpa, s);
                    try self.args.appendSlice(gpa, remaining.items);
                    remaining.clearAndFree(gpa);
                    return;
                }
                try self.args.append(gpa, s);
                continue;
            }
            if (s[1] == '-') {
                if (s.len == 2) {
                    self.args_len_at_dash = @intCast(self.args.items.len);
                    try self.args.appendSlice(gpa, remaining.items);
                    remaining.clearAndFree(gpa);
                    break;
                }
                try self.parseLongArg(s, remaining);
            } else {
                try self.parseShortArg(s, remaining);
            }
        }
    }

    pub fn parse(self: *FlagSet, arguments: []const []const u8) !void {
        const gpa = self.gpa;
        self.parsed = true;
        if (arguments.len == 0) return;

        var remaining = try std.ArrayListUnmanaged([]const u8).initCapacity(gpa, arguments.len);
        defer remaining.deinit(gpa);
        try remaining.appendSlice(gpa, arguments);

        self.parseArgLoop(&remaining) catch |err| {
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
            if (f.shorthand.len > 0) {
                w.print("  -{s}, --{s}", .{ f.shorthand, f.name }) catch return;
            } else {
                w.print("      --{s}", .{f.name}) catch return;
            }
            const hasDefault = !std.mem.eql(u8, f.def_value, "false") and !std.mem.eql(u8, f.def_value, "");
            const needsDefault = !std.mem.eql(u8, f.no_opt_def_val, "true");
            if (hasDefault and needsDefault) w.print("={s}", .{f.def_value}) catch return;
            if (f.usage.len > 0) w.print("\n    \t{s}", .{f.usage}) catch return;
            if (f.deprecated.len > 0) w.print(" (deprecated: {s})", .{f.deprecated}) catch return;
            w.print("\n", .{}) catch return;
        }
    }
};

fn defaultUsage(fs: *FlagSet) void {
    if (fs.out_writer == null) return;
    const w = fs.out_writer.?;
    w.print("Usage of {s}:\n", .{fs.name}) catch return;
    for (fs.ordered_formal.items) |f| {
        if (f.shorthand.len > 0) {
            w.print("  -{s}, --{s}", .{ f.shorthand, f.name }) catch return;
        } else {
            w.print("  --{s}", .{f.name}) catch return;
        }
        if (!std.mem.eql(u8, f.def_value, "false") and !std.mem.eql(u8, f.def_value, "")) w.print("={s}", .{f.def_value}) catch return;
        if (f.usage.len > 0) w.print("\n    \t{s}", .{f.usage}) catch return;
        w.print("\n", .{}) catch return;
    }
}

// ─── Global Helpers ───

pub fn newFlagSet(gpa: std.mem.Allocator, name: []const u8) FlagSet {
    return FlagSet.init(gpa, name);
}

var commandLine: ?FlagSet = null;

pub fn initCommandLine(gpa: std.mem.Allocator) void {
    const args = std.process.argsAlloc(gpa) catch @panic("Failed to read args");
    defer std.process.argsFree(gpa, args);
    commandLine = FlagSet.init(gpa, if (args.len > 0) args[0] else "program");
}
pub fn getCommandLine(gpa: std.mem.Allocator) *FlagSet {
    if (commandLine == null) initCommandLine(gpa);
    return &commandLine.?;
}
pub fn deinitCommandLine() void {
    if (commandLine) |*cl| cl.deinit();
}
pub fn boolCL(p: *bool, name: []const u8, value: bool, usage: []const u8) !void {
    try getCommandLine(std.heap.page_allocator).boolVar(p, name, value, usage);
}
pub fn intCL(comptime T: type, p: *T, name: []const u8, value: T, usage: []const u8) !void {
    try getCommandLine(std.heap.page_allocator).intVar(T, p, name, value, usage);
}
pub fn stringCL(p: *[]const u8, name: []const u8, value: []const u8, usage: []const u8) !void {
    try getCommandLine(std.heap.page_allocator).stringVar(p, name, value, usage);
}
pub fn parseCL(arguments: []const []const u8) !void {
    try getCommandLine(std.heap.page_allocator).parse(arguments);
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
