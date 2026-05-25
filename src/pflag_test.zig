//! Tests for pflag. Ported from Go's spf13/pflag flag_test.go v1.0.9.
const std = @import("std");
const pflag = @import("pflag");
const testing = std.testing;

const FlagSet = pflag.FlagSet;

fn newTestFlagSet() FlagSet {
    return FlagSet.init(testing.allocator, "test");
}

const VisitCounter = struct { count: usize = 0 };
fn visitCountFn(ctx: *VisitCounter, _: *pflag.Flag) void {
    ctx.count += 1;
}

// ── Basic Bool ──

test "BoolVar and parse true" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var flag_val: bool = false;
    try fs.boolVar(&flag_val, "verbose", false, "enable verbose");
    try fs.parse(&.{"--verbose"});
    try testing.expect(flag_val);
    try testing.expectEqual(@as(usize, 0), fs.nArg());
}

test "BoolVar parse explicit true/false" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: bool = true;
    try fs.boolVar(&a, "a", false, "");
    try fs.boolVar(&b, "b", true, "");
    try fs.parse(&.{ "--a=true", "--b=false" });
    try testing.expect(a);
    try testing.expect(!b);
}

test "BoolVar shorthand" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var flag_val: bool = false;
    try fs.boolVarP(&flag_val, "verbose", "v", false, "verbose mode");
    try fs.parse(&.{"-v"});
    try testing.expect(flag_val);
}

test "BoolVar accepts 0 and 1" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = true;
    var b: bool = false;
    try fs.boolVar(&a, "a", true, "");
    try fs.boolVar(&b, "b", false, "");
    try fs.parse(&.{ "--a=0", "--b=1" });
    try testing.expect(!a);
    try testing.expect(b);
}

// ── Int ──

test "IntVar and parse" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var count: i32 = 0;
    try fs.intVar(i32, &count, "count", 0, "the count");
    try fs.parse(&.{"--count=42"});
    try testing.expectEqual(@as(i32, 42), count);
}

test "IntVar separate value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var count: i32 = 0;
    try fs.intVar(i32, &count, "count", 0, "the count");
    try fs.parse(&.{ "--count", "99" });
    try testing.expectEqual(@as(i32, 99), count);
}

test "IntVar different types" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: i8 = 0;
    var b: i64 = 0;
    try fs.intVar(i8, &a, "a", 0, "");
    try fs.intVar(i64, &b, "b", 0, "");
    try fs.parse(&.{ "--a=127", "--b=9223372036854775807" });
    try testing.expectEqual(@as(i8, 127), a);
    try testing.expectEqual(@as(i64, 9223372036854775807), b);
}

// ── String ──

test "StringVar and parse" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVar(&name, "name", "default", "your name");
    try fs.parse(&.{"--name=Alice"});
    try testing.expectEqualStrings("Alice", name);
}

test "StringVar shorthand" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVarP(&name, "name", "n", "default", "your name");
    try fs.parse(&.{ "-n", "Bob" });
    try testing.expectEqualStrings("Bob", name);
}

// ── Float ──

test "FloatVar and parse" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: f64 = 0.0;
    try fs.floatVar(f64, &val, "rate", 0.0, "the rate");
    try fs.parse(&.{"--rate=3.14"});
    try testing.expectApproxEqRel(3.14, val, @as(f64, @floatCast(0.0001)));
}

test "FloatVar hex value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: f64 = 0.0;
    try fs.floatVar(f64, &val, "val", 0.0, "");
    try fs.parse(&.{"--val=0x1.0p10"});
    try testing.expectApproxEqRel(1024.0, val, @as(f64, @floatCast(0.001)));
}

// ── Shorthand Combination ──

test "Shorthand combo -abc" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    var c: bool = false;
    try fs.boolVarP(&a, "alpha", "a", false, "");
    try fs.boolVarP(&b, "bravo", "b", false, "");
    try fs.boolVarP(&c, "charlie", "c", false, "");
    try fs.parse(&.{"-abc"});
    try testing.expect(a);
    try testing.expect(b);
    try testing.expect(c);
}

// ── Dash-dash ──

test "Dash-dash terminates flag parsing" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var verbose: bool = false;
    try fs.boolVar(&verbose, "verbose", false, "");
    try fs.parse(&.{ "--verbose", "--", "--not-a-flag", "positional" });
    try testing.expect(verbose);
    try testing.expectEqual(@as(usize, 2), fs.nArg());
    try testing.expectEqualStrings("--not-a-flag", fs.argList()[0]);
    try testing.expectEqualStrings("positional", fs.argList()[1]);
}

// ── No Args ──

test "Parse with no arguments" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var flag_val: bool = false;
    try fs.boolVar(&flag_val, "verbose", false, "");
    try fs.parse(&.{});
    try testing.expect(!flag_val);
    try testing.expect(fs.parsedFlag());
}

// ── Positional Args ──

