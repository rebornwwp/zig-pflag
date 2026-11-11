//! pflag — POSIX/GNU-style `--flags` for Zig.
//!
//! A port of Go's [spf13/pflag](https://github.com/spf13/pflag) v1.0.9 to
//! Zig 0.17.0: pure Zig, no C dependencies, no runtime services.
//!
//! ## File layout
//!
//! Upstream lives mostly in one 1.4k-line `flag.go`; this port layers by
//! dependency direction *beyond* upstream on purpose, while keeping the
//! public API frozen: everything user-facing is re-exported FLAT from this
//! module (no namespace tables like `pflag.bool_types` are published).
//!
//! - `value.zig` — the `Value` interface (ptr + vtable)
//! - `internal.zig` — shared leaf helpers (CSV, bool parsing, key=value)
//! - `usage.zig` — usage/help line rendering + word wrap
//! - `parse.zig` — argument parsing engine (`argLoop`/`longArg`/`shortArg`)
//! - `cmdline.zig` — process-global CommandLine singleton (`*CL` helpers)
//! - `pflag.zig` — `Flag`, `FlagSet`, registration, parse entry shells
//! - `errors.zig` — error types (`ParseError`, `ErrorHandling`, allowlist)
//! - `*_types.zig` — one file per concrete `Value` implementation, all
//!   comptime-generic where a family of widths exists (int/uint/float/slice/map)

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
// All module imports in this file are FILE-PRIVATE: the published surface is
// the flat names below, never a namespace table (no `pflag.errors`,
// no `pflag.bool_types`, ...). Keep it that way when adding features.
const errors = @import("errors.zig");
pub const ErrorHandling = errors.ErrorHandling;
pub const ParseErrorsAllowlist = errors.ParseErrorsAllowlist;
pub const ParseError = errors.ParseError;

// ─── Shared leaf helpers ───
// canonical homes are internal.zig; these three are part of the public API
// (custom Value implementations and round-trip tooling need them).
const internal = @import("internal.zig");
pub const parseBool = internal.parseBool;
pub const readAsCSV = internal.readAsCSV;
pub const writeAsCSV = internal.writeAsCSV;

// ─── Value Interface ───
// Lives in value.zig and stays FILE-PRIVATE from this module: the extension
// mechanism (custom vtable + varP) is an upstream-Go affordance this port
// deliberately does not publish — new flag types are contributed as *_types
// files (see AGENTS.md checklist), which import value.zig directly.
// `Flag.value` / the ctors below remain usable anonymously by callers.

const Value = @import("value.zig").Value;

// ─── Built-in Value Types ───
// Implementation modules AND their ctors are file-private now: registering
// goes exclusively through the FlagSet.xxxVar/xxxVarP methods below; the
// State structs stay public because callers must construct them.

const bool_types = @import("bool_types.zig");
const int_types = @import("int_types.zig");
const uint_types = @import("uint_types.zig");
const float_types = @import("float_types.zig");
const string_types = @import("string_types.zig");
const count_types = @import("count_types.zig");
const duration_types = @import("duration_types.zig");
const slice_types = @import("slice_types.zig");
const map_types = @import("map_types.zig");

const boolValue = bool_types.boolValue;
const intValue = int_types.intValue;
const uintValue = uint_types.uintValue;
const floatValue = float_types.floatValue;
const stringValue = string_types.stringValue;
const stringStateValue = string_types.stringStateValue;
pub const StringState = string_types.StringState;
const countValue = count_types.countValue;
const durationValue = duration_types.durationValue;
pub const parseDuration = duration_types.parseDuration;
pub const formatDuration = duration_types.formatDuration;
const stringSliceValue = slice_types.stringSliceValue;
pub const StringSliceState = slice_types.StringSliceState;
const stringArrayValue = slice_types.stringArrayValue;
pub const StringArrayState = slice_types.StringArrayState;
const intSliceValue = slice_types.intSliceValue;
const uintSliceValue = slice_types.uintSliceValue;
const boolSliceValue = slice_types.boolSliceValue;
const floatSliceValue = slice_types.floatSliceValue;
pub const SliceState = slice_types.SliceState;
const stringToIntValue = map_types.stringToIntValue;
pub const StringToIntState = map_types.StringToIntState;
const stringToStringValue = map_types.stringToStringValue;
pub const StringToStringState = map_types.StringToStringState;