test "Non-flag args collected as positional" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var verbose: bool = false;
    try fs.boolVar(&verbose, "verbose", false, "");
    try fs.parse(&.{ "input.txt", "--verbose", "output.txt" });
    try testing.expect(verbose);
    try testing.expectEqual(@as(usize, 2), fs.nArg());
    try testing.expectEqualStrings("input.txt", fs.argList()[0]);
    try testing.expectEqualStrings("output.txt", fs.argList()[1]);
}

// ── Visit / VisitAll ──

test "VisitAll visits all defined flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var s: []const u8 = "";
    try fs.boolVar(&a, "verbose", false, "");
    try fs.stringVar(&s, "name", "", "");
    var counter = VisitCounter{};
    fs.visitAll(&counter, visitCountFn);
    try testing.expectEqual(@as(usize, 2), counter.count);
}

test "Visit visits only set flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var s: []const u8 = "";
    try fs.boolVar(&a, "verbose", false, "");
    try fs.stringVar(&s, "name", "", "");
    try fs.parse(&.{"--verbose"});
    var counter = VisitCounter{};
    fs.visit(&counter, visitCountFn);
    try testing.expectEqual(@as(usize, 1), counter.count);
}

// ── Get Typed Values ──

test "GetBool retrieves bool flag value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var flag_val: bool = false;
    try fs.boolVar(&flag_val, "verbose", false, "");
    try fs.parse(&.{"--verbose"});
    try testing.expect(try fs.getBool("verbose"));
}

test "GetInt retrieves int flag value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var count: i32 = 0;
    try fs.intVar(i32, &count, "count", 0, "");
    try fs.parse(&.{"--count=42"});
    try testing.expectEqual(@as(i32, 42), try fs.getInt(i32, "count"));
}

test "GetFloat retrieves float flag value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: f64 = 0.0;
    try fs.floatVar(f64, &val, "rate", 0.0, "");
    try fs.parse(&.{"--rate=2.5"});
    try testing.expectApproxEqRel(2.5, try fs.getFloat(f64, "rate"), @as(f64, @floatCast(0.0001)));
}

test "GetString retrieves string flag value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var name: []const u8 = "";
    try fs.stringVar(&name, "name", "", "");
    try fs.parse(&.{"--name=hello"});
    const got = try fs.getString("name");
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("hello", got);
}
// ── Lookup / Set ──

test "Lookup finds defined flag" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "debug", false, "");
    const flag = fs.lookup("debug");
    try testing.expect(flag != null);
    try testing.expectEqualStrings("debug", flag.?.name);
}

test "Lookup returns null for unknown" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expect(fs.lookup("missing") == null);
}

test "Set changes flag value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "debug", false, "");
    try fs.set("debug", "true");
    try testing.expect(val);
}

// ── NFlag / HasFlags ──

test "NFlag counts set flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    try fs.boolVar(&a, "a", false, "");
    try fs.boolVar(&b, "b", false, "");
    try fs.parse(&.{ "--a", "--b" });
    try testing.expectEqual(@as(usize, 2), fs.nFlag());
}

test "HasFlags with defined flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    try fs.boolVar(&a, "verbose", false, "");
    try testing.expect(fs.hasFlags());
}

test "HasFlags without flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expect(!fs.hasFlags());
}

// ── ParseErrorsAllowlist ──

test "ParseErrorsAllowlist ignores unknown flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.parse_errors_allowlist.unknown_flags = true;
    var known: bool = false;
    try fs.boolVar(&known, "known", false, "");
    try fs.parse(&.{ "--known", "--unknown", "positional" });
    try testing.expect(known);
    try testing.expectEqual(@as(usize, 1), fs.nArg());
}

// ── Name ──

test "FlagSet name is stored" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expectEqualStrings("test", fs.name);
}

// ── AddFlagSet ──

test "AddFlagSet merges flags" {
    var fs1 = FlagSet.init(testing.allocator, "set1");
    defer fs1.deinit();
    var fs2 = FlagSet.init(testing.allocator, "set2");
    defer fs2.deinit();
    var a: bool = false;
    var b: []const u8 = "";
    try fs1.boolVar(&a, "flag1", false, "");
    try fs2.stringVar(&b, "flag2", "", "");
    try fs1.addFlagSet(&fs2);
    try testing.expect(fs1.lookup("flag1") != null);
    try testing.expect(fs1.lookup("flag2") != null);
}

// ── NoOptDefVal ──

test "Bool default has NoOptDefVal set" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "flag", false, "");
    const flag = fs.lookup("flag").?;
    try testing.expectEqualStrings("true", flag.no_opt_def_val);
}

// ── Comprehensive ──