// ─── Flag ───

/// One command-line flag: metadata plus the bound `value`. Created by the
/// `xxxVar`/`xxxVarP` registration methods (a custom `Value` needs a new
/// `*_types.zig` module in this repo — the ctor/`varP` plumbing is internal).
pub const Flag = struct {
    /// Long flag name, without the leading dashes (normalized at registration time).
    name: []const u8,
    /// Optional one-character shorthand, without dashes; "" when absent.
    shorthand: []const u8 = "",
    /// Help text shown by the usage renderers (word-wrapped at layout time).
    usage: []const u8 = "",
    /// The type-erased storage bound to the user variable (ptr + vtable).
    value: Value,
    /// Snapshot of the default value as text, taken at registration
    /// (`value.string()`); owned by the FlagSet and freed in `deinit`.
    def_value: []const u8,
    /// True if this flag was explicitly set on the command line.
    /// Used by FlagSet.changed(name), Lookup, and Get functions.
    /// Distinct from VTable-level changed/allocated flags which track
    /// memory ownership of dupe'd data items.
    changed: bool = false,
    /// Value used when the flag appears WITHOUT `=value` (bool: "true",
    /// count: "+1"); "" means a value is required.
    no_opt_def_val: []const u8 = "",
    /// Non-empty marks the long name deprecated; usage/render still shows the flag.
    deprecated: []const u8 = "",
    /// Non-empty marks the shorthand deprecated (mirrors `deprecated`).
    shorthand_deprecated: []const u8 = "",
    /// Hidden flags parse normally but are omitted from usage output.
    hidden: bool = false,
    /// Free-form metadata for integrations (completion, docs tools); keys and
    /// value slices are stored as given — the caller keeps ownership.
    annotations: std.StringArrayHashMapUnmanaged([]const []const u8) = .empty,

    /// Frees annotation storage, then the Value's owned data via vtable deinit.
    /// Called by `FlagSet.deinit` for every registered flag.
    pub fn deinit(self: *Flag, gpa: std.mem.Allocator) void {
        self.annotations.deinit(gpa);
        self.value.deinit(gpa);
    }
};

// ─── FlagSet ───