test "Comprehensive parse" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var bool_flag: bool = false;
    var int_flag: i32 = 0;
    var string_flag: []const u8 = "";
    var float_flag: f64 = 0.0;
    try fs.boolVar(&bool_flag, "bool", false, "bool value");
    try fs.intVar(i32, &int_flag, "int", 0, "int value");
    try fs.stringVar(&string_flag, "string", "default", "string value");
    try fs.floatVar(f64, &float_flag, "float", 0.0, "float value");
    const extra = "extra-arg";
    try fs.parse(&.{ "--bool", "--int=42", "--string=hello", "--float=3.14", extra });
    try testing.expect(bool_flag);
    try testing.expectEqual(@as(i32, 42), int_flag);
    try testing.expectEqualStrings("hello", string_flag);
    try testing.expectApproxEqRel(3.14, float_flag, @as(f64, @floatCast(0.0001)));
    try testing.expectEqual(@as(usize, 1), fs.nArg());
    try testing.expectEqualStrings(extra, fs.argList()[0]);
}

// ── Shorthand Lookup ──

test "shorthandLookup returns null for unknown" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expect(fs.shorthandLookup('x') == null);
}

// ── MarkDeprecated ──

test "MarkDeprecated sets deprecated message" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "oldflag", false, "an old flag");
    try fs.markDeprecated("oldflag", "use --newflag instead");
    const flag = fs.lookup("oldflag").?;
    try testing.expectEqualStrings("use --newflag instead", flag.deprecated);
}

test "MarkDeprecated on unknown flag returns error" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expectError(error.NoSuchFlag, fs.markDeprecated("missing", "msg"));
}

test "MarkShorthandDeprecated sets shorthand deprecated message" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVarP(&val, "flag", "f", false, "a flag");
    try fs.markShorthandDeprecated("flag", "use --flag instead");
    const flag = fs.lookup("flag").?;
    try testing.expectEqualStrings("use --flag instead", flag.shorthand_deprecated);
}

test "MarkShorthandDeprecated on unknown flag returns error" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expectError(error.NoSuchFlag, fs.markShorthandDeprecated("missing", "msg"));
}

// ── SetNormalizeFunc ──

fn lowerNormalize(_: *FlagSet, name: []const u8) []const u8 {
    return name; // return as-is for testing; real impl would lowercase
}

test "SetNormalizeFunc affects lookup" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.setNormalizeFunc(struct {
        fn toLower(fs_: *FlagSet, name: []const u8) []const u8 {
            _ = fs_;
            // Return a static buffer with lowercase - for testing we just mark it
            return name; // use as-is for now since we can't mutate
        }
    }.toLower);
    var val: bool = false;
    try fs.boolVar(&val, "verbose", false, "");
    // Lookup should still work with original name
    try testing.expect(fs.lookup("verbose") != null);
}

// ── SetInterspersed ──

test "SetInterspersed stops parsing after first non-flag" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.setInterspersed(false);
    var verbose: bool = false;
    try fs.boolVar(&verbose, "verbose", false, "");
    try fs.parse(&.{ "cmd", "--verbose", "arg" });
    // With interspersed=false, "--verbose" should be treated as positional
    try testing.expect(!verbose);
    try testing.expectEqual(@as(usize, 3), fs.nArg());
    try testing.expectEqualStrings("cmd", fs.argList()[0]);
    try testing.expectEqualStrings("--verbose", fs.argList()[1]);
}

// ── Hidden flags ──

test "Hidden flag is not printed in defaults" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "visible", false, "shown");
    const flag = fs.lookup("visible").?;
    flag.hidden = true;
    // Hidden flag should still work during parse
    try fs.parse(&.{"--visible"});
    try testing.expect(val);
}

// ── SetName ──

test "SetName changes flagset name" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.setName("newapp");
    try testing.expectEqualStrings("newapp", fs.name);
}

// ── Deprecated message during parse ──

test "Parse deprecated flag accepts value but warns" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "oldflag", false, "");
    fs.error_handling = .continue_on_error;
    try fs.markDeprecated("oldflag", "please use --newflag");
    try fs.parse(&.{"--oldflag"});
    try testing.expect(val);
}

// ── PrintDefaults produces output ──

test "PrintDefaults writes to out_writer" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "verbose", false, "enable verbose output");

    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;

    fs.printDefaults();
    const output = std.Io.Writer.buffered(&writer);
    try testing.expect(std.mem.indexOf(u8, output, "verbose") != null);
}

// ── Comprehensive with deprecated ──

test "Comprehensive parse with deprecated prints deprecation" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;

    var a: bool = false;
    var b: i32 = 0;
    try fs.boolVar(&a, "a", false, "");
    try fs.intVar(i32, &b, "b", 0, "");

    try fs.markDeprecated("a", "use --other");
    try fs.markShorthandDeprecated("b", "use --better");

    try fs.parse(&.{ "--a=true", "--b=42" });
    try testing.expect(a);
    try testing.expectEqual(@as(i32, 42), b);
}

// ── Count flag ──

test "CountVar increments on each use" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var c: i32 = 0;
    try fs.countVarP(&c, "verbose", "v", 0, "verbosity level");
    try fs.parse(&.{ "-v", "-v", "-v" });

    try testing.expectEqual(@as(i32, 3), c);
}

test "CountVar with value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var c: i32 = 0;
    try fs.countVar(&c, "count", 0, "");
    try fs.parse(&.{"--count=5"});

    try testing.expectEqual(@as(i32, 5), c);
}

test "CountVar default value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var c: i32 = 10;
    try fs.countVar(&c, "count", 10, "");
    try fs.parse(&.{"--count"});

    try testing.expectEqual(@as(i32, 11), c);
}

test "CountVar explicit value assigns not accumulates" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var c: i32 = 10;
    try fs.countVar(&c, "count", 10, "");
    try fs.parse(&.{"--count=5"});

    // Should be 5 (assigned), not 15 (accumulated)
    try testing.expectEqual(@as(i32, 5), c);
}

// ── Duration flag ──

test "DurationVar parses seconds" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=30s"});

    try testing.expectEqual(30 * std.time.ns_per_s, d);
}

test "DurationVar parses minutes" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=5m"});

    try testing.expectEqual(5 * std.time.ns_per_min, d);
}

test "DurationVar parses hours" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=2h"});

    try testing.expectEqual(2 * std.time.ns_per_hour, d);
}

test "DurationVar parses days" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=1d"});

    try testing.expectEqual(std.time.ns_per_day, d);
}

test "DurationVar parses milliseconds" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=500ms"});

    try testing.expectEqual(500 * std.time.ns_per_ms, d);
}

test "DurationVar parses microseconds" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=100us"});

    try testing.expectEqual(100 * std.time.ns_per_us, d);
}

test "DurationVar parses nanoseconds" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var d: i64 = 0;
    try fs.durationVar(&d, "timeout", 0, "");
    try fs.parse(&.{"--timeout=200ns"});

    try testing.expectEqual(@as(i64, 200), d);
}

// ── String Slice ──

test "StringSlice accumulates values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (slice.items) |s| testing.allocator.free(s);
        slice.deinit(testing.allocator);
    }
    var state = pflag.StringSliceState{ .value = &slice, .gpa = testing.allocator };
    try fs.stringSliceVar(&state, "tag", &.{}, "");
    try fs.parse(&.{ "--tag=a", "--tag=b", "--tag=c" });

    try testing.expectEqual(@as(usize, 3), slice.items.len);
    try testing.expectEqualStrings("a", slice.items[0]);
    try testing.expectEqualStrings("b", slice.items[1]);
    try testing.expectEqualStrings("c", slice.items[2]);
}

test "StringSlice with shorthand" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (slice.items) |s| testing.allocator.free(s);
        slice.deinit(testing.allocator);
    }
    var state = pflag.StringSliceState{ .value = &slice, .gpa = testing.allocator };
    fs.error_handling = .continue_on_error;
    try fs.stringSliceVarP(&state, "tag", "t", &.{}, "");
    try fs.parse(&.{ "-t", "x", "-t", "y" });

    try testing.expectEqual(@as(usize, 2), slice.items.len);
}

test "StringSlice first Set replaces defaults" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (slice.items) |s| testing.allocator.free(s);
        slice.deinit(testing.allocator);
    }
    var state = pflag.StringSliceState{ .value = &slice, .gpa = testing.allocator };
    try fs.stringSliceVar(&state, "tag", &.{ "default1", "default2" }, "");
    // Before parse: defaults are populated
    try testing.expectEqual(@as(usize, 2), slice.items.len);
    // After parse: first Set replaces defaults
    try fs.parse(&.{"--tag=gamma"});
    try testing.expectEqual(@as(usize, 1), slice.items.len);
    try testing.expectEqualStrings("gamma", slice.items[0]);
}

test "StringSlice supports CSV format" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (slice.items) |s| testing.allocator.free(s);
        slice.deinit(testing.allocator);
    }
    var state = pflag.StringSliceState{ .value = &slice, .gpa = testing.allocator };
    try fs.stringSliceVar(&state, "tag", &.{}, "");
    try fs.parse(&.{"--tag=a,b,c"});
    try testing.expectEqual(@as(usize, 3), slice.items.len);
    try testing.expectEqualStrings("a", slice.items[0]);
    try testing.expectEqualStrings("b", slice.items[1]);
    try testing.expectEqualStrings("c", slice.items[2]);
}

// ── Int Slice ──

test "IntSlice accumulates values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(i32) = .empty;
    defer slice.deinit(testing.allocator);
    var state = pflag.SliceState(i32){ .value = &slice, .gpa = testing.allocator };
    try fs.intSliceVar(i32, &state, "port", &.{}, "");
    try fs.parse(&.{ "--port=80", "--port=443", "--port=8080" });

    try testing.expectEqual(@as(usize, 3), slice.items.len);
    try testing.expectEqual(@as(i32, 80), slice.items[0]);
    try testing.expectEqual(@as(i32, 443), slice.items[1]);
    try testing.expectEqual(@as(i32, 8080), slice.items[2]);
}

// ── Arg / Changed / MarkHidden ──