/// A named collection of flags: registration, parsing, and query — the
/// port's equivalent of Go's `pflag.FlagSet`. Allocate with `init(gpa, name)`
/// and release with `deinit()`; nothing is global, all memory comes from `gpa`.
pub const FlagSet = struct {
    /// Program/set name, shown in the "Usage of <name>:" header.
    name: []const u8,
    /// Custom help printer; null falls back to `defaultUsage` (see `printUsage`).
    usage_callback: ?*const fn (*FlagSet) void = null,
    /// Reserved for Go parity; usage currently renders in registration order.
    sort_flags: bool = false,
    /// Opt-in leniency: silently ignore unknown flags instead of failing parse.
    parse_errors_allowlist: ParseErrorsAllowlist = .{},

    /// Allocator for every internal structure and Value-owned duplicate.
    gpa: std.mem.Allocator,
    /// Defined flags, keyed by normalized name ("formal" = declared).
    formal: std.StringHashMapUnmanaged(*Flag) = .empty,
    /// Same flags in registration order (usage rendering, visitAll).
    ordered_formal: std.ArrayListUnmanaged(*Flag) = .empty,
    /// Shorthand character -> flag index for `-x` parsing.
    shorthands: std.AutoHashMapUnmanaged(u8, *Flag) = .empty,
    /// Flags actually set so far ("actual" = observed), keyed by name...
    actual: std.StringHashMapUnmanaged(*Flag) = .empty,
    /// ...and in first-seen order (visit / nFlag backing).
    ordered_actual: std.ArrayListUnmanaged(*Flag) = .empty,
    /// Positional (non-flag) arguments collected by the last parse.
    args: std.ArrayListUnmanaged([]const u8) = .empty,
    /// Length of `args` when the first `--` was consumed, else -1.
    args_len_at_dash: isize = -1,
    /// Set once `parse`/`parseAll` has been invoked.
    parsed: bool = false,
    /// What parse errors do: return err / exit(2) like Go / panic. Default `.exit_on_error`.
    error_handling: ErrorHandling = .exit_on_error,
    /// Sink for usage + deprecation warnings; null = print nothing at all.
    out_writer: ?*std.Io.Writer = null,
    /// True (default, GNU style): flags may appear between positionals.
    /// False: first positional stops flag parsing (see `setInterspersed`).
    interspersed: bool = true,
    /// Optional name rewriter (normalization) applied at register AND lookup.
    normalize_name_callback: ?*const fn (*FlagSet, []const u8) []const u8 = null,
    _parse_callback: ?*const fn (*Flag, []const u8) anyerror!void = null,
    _last_error: ParseError = .{ .kind = .help },
    _shorthand_err_buf: [1]u8 = undefined,

    /// Creates an empty FlagSet named `name` allocating from `gpa`.
    /// Every internal structure uses this allocator; see `deinit`.
    pub fn init(gpa: std.mem.Allocator, name: []const u8) FlagSet {
        return .{ .gpa = gpa, .name = name };
    }

    /// Frees every registered Flag (vtable `deinit` for user-owned value
    /// data, then `def_value`, then the Flag itself) and all internal tables.
    /// The bound user variables (`*bool`, `*T`, states...) are NOT freed —
    /// they belong to the caller.
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

    /// Registers a caller-built Flag (the set takes ownership on success).
    /// Validation happens BEFORE any mutation: duplicate long name ->
    /// error.FlagRedefined, shorthand longer than one byte ->
    /// error.ShorthandTooLong, duplicate shorthand -> error.ShorthandRedefined.
    /// Honors the active normalize callback (the flag's name field is
    /// rewritten to its normalized form).
    fn addFlag(self: *FlagSet, flag: *Flag) !void {
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

    /// Copies every flag definition from `new_set` into self, skipping names
    /// that already exist. Flags are rebuilt (same `Value`, so both sets
    /// still write to the SAME user variables); no_opt_def_val, deprecation
    /// messages, hidden and annotations carry over.
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

    /// The single registration funnel: allocates the Flag, snapshots
    /// `value.string()` as the printed default, and calls `addFlag`.
    /// All typed `xxxVar`/`xxxVarP` helpers below are thin wrappers over this.
    fn varP(self: *FlagSet, value: Value, name: []const u8, shorthand: []const u8, usage: []const u8) !*Flag {
        const gpa = self.gpa;
        const flag = try gpa.create(Flag);
        errdefer gpa.destroy(flag);
        const def_value = try value.string(gpa);
        flag.* = .{ .name = name, .shorthand = shorthand, .usage = usage, .value = value, .def_value = def_value };
        errdefer gpa.free(flag.def_value);
        try self.addFlag(flag);
        return flag;
    }

    /// Registers a bool flag bound to `p`. A bare `--name` sets true
    /// (no_opt_def_val); it never consumes the next argument.
    pub fn boolVar(self: *FlagSet, p: *bool, name: []const u8, value: bool, usage: []const u8) !void {
        try self.boolVarP(p, name, "", value, usage);
    }
    /// `boolVar` plus a one-character shorthand (`-v` == `--name`).
    pub fn boolVarP(self: *FlagSet, p: *bool, name: []const u8, shorthand: []const u8, value: bool, usage: []const u8) !void {
        const flag = try self.varP(boolValue(value, p), name, shorthand, usage);
        flag.no_opt_def_val = "true";
    }

    /// Registers a signed integer flag (T = i8/i16/i32/i64) bound to `p`.
    /// Values are parsed with radix autodetection: `0x`/`0b`/`0o` prefixes
    /// and `_` digit separators are accepted; a bare leading zero stays
    /// DECIMAL (Zig behavior: "010" == 10, unlike Go's octal 8).
    pub fn intVar(self: *FlagSet, comptime T: type, p: *T, name: []const u8, value: T, usage: []const u8) !void {
        try self.intVarP(T, p, name, "", value, usage);
    }
    /// `intVar` plus shorthand; also accepts `-x=42`, `-x42`, `-x 42`.
    pub fn intVarP(self: *FlagSet, comptime T: type, p: *T, name: []const u8, shorthand: []const u8, value: T, usage: []const u8) !void {
        _ = try self.varP(intValue(T, value, p), name, shorthand, usage);
    }

    /// Registers a float flag (T = f32/f64) bound to `p`. Accepts standard
    /// decimal/scientific forms, hex floats (`0x1.0p10`), `.5` / `5.` shapes,
    /// and `inf`/`nan` spellings; overflow SILENTLY saturates to +/-inf
    /// (no range error, unlike Go's strconv).
    pub fn floatVar(self: *FlagSet, comptime T: type, p: *T, name: []const u8, value: T, usage: []const u8) !void {
        try self.floatVarP(T, p, name, "", value, usage);
    }
    /// `floatVar` plus shorthand.
    pub fn floatVarP(self: *FlagSet, comptime T: type, p: *T, name: []const u8, shorthand: []const u8, value: T, usage: []const u8) !void {
        _ = try self.varP(floatValue(T, value, p), name, shorthand, usage);
    }

    /// Registers an unsigned integer flag (T = u8/u16/u32/u64) bound to `p`.
    /// Same radix rules as `intVar`; a negative literal fails with
    /// error.Overflow EXCEPT `-0`, which is accepted as 0.
    pub fn uintVar(self: *FlagSet, comptime T: type, p: *T, name: []const u8, value: T, usage: []const u8) !void {
        try self.uintVarP(T, p, name, "", value, usage);
    }
    /// `uintVar` plus shorthand.
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

    /// Library-managed string flag: the default is duplicated into `gpa` here,
    /// every `--name=...` duplicates again on set, and FlagSet.deinit frees it.
    /// PREFER THIS over the legacy `stringVar` (which stores the caller's
    /// slice without copying).
    pub fn stringStateVar(self: *FlagSet, state: *StringState, name: []const u8, value: []const u8, usage: []const u8) !void {
        try self.stringStateVarP(state, name, "", value, usage);
    }
    /// `stringStateVar` plus shorthand.
    pub fn stringStateVarP(self: *FlagSet, state: *StringState, name: []const u8, shorthand: []const u8, value: []const u8, usage: []const u8) !void {
        state.value.* = try state.gpa.dupe(u8, value);
        state.allocated = true;
        _ = try self.varP(stringStateValue(state), name, shorthand, usage);
    }

    /// Occurrence counter (Go's count flag): each bare appearance adds +1,
    /// while `--name=N` / `-v=N` sets exactly N; parseable with radix prefixes.
    /// `string()` renders the current count; `changed()` becomes true on any use.
    pub fn countVar(self: *FlagSet, p: *i32, name: []const u8, value: i32, usage: []const u8) !void {
        try self.countVarP(p, name, "", value, usage);
    }
    /// `countVar` plus shorthand (`-vvv` == 3).
    pub fn countVarP(self: *FlagSet, p: *i32, name: []const u8, shorthand: []const u8, value: i32, usage: []const u8) !void {
        const flag = try self.varP(countValue(value, p), name, shorthand, usage);
        flag.no_opt_def_val = "+1";
    }

    /// Duration flag stored as i64 NANOSECONDS. Shapes: integer + unit from
    /// `ns, us, ms, s, m, h, d` (`90s`, `2h`, `1d`, `-5s`); fractional values
    /// and compound spans (`1.5h`, `1h30m`) are NOT supported, and a bare
    /// number with no unit is rejected (differs from Go's time.ParseDuration).
    pub fn durationVar(self: *FlagSet, p: *i64, name: []const u8, value: i64, usage: []const u8) !void {
        try self.durationVarP(p, name, "", value, usage);
    }
    /// `durationVar` plus shorthand.
    pub fn durationVarP(self: *FlagSet, p: *i64, name: []const u8, shorthand: []const u8, value: i64, usage: []const u8) !void {
        _ = try self.varP(durationValue(value, p), name, shorthand, usage);
    }

    /// CSV string slice: `--names=a,"b,c"` splits on commas OUTSIDE quotes
    /// only (Go csv semantics). First parse-time Set REPLACES the defaults,
    /// later occurrences APPEND. `state` owns the list; deinit conditionally
    /// frees items based on `state.changed` (see AGENTS.md memory rules).
    pub fn stringSliceVar(self: *FlagSet, state: *StringSliceState, name: []const u8, value: []const []const u8, usage: []const u8) !void {
        try self.stringSliceVarP(state, name, "", value, usage);
    }
    /// `stringSliceVar` plus shorthand; `value` is pre-populated as defaults.
    pub fn stringSliceVarP(self: *FlagSet, state: *StringSliceState, name: []const u8, shorthand: []const u8, value: []const []const u8, usage: []const u8) !void {
        // Pre-populate defaults into the ArrayList if provided
        if (value.len > 0) {
            try state.value.appendSlice(self.gpa, value);
        }
        _ = try self.varP(stringSliceValue(state), name, shorthand, usage);
    }

    /// Numeric slice (T = i8..i64): plain comma splitting with `intVar`'s
    /// radix-0 element parsing (NO quote handling — that is `stringSliceVar`).
    /// Replace-then-append semantics identical to string slices.
    pub fn intSliceVar(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, value: []const T, usage: []const u8) !void {
        try self.intSliceVarP(T, state, name, "", value, usage);
    }
    /// `intSliceVar` plus shorthand.
    pub fn intSliceVarP(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, shorthand: []const u8, value: []const T, usage: []const u8) !void {
        try state.value.appendSlice(self.gpa, value);
        _ = try self.varP(intSliceValue(T, state), name, shorthand, usage);
    }

    /// Unsigned numeric slice variant of `intSliceVar` (u8..u64).
    pub fn uintSliceVar(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, value: []const T, usage: []const u8) !void {
        try self.uintSliceVarP(T, state, name, "", value, usage);
    }
    /// `uintSliceVar` plus shorthand.
    pub fn uintSliceVarP(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, shorthand: []const u8, value: []const T, usage: []const u8) !void {
        try state.value.appendSlice(self.gpa, value);
        _ = try self.varP(uintSliceValue(T, state), name, shorthand, usage);
    }

    /// Bool slice: elements pass through quote-stripping + CSV reads, each
    /// parsed by the `boolVar` spelling table. Bare `--name` (no "=") uses
    /// no_opt_def_val true, like Go's boolSlice.
    pub fn boolSliceVar(self: *FlagSet, state: *slice_types.SliceState(bool), name: []const u8, value: []const bool, usage: []const u8) !void {
        try self.boolSliceVarP(state, name, "", value, usage);
    }
    /// `boolSliceVar` plus shorthand.
    pub fn boolSliceVarP(self: *FlagSet, state: *slice_types.SliceState(bool), name: []const u8, shorthand: []const u8, value: []const bool, usage: []const u8) !void {
        try state.value.appendSlice(self.gpa, value);
        const flag = try self.varP(boolSliceValue(state), name, shorthand, usage);
        flag.no_opt_def_val = "true";
    }

    /// Float slice variant (f32/f64) of `intSliceVar`; comma split, no CSV
    /// quoting, elements parse like `floatVar`.
    pub fn floatSliceVar(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, value: []const T, usage: []const u8) !void {
        try self.floatSliceVarP(T, state, name, "", value, usage);
    }
    /// `floatSliceVar` plus shorthand.
    pub fn floatSliceVarP(self: *FlagSet, comptime T: type, state: *slice_types.SliceState(T), name: []const u8, shorthand: []const u8, value: []const T, usage: []const u8) !void {
        try state.value.appendSlice(self.gpa, value);
        _ = try self.varP(floatSliceValue(T, state), name, shorthand, usage);
    }

    /// String array: same replace-then-append bookkeeping as `stringSliceVar`
    /// but NO comma splitting — every appearance of the flag contributes
    /// exactly ONE element, verbatim (`--tag=a,b` yields a single "a,b").
    pub fn stringArrayVar(self: *FlagSet, state: *StringArrayState, name: []const u8, value: []const []const u8, usage: []const u8) !void {
        try self.stringArrayVarP(state, name, "", value, usage);
    }
    /// `stringArrayVar` plus shorthand.
    pub fn stringArrayVarP(self: *FlagSet, state: *StringArrayState, name: []const u8, shorthand: []const u8, value: []const []const u8, usage: []const u8) !void {
        // Pre-populate defaults into the ArrayList if provided
        if (value.len > 0) {
            try state.value.appendSlice(self.gpa, value);
        }
        _ = try self.varP(stringArrayValue(state), name, shorthand, usage);
    }

    /// `map[string]T` flag (Go's stringToInt): each occurrence accepts
    /// `key=val,key2=val2` — plain comma + trim (no CSV quotes), values parsed
    /// with `uintVar`/`intVar` radix rules. First Set replaces, later Sets
    /// merge per-key. NOTE: like upstream today, the `value` default is not
    /// pre-populated (tracked TODO).
    pub fn stringToIntVar(self: *FlagSet, comptime T: type, state: *StringToIntState(T), name: []const u8, value: T, usage: []const u8) !void {
        try self.stringToIntVarP(T, state, name, "", value, usage);
    }
    /// `stringToIntVar` plus shorthand.
    pub fn stringToIntVarP(self: *FlagSet, comptime T: type, state: *StringToIntState(T), name: []const u8, shorthand: []const u8, value: T, usage: []const u8) !void {
        _ = value; // TODO: pre-populate map from value if non-empty
        _ = try self.varP(stringToIntValue(T, state), name, shorthand, usage);
    }

    /// `map[string]string` flag: same `k=v,k2=v2` grammar as
    /// `stringToIntVar`, values kept verbatim after trim. Pre-existing
    /// `value` default is not pre-populated yet (tracked TODO, upstream parity).
    pub fn stringToStringVar(self: *FlagSet, state: *StringToStringState, name: []const u8, value: []const u8, usage: []const u8) !void {
        try self.stringToStringVarP(state, name, "", value, usage);
    }
    /// `stringToStringVar` plus shorthand.
    pub fn stringToStringVarP(self: *FlagSet, state: *StringToStringState, name: []const u8, shorthand: []const u8, value: []const u8, usage: []const u8) !void {
        _ = value; // TODO: pre-populate map from CSV value if non-empty
        _ = try self.varP(stringToStringValue(state), name, shorthand, usage);
    }

    /// Finds a registered flag by name. The lookup name goes through the
    /// SAME normalization callback used at registration, then the formal table.
    /// Returns null for unknown names (Go's Lookup contract).
    pub fn lookup(self: *FlagSet, name: []const u8) ?*Flag {
        return self.formal.get(self.normalizeFlagName(name));
    }
    /// Finds a registered flag by its shorthand character; null when unused.
    pub fn shorthandLookup(self: *FlagSet, shorthand: u8) ?*Flag {
        return self.shorthands.get(shorthand);
    }

    /// Programmatic assignment, bypassing argv: runs the Value vtable `set`
    /// then records the flag in the actual set (same bookkeeping as parse).
    /// Errors: error.NoSuchFlag plus whatever the value's parser returns
    /// (InvalidIntValue-style grammar errors, error.Overflow, ...).
    pub fn set(self: *FlagSet, name: []const u8, value: []const u8) !void {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        try flag.value.set(value);
        try parse_engine.markParsed(self, flag);
    }

    /// True after `parse`/`parseAll` has run (the flag is set at entry).
    pub fn parsedFlag(self: *const FlagSet) bool {
        return self.parsed;
    }
    /// Number of positional (non-flag) arguments from the last parse.
    pub fn nArg(self: *const FlagSet) usize {
        return self.args.items.len;
    }
    /// Borrowed view of the positional args (owned by the set; valid until
    /// deinit or the next parse, which resets them).
    pub fn argList(self: *const FlagSet) []const []const u8 {
        return self.args.items;
    }
    /// How many DISTINCT flags have actually been set so far.
    pub fn nFlag(self: *const FlagSet) usize {
        return self.actual.count();
    }
    /// True if any flag at all is defined (hidden or not).
    pub fn hasFlags(self: *const FlagSet) bool {
        return self.ordered_formal.items.len > 0;
    }
    /// Index into argList() where the tail after `--` begins, or -1 when the
    /// command line contained no bare `--` (mirrors Go ArgsLenAtDash).
    pub fn argsLenAtDash(self: *const FlagSet) isize {
        return self.args_len_at_dash;
    }

    /// Calls `cb(context, flag)` for every flag SET during parsing, in
    /// first-observed order (Go Visit).
    pub fn visit(self: *const FlagSet, context: anytype, cb: *const fn (@TypeOf(context), *Flag) void) void {
        for (self.ordered_actual.items) |f| cb(context, f);
    }
    /// Calls `cb(context, flag)` for every DEFINED flag, in registration
    /// order (Go VisitAll).
    pub fn visitAll(self: *const FlagSet, context: anytype, cb: *const fn (@TypeOf(context), *Flag) void) void {
        for (self.ordered_formal.items) |f| cb(context, f);
    }

    /// Typed read-back of a registered bool flag (no casting at the call site).
    /// Errors: error.NoSuchFlag, error.TypeMismatch (typeName() != "bool").
    pub fn getBool(self: *FlagSet, name: []const u8) !bool {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (!std.mem.eql(u8, flag.value.typeName(), "bool")) return error.TypeMismatch;
        return (@as(*bool, @ptrCast(@alignCast(flag.value.ptr)))).*;
    }
    /// Typed integer read-back; the typeName comparison uses @typeName(T), so
    /// request exactly the registered width (i32 flag != int64 lookup).
    /// Errors: error.NoSuchFlag, error.TypeMismatch.
    pub fn getInt(self: *FlagSet, comptime T: type, name: []const u8) !T {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (!std.mem.eql(u8, flag.value.typeName(), @typeName(T))) return error.TypeMismatch;
        return (@as(*T, @ptrCast(@alignCast(flag.value.ptr)))).*;
    }
    /// Float counterpart of `getInt` (f32/f64 width must match registration).
    pub fn getFloat(self: *FlagSet, comptime T: type, name: []const u8) !T {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (!std.mem.eql(u8, flag.value.typeName(), @typeName(T))) return error.TypeMismatch;
        return (@as(*T, @ptrCast(@alignCast(flag.value.ptr)))).*;
    }
    /// Rendered string value of a *string-typed* flag, freshly allocated from
    /// the set's gpa — THE CALLER OWNS AND MUST FREE the result. Works only
    /// when typeName() == "string" (Go GetString contract).
    pub fn getString(self: *FlagSet, name: []const u8) ![]const u8 {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (!std.mem.eql(u8, flag.value.typeName(), "string")) return error.TypeMismatch;
        return try flag.value.string(self.gpa);
    }

    /// Getter form of the `name` field (kept for Go parity).
    pub fn nameFn(self: *const FlagSet) []const u8 {
        return self.name;
    }
    /// Positional argument `i`; returns "" past the end (Go Arg).
    pub fn arg(self: *const FlagSet, i: usize) []const u8 {
        if (i >= self.args.items.len) return "";
        return self.args.items[i];
    }

    /// True when the named flag was explicitly provided (parse or `set`);
    /// false for unknown names as well (Go Changed).
    pub fn changed(self: *FlagSet, name: []const u8) bool {
        const flag = self.lookup(name) orelse return false;
        return flag.changed;
    }

    /// Exclude the named flag from usage output (it still parses!).
    /// Errors: error.NoSuchFlag.
    pub fn markHidden(self: *FlagSet, name: []const u8) !void {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        flag.hidden = true;
    }

    /// True if at least one flag is still visible in usage (Go HasAvailableFlags).
    pub fn hasAvailableFlags(self: *const FlagSet) bool {
        for (self.ordered_formal.items) |f| if (!f.hidden) return true;
        return false;
    }

    /// Attach (or with null `values`, remove) annotation metadata on a flag.
    /// Stored as-is: key and values retain CALLER ownership. Errors:
    /// error.NoSuchFlag, allocator errors from the map.
    pub fn setAnnotation(self: *FlagSet, name: []const u8, key: []const u8, values: ?[]const []const u8) !void {
        const gpa = self.gpa;
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        if (values) |vals| try flag.annotations.put(gpa, key, vals) else _ = flag.annotations.swapRemove(key);
    }

    /// Read back an annotation; null when flag or key is unknown.
    pub fn getAnnotation(self: *FlagSet, name: []const u8, key: []const u8) ?[]const []const u8 {
        const flag = self.lookup(name) orelse return null;
        return flag.annotations.get(key);
    }

    /// Accessor for the callback installed by `setNormalizeFunc`.
    pub fn getNormalizeFunc(self: *const FlagSet) ?*const fn (*FlagSet, []const u8) []const u8 {
        return self.normalize_name_callback;
    }

    /// Multi-line help block for all visible flags, wrapped at 80 columns.
    /// Result is allocated from the set's gpa — CALLER MUST FREE it.
    /// (Use `FlagSet.flagUsagesWrapped` for a different width, `0` disables wrapping.)
    pub fn flagUsages(self: *const FlagSet) []const u8 {
        return self.flagUsagesWrapped(80);
    }

    /// Width-parameterized `flagUsages`. A render failure on one flag does not
    /// abort the text — remaining flags keep going; on total allocation failure
    /// returns the literal "?" rather than erroring (Go parity).
    pub fn flagUsagesWrapped(self: *const FlagSet, cols: usize) []const u8 {
        const gpa = self.gpa;
        var allocating = std.Io.Writer.Allocating.init(gpa);
        for (self.ordered_formal.items) |f| {
            if (f.hidden) continue;
            usage_fmt.formatFlag(f, cols, &allocating.writer) catch continue;
        }
        return allocating.toOwnedSlice() catch return "?";
    }

    /// Intercept variant of `parse`: instead of applying values through the
    /// vtable, EVERY parsed (flag, value) pair is routed to `callback`
    /// (validation hooks, config-file overlays...). Bookkeeping (actual set,
    /// changed flags, args) is identical to parse; any previously installed
    /// callback is saved and restored.
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

    /// Attach a deprecation message to the long name: parsing still works but
    /// usage shows "(deprecated: msg)" and parse time logs a warning through
    /// `out_writer`. Errors: error.NoSuchFlag.
    pub fn markDeprecated(self: *FlagSet, name: []const u8, msg: []const u8) !void {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        flag.deprecated = msg;
    }
    /// Shorthand-scoped twin of `markDeprecated` (warns only when `-x` is used).
    pub fn markShorthandDeprecated(self: *FlagSet, name: []const u8, msg: []const u8) !void {
        const flag = self.lookup(name) orelse return error.NoSuchFlag;
        flag.shorthand_deprecated = msg;
    }
    /// Rename the set (changes the "Usage of <name>:" header only).
    pub fn setName(self: *FlagSet, name: []const u8) void {
        self.name = name;
    }
    /// Install a name-normalization hook applied to flag names at BOTH
    /// registration and lookup (aliases, case folding...). Must return a slice
    /// that stays valid as long as the flag does.
    pub fn setNormalizeFunc(self: *FlagSet, cb: *const fn (*FlagSet, []const u8) []const u8) void {
        self.normalize_name_callback = cb;
    }
    /// false = classic subcommand behavior: parsing stops at the first
    /// positional argument and the rest of argv goes to args untouched.
    /// true (default) = GNU-style interspersing of flags and positionals.
    pub fn setInterspersed(self: *FlagSet, b: bool) void {
        self.interspersed = b;
    }

    /// Structured record of the most recent parse failure (kind + offending
    /// name); independent of the Zig error value returned by `parse`.
    pub fn lastError(self: *const FlagSet) ParseError {
        return self._last_error;
    }
    /// Print help: `usage_callback` if installed, otherwise `defaultUsage`
    /// (header + printDefaults-style lines). Silent when `out_writer` is null.
    pub fn printUsage(self: *FlagSet) void {
        if (self.usage_callback) |cb| cb(self) else defaultUsage(self);
    }

    /// Parse an argument vector — pass `argv[1..]`, NOT argv[0] (Go parity).
    /// Resets positional args and re-armable: calling again re-parses from a
    /// clean state while keeping flag bindings. Tokenization itself is a
    /// delegating shell over parse.zig (argLoop): `--name=v`, `--name v`,
    /// bare bools/counts, `-abc` bundles, `-c=v`/`-cv`, and `--` terminator;
    /// unknown names hit `parse_errors_allowlist` or fail with NoSuchFlag.
    /// On error the outcome follows `error_handling`: return the Zig error
    /// (.continue_on_error), print usage and std.process.exit(2)
    /// (.exit_on_error, THE DEFAULT — set it to .continue_on_error in libs
    /// and tests!), or panic (.panic_on_error).
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

    /// List every visible flag with a "=default" suffix where applicable
    /// (Go PrintDefaults). Writes to `out_writer` only; no-op when unset.
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

/// Convenience alias for `FlagSet.init(gpa, name)` (Go NewFlagSet).
pub fn newFlagSet(gpa: std.mem.Allocator, name: []const u8) FlagSet {
    return FlagSet.init(gpa, name);
}

// The process-global CommandLine singleton lives in cmdline.zig; re-exported
// flat so historical `pflag.boolCL(...)` style calls keep resolving. The
// module alias itself stays file-private — `pflag.cmdline` is deliberately
// NOT part of the public surface (no second access path to the singleton).
const cmdline = @import("cmdline.zig");
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