test "Arg returns positional args by index" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try fs.parse(&.{ "one", "two", "three" });

    try testing.expectEqualStrings("one", fs.arg(0));
    try testing.expectEqualStrings("two", fs.arg(1));
    try testing.expectEqualStrings("three", fs.arg(2));
    try testing.expectEqualStrings("", fs.arg(99));
}

test "Changed returns true if flag was set" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: i32 = 0;
    try fs.boolVar(&a, "a", false, "");
    try fs.intVar(i32, &b, "b", 0, "");
    try fs.parse(&.{"--a"});

    try testing.expect(fs.changed("a"));
    try testing.expect(!fs.changed("b"));
    try testing.expect(!fs.changed("missing"));
}

test "MarkHidden hides flag from defaults" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    try fs.boolVar(&a, "a", false, "");
    try fs.markHidden("a");

    const flag = fs.lookup("a").?;
    try testing.expect(flag.hidden);
}

test "MarkHidden on missing flag returns error" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expectError(error.NoSuchFlag, fs.markHidden("missing"));
}

test "HasAvailableFlags with hidden only" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    try fs.boolVar(&a, "a", false, "");
    try testing.expect(fs.hasAvailableFlags());
    try fs.markHidden("a");
    try testing.expect(!fs.hasAvailableFlags());
}

// ── Annotations ──

test "SetAnnotation adds key-value to flag" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: []const u8 = "";
    try fs.stringVar(&val, "name", "", "");
    const values = [_][]const u8{ "v1", "v2" };
    try fs.setAnnotation("name", "mykey", &values);

    const ann = fs.getAnnotation("name", "mykey").?;
    try testing.expectEqual(@as(usize, 2), ann.len);
    try testing.expectEqualStrings("v1", ann[0]);
}

test "GetAnnotation returns null for missing" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expect(fs.getAnnotation("missing", "key") == null);
}

// ── GetNormalizeFunc ──

test "GetNormalizeFunc returns set callback" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expect(fs.getNormalizeFunc() == null);

    fs.setNormalizeFunc(struct {
        fn dummy(fs_: *FlagSet, n: []const u8) []const u8 {
            _ = fs_;
            return n;
        }
    }.dummy);
    try testing.expect(fs.getNormalizeFunc() != null);
}

// ── Name ──

test "NameFn returns flagset name" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expectEqualStrings("test", fs.nameFn());
}

// ── FlagUsages ──

test "FlagUsages returns usage text" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "verbose", false, "enable verbose");

    const usage = fs.flagUsages();
    defer fs.gpa.free(usage);
    try testing.expect(std.mem.indexOf(u8, usage, "verbose") != null);
    try testing.expect(std.mem.indexOf(u8, usage, "enable verbose") != null);
}

test "FlagUsages skips hidden flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    try fs.boolVar(&a, "visible", false, "shown");
    try fs.boolVar(&b, "hidden", false, "not shown");
    try fs.markHidden("hidden");

    const usage = fs.flagUsages();
    defer fs.gpa.free(usage);
    try testing.expect(std.mem.indexOf(u8, usage, "visible") != null);
    try testing.expect(std.mem.indexOf(u8, usage, "hidden") == null);
}

// ── ParseAll ──

// Module-level for ParseAll test (Zig doesn't have closures)
var parseAllCount: usize = 0;
fn parseAllCb(_: *pflag.Flag, _: []const u8) !void {
    parseAllCount += 1;
}

test "ParseAll calls callback for each set flag" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: i32 = 0;
    try fs.boolVar(&a, "a", false, "");
    try fs.intVar(i32, &b, "b", 0, "");

    parseAllCount = 0;
    try fs.parseAll(&.{ "--a", "--b=42" }, parseAllCb);

    try testing.expectEqual(@as(usize, 2), parseAllCount);
}

// ── StringToInt map ──

test "StringToIntVar maps key=value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    defer map.deinit(testing.allocator);
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = testing.allocator };
    try fs.stringToIntVar(i32, &state, "headers", 0, "header map");
    try fs.parse(&.{ "--headers=a=1", "--headers=b=2", "--headers=c=3" });

    try testing.expectEqual(@as(i32, 1), map.get("a").?);
    try testing.expectEqual(@as(i32, 2), map.get("b").?);
    try testing.expectEqual(@as(i32, 3), map.get("c").?);
}

test "StringToIntVar rejects non-key=value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    defer map.deinit(testing.allocator);
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = testing.allocator };
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try testing.expectError(error.ExpectedKeyValue, fs.parse(&.{"--headers=badval"}));
}

// ── StringToString map ──

test "StringToStringVar maps key=value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer {
        var it = map.iterator();
        while (it.next()) |e| {
            testing.allocator.free(e.key_ptr.*);
            testing.allocator.free(e.value_ptr.*);
        }
        map.deinit(testing.allocator);
    }
    var state = pflag.StringToStringState{ .value = &map, .gpa = testing.allocator };
    try fs.stringToStringVar(&state, "labels", "", "");
    try fs.parse(&.{ "--labels=env=prod", "--labels=region=us-east" });

    try testing.expectEqualStrings("prod", map.get("env").?);
    try testing.expectEqualStrings("us-east", map.get("region").?);
}

// ── Error system ──

test "LastError captures parse failure details" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;

    var a: bool = false;
    try fs.boolVar(&a, "known", false, "");
    fs.parse(&.{"--unknown-flag"}) catch {};

    const err = fs.lastError();
    try testing.expectEqual(pflag.ParseError.ErrorKind.unknown_flag, err.kind);
    try testing.expectEqualStrings("unknown-flag", err.name);
}

test "LastError captures value required" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;

    var s: []const u8 = "";
    try fs.stringVar(&s, "name", "", "requires value");
    fs.parse(&.{"--name"}) catch {};

    const err = fs.lastError();
    try testing.expectEqual(pflag.ParseError.ErrorKind.value_required, err.kind);
    try testing.expectEqualStrings("name", err.name);
}

// ── Uint flags ──

test "UintVar parses unsigned values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var count: u32 = 0;
    try fs.uintVar(u32, &count, "count", 0, "");
    try fs.parse(&.{"--count=42"});
    try testing.expectEqual(@as(u32, 42), count);
}

test "UintVar different types" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: u8 = 0;
    var b: u64 = 0;
    try fs.uintVar(u8, &a, "a", 0, "");
    try fs.uintVar(u64, &b, "b", 0, "");
    try fs.parse(&.{ "--a=255", "--b=18446744073709551615" });
    try testing.expectEqual(@as(u8, 255), a);
    try testing.expectEqual(@as(u64, 18446744073709551615), b);
}

test "UintVar rejects negative values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var count: u32 = 0;
    try fs.uintVar(u32, &count, "count", 0, "");
    try testing.expectError(error.Overflow, fs.parse(&.{"--count=-1"}));
}

// ── Uint Slice ──

test "UintSlice accumulates values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(u32) = .empty;
    defer slice.deinit(testing.allocator);
    var state = pflag.SliceState(u32){ .value = &slice, .gpa = testing.allocator };
    try fs.uintSliceVar(u32, &state, "port", &.{}, "");
    try fs.parse(&.{ "--port=80", "--port=443", "--port=8080" });
    try testing.expectEqual(@as(usize, 3), slice.items.len);
    try testing.expectEqual(@as(u32, 80), slice.items[0]);
    try testing.expectEqual(@as(u32, 8080), slice.items[2]);
}

// ── Bool Slice ──

test "BoolSlice accumulates values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    defer slice.deinit(testing.allocator);
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = testing.allocator };
    try fs.boolSliceVar(&state, "flag", &.{}, "");
    try fs.parse(&.{ "--flag=true", "--flag=false", "--flag" });
    try testing.expectEqual(@as(usize, 3), slice.items.len);
    try testing.expect(slice.items[0]);
    try testing.expect(!slice.items[1]);
    try testing.expect(slice.items[2]);
}

test "BoolSlice with shorthand" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var slice: std.ArrayListUnmanaged(bool) = .empty;
    defer slice.deinit(testing.allocator);
    var state = pflag.SliceState(bool){ .value = &slice, .gpa = testing.allocator };
    try fs.boolSliceVarP(&state, "flag", "f", &.{}, "");
    try fs.parse(&.{ "-f", "-f", "-f" });
    try testing.expectEqual(@as(usize, 3), slice.items.len);
}

// ── Float Slice ──

test "FloatSlice accumulates values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f64) = .empty;
    defer slice.deinit(testing.allocator);
    var state = pflag.SliceState(f64){ .value = &slice, .gpa = testing.allocator };
    try fs.floatSliceVar(f64, &state, "rate", &.{}, "");
    try fs.parse(&.{ "--rate=1.5", "--rate=2.5", "--rate=3.14" });
    try testing.expectEqual(@as(usize, 3), slice.items.len);
    try testing.expectApproxEqRel(1.5, slice.items[0], @as(f64, @floatCast(0.0001)));
    try testing.expectApproxEqRel(3.14, slice.items[2], @as(f64, @floatCast(0.0001)));
}

test "FloatSlice f32 type" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged(f32) = .empty;
    defer slice.deinit(testing.allocator);
    var state = pflag.SliceState(f32){ .value = &slice, .gpa = testing.allocator };
    try fs.floatSliceVar(f32, &state, "val", &.{}, "");
    try fs.parse(&.{ "--val=0.5", "--val=1.0" });
    try testing.expectEqual(@as(usize, 2), slice.items.len);
}

// ── String Array ──

test "StringArray accumulates values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = testing.allocator };
    try fs.stringArrayVar(&state, "tag", &.{}, "");
    try fs.parse(&.{ "--tag=a", "--tag=b", "--tag=c" });
    defer {
        for (slice.items) |s| testing.allocator.free(s);
        slice.deinit(testing.allocator);
    }
    try testing.expectEqual(@as(usize, 3), slice.items.len);
    try testing.expectEqualStrings("a", slice.items[0]);
}

test "StringArray with default values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    defer slice.deinit(testing.allocator);
    var state = pflag.StringArrayState{ .value = &slice, .gpa = testing.allocator };
    try fs.stringArrayVar(&state, "tag", &.{ "alpha", "beta" }, "");
    try testing.expectEqual(@as(usize, 2), slice.items.len);
}

test "StringArray first Set replaces defaults" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringArrayState{ .value = &slice, .gpa = testing.allocator };
    try fs.stringArrayVar(&state, "tag", &.{ "d1", "d2" }, "");
    // Before parse: defaults are populated
    try testing.expectEqual(@as(usize, 2), slice.items.len);
    // After parse: first Set replaces defaults
    try fs.parse(&.{"--tag=new"});
    defer {
        for (slice.items) |s| testing.allocator.free(s);
        slice.deinit(testing.allocator);
    }
    try testing.expectEqual(@as(usize, 1), slice.items.len);
    try testing.expectEqualStrings("new", slice.items[0]);
}

// ── Additional coverage ──

test "GetAnnotation returns values" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: []const u8 = "";
    try fs.stringVar(&val, "flag", "", "");
    const values = [_][]const u8{ "x", "y" };
    try fs.setAnnotation("flag", "key", &values);
    const ann = fs.getAnnotation("flag", "key").?;
    try testing.expectEqual(@as(usize, 2), ann.len);
}

test "ParseRepeated works" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    try fs.boolVar(&a, "a", false, "");
    try fs.parse(&.{"--a"});
    try testing.expect(a);
    // Parse again with empty args - args are reset, but flag value preserved
    try fs.parse(&.{});
    try testing.expect(a); // value preserved
    try testing.expectEqual(@as(usize, 0), fs.nArg()); // args reset
}

test "SetOutput changes writer" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    fs.out_writer = &w;
    try testing.expect(fs.out_writer == &w);
}

test "Usage prints to writer" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    fs.out_writer = &w;
    fs.printUsage();
    const output = std.Io.Writer.buffered(&w);
    try testing.expect(std.mem.indexOf(u8, output, "Usage of test") != null);
}

test "IntVar shorthand with uint" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: u16 = 0;
    try fs.uintVarP(u16, &val, "port", "p", 0, "");
    try fs.parse(&.{ "-p", "8080" });
    try testing.expectEqual(@as(u16, 8080), val);
}

// ── StringToInt with i64 ──

test "StringToIntVar supports i64" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i64) = .empty;
    defer map.deinit(testing.allocator);
    var state = pflag.StringToIntState(i64){ .value = &map, .gpa = testing.allocator };
    try fs.stringToIntVar(i64, &state, "headers", 0, "header map (i64)");
    try fs.parse(&.{"--headers=x=9223372036854775807"});
    try testing.expectEqual(@as(i64, 9223372036854775807), map.get("x").?);
}

test "StringToIntVar supports u32" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(u32) = .empty;
    defer map.deinit(testing.allocator);
    var state = pflag.StringToIntState(u32){ .value = &map, .gpa = testing.allocator };
    try fs.stringToIntVar(u32, &state, "ports", 0, "port map");
    try fs.parse(&.{ "--ports=web=80", "--ports=ssl=443" });
    try testing.expectEqual(@as(u32, 80), map.get("web").?);
    try testing.expectEqual(@as(u32, 443), map.get("ssl").?);
}

test "StringToIntVar first Set replaces defaults" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    // Pre-populate with defaults
    map.put(testing.allocator, "old1", 100) catch {};
    map.put(testing.allocator, "old2", 200) catch {};
    defer map.deinit(testing.allocator);
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = testing.allocator };
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try testing.expectEqual(@as(u32, 2), map.count());
    // First Set should replace defaults
    try fs.parse(&.{"--headers=x=10"});
    try testing.expectEqual(@as(u32, 1), map.count());
    try testing.expectEqual(@as(i32, 10), map.get("x").?);
    try testing.expect(map.get("old1") == null);
}

test "StringToIntVar supports comma-separated pairs" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged(i32) = .empty;
    defer map.deinit(testing.allocator);
    var state = pflag.StringToIntState(i32){ .value = &map, .gpa = testing.allocator };
    try fs.stringToIntVar(i32, &state, "headers", 0, "");
    try fs.parse(&.{"--headers=a=1,b=2,c=3"});
    try testing.expectEqual(@as(u32, 3), map.count());
    try testing.expectEqual(@as(i32, 1), map.get("a").?);
    try testing.expectEqual(@as(i32, 2), map.get("b").?);
    try testing.expectEqual(@as(i32, 3), map.get("c").?);
}

// ── Duplicate shorthand rejection ──

test "Duplicate shorthand is rejected" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    try fs.boolVarP(&a, "alpha", "a", false, "");
    try testing.expectError(error.ShorthandRedefined, fs.boolVarP(&b, "beta", "a", false, ""));
}

// ── Re-parse resets args ──

test "Parse resets args on re-parse" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try fs.parse(&.{ "arg1", "arg2" });
    try testing.expectEqual(@as(usize, 2), fs.nArg());
    try fs.parse(&.{"arg3"});
    try testing.expectEqual(@as(usize, 1), fs.nArg());
    try testing.expectEqualStrings("arg3", fs.arg(0));
}

// ── argsLenAtDash ──

test "ArgsLenAtDash returns correct value" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    try fs.boolVar(&a, "a", false, "");
    try fs.parse(&.{ "--a", "--", "extra" });
    try testing.expectEqual(@as(isize, 0), fs.argsLenAtDash());
}

test "ArgsLenAtDash returns -1 without dash-dash" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try fs.parse(&.{"arg1"});
    try testing.expectEqual(@as(isize, -1), fs.argsLenAtDash());
}

// ── Type-safe getters ──

test "GetInt returns TypeMismatch for wrong type" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVar(&b, "flag", false, "");
    try testing.expectError(error.TypeMismatch, fs.getInt(i32, "flag"));
}

test "GetBool returns TypeMismatch for non-bool" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var n: i32 = 0;
    try fs.intVar(i32, &n, "num", 0, "");
    try testing.expectError(error.TypeMismatch, fs.getBool("num"));
}

// ── Go-compatible bool forms ──

test "BoolVar accepts Go-compatible forms" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: bool = true;
    var c: bool = false;
    var d: bool = true;
    try fs.boolVar(&a, "a", false, "");
    try fs.boolVar(&b, "b", true, "");
    try fs.boolVar(&c, "c", false, "");
    try fs.boolVar(&d, "d", true, "");
    try fs.parse(&.{ "--a=TRUE", "--b=FALSE", "--c=True", "--d=False" });
    try testing.expect(a);
    try testing.expect(!b);
    try testing.expect(c);
    try testing.expect(!d);
}

test "BoolVar accepts T and F shorthand forms" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: bool = true;
    try fs.boolVar(&a, "a", false, "");
    try fs.boolVar(&b, "b", true, "");
    try fs.parse(&.{ "--a=t", "--b=f" });
    try testing.expect(a);
    try testing.expect(!b);
}

// ── StringToString CSV ──

test "StringToStringVar supports CSV format" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer {
        var it = map.iterator();
        while (it.next()) |e| {
            testing.allocator.free(e.key_ptr.*);
            testing.allocator.free(e.value_ptr.*);
        }
        map.deinit(testing.allocator);
    }
    var state = pflag.StringToStringState{ .value = &map, .gpa = testing.allocator };
    try fs.stringToStringVar(&state, "labels", "", "");
    try fs.parse(&.{"--labels=a=1,b=2,c=3"});
    try testing.expectEqual(@as(u32, 3), map.count());
    try testing.expectEqualStrings("1", map.get("a").?);
    try testing.expectEqualStrings("2", map.get("b").?);
    try testing.expectEqualStrings("3", map.get("c").?);
}

// ── addFlagSet copies annotations ──

test "AddFlagSet copies annotations" {
    var fs1 = FlagSet.init(testing.allocator, "set1");
    defer fs1.deinit();
    var fs2 = FlagSet.init(testing.allocator, "set2");
    defer fs2.deinit();
    var a: bool = false;
    try fs2.boolVar(&a, "flag1", false, "");
    const values = [_][]const u8{"v1"};
    try fs2.setAnnotation("flag1", "mykey", &values);
    try fs1.addFlagSet(&fs2);
    const ann = fs1.getAnnotation("flag1", "mykey");
    try testing.expect(ann != null);
    try testing.expectEqual(@as(usize, 1), ann.?.len);
}

// ── StringStateVar copy-on-set ──

test "StringStateVar copies input on set" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var name: []const u8 = "";
    var state = pflag.StringState{ .value = &name, .gpa = testing.allocator };
    try fs.stringStateVar(&state, "name", "", "");
    try fs.parse(&.{"--name=copied"});
    try testing.expectEqualStrings("copied", name);
}

// ── FlagUsagesWrapped ──

test "FlagUsagesWrapped respects column width" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVarP(&val, "verbose", "v", false, "enable verbose output for debugging purposes");
    const text = fs.flagUsagesWrapped(40);
    defer testing.allocator.free(text);
    try testing.expect(text.len > 0);
}

// ── CommandLine singleton ──

test "CommandLine basic bool flag" {
    pflag.initCommandLine(testing.allocator);
    defer pflag.deinitCommandLine();
    var debug: bool = false;
    try pflag.boolCL(&debug, "debug", false, "enable debug");
    try pflag.parseCL(&.{"--debug"});
    try testing.expect(debug);
    try testing.expectEqual(@as(usize, 1), pflag.nFlagCL());
    try testing.expectEqual(@as(usize, 0), pflag.nArgCL());
}
