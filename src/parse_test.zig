//! Parse-engine behavior tests: --long / -short bundles / interspersed /
//! "--" termination / allowlist / parseAll / re-parse, including ports of
//! Go testParse and supplementary flag_test.go cases.

const std = @import("std");
const pflag = @import("pflag.zig");
const testing = std.testing;

const FlagSet = pflag.FlagSet;

const testutil = @import("testutil.zig");
const newTestFlagSet = testutil.newTestFlagSet;
const VisitCounter = testutil.VisitCounter;
const visitCountFn = testutil.visitCountFn;
const lowerNormalize = testutil.lowerNormalize;
const wordSepNormalizeFunc = testutil.wordSepNormalizeFunc;
const aliasAndWordSepFlagNames = testutil.aliasAndWordSepFlagNames;
const parseAllCb = testutil.parseAllCb;

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

test "Parse with no arguments" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var flag_val: bool = false;
    try fs.boolVar(&flag_val, "verbose", false, "");
    try fs.parse(&.{});
    try testing.expect(!flag_val);
    try testing.expect(fs.parsedFlag());
}

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

test "ParseAll calls callback for each set flag" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: i32 = 0;
    try fs.boolVar(&a, "a", false, "");
    try fs.intVar(i32, &b, "b", 0, "");

    testutil.parseAllCount = 0;
    try fs.parseAll(&.{ "--a", "--b=42" }, testutil.parseAllCb);

    try testing.expectEqual(@as(usize, 2), testutil.parseAllCount);
}

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

test "Parse resets args on re-parse" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try fs.parse(&.{ "arg1", "arg2" });
    try testing.expectEqual(@as(usize, 2), fs.nArg());
    try fs.parse(&.{"arg3"});
    try testing.expectEqual(@as(usize, 1), fs.nArg());
    try testing.expectEqualStrings("arg3", fs.arg(0));
}

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

test "Short flag single char" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVarP(&b, "bool", "b", false, "");
    try fs.parse(&.{"-b"});
    try testing.expect(b);
}

test "Short flag with extra argument" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var s: []const u8 = "";
    try fs.stringVarP(&s, "string", "s", "", "");
    try fs.parse(&.{ "-s", "value" });
    try testing.expectEqualStrings("value", s);
}

test "Ignore unknown flags with allowlist" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    fs.parse_errors_allowlist.unknown_flags = true;
    var b: bool = false;
    try fs.boolVar(&b, "known", false, "");
    try fs.parse(&.{ "--known", "--unknown" });
    try testing.expect(b);
}

test "Ignore unknown flags backwards compat" {
    // Zig port only has parse_errors_allowlist, not the Go whitelist backwards-compat API
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    fs.parse_errors_allowlist.unknown_flags = true;
    var b: bool = false;
    try fs.boolVar(&b, "known", false, "");
    try fs.parse(&.{ "--known", "--unknown" });
    try testing.expect(b);
}

test "Ignore unknown flags and pass to args" {
    // Zig port doesn't have pass_unknown_flag_to_args — unknown flags are simply skipped
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    fs.parse_errors_allowlist.unknown_flags = true;
    var b: bool = false;
    try fs.boolVar(&b, "known", false, "");
    try fs.parse(&.{ "--known", "--unknown", "positional" });
    try testing.expect(b);
    // Unknown flag is skipped, positional arg collected
    try testing.expectEqual(@as(usize, 1), fs.args.items.len);
    try testing.expectEqualStrings("positional", fs.args.items[0]);
}

test "Ignore unknown flags backwards compat pass to args" {
    // Zig port doesn't have whitelist backwards-compat — use allowlist instead
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    fs.parse_errors_allowlist.unknown_flags = true;
    var b: bool = false;
    try fs.boolVar(&b, "known", false, "");
    try fs.parse(&.{ "--known", "--unknown" });
    try testing.expect(b);
}

test "FlagSet parse basic" {
    var fs = pflag.FlagSet.init(testing.allocator, "test");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var b: bool = false;
    try fs.boolVar(&b, "flag", false, "");
    try fs.parse(&.{"--flag=true"});
    try testing.expect(b);
}

test "Changing args - reparse" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var before: bool = false;
    try fs.boolVar(&before, "before", false, "");
    try fs.parse(&.{ "--before", "subcmd" });
    try testing.expect(before);
    try testing.expectEqualStrings("subcmd", fs.arg(0));
}

test "Unknown flag returns error" {
    // Zig port doesn't have special --help handling like Go pflag.
    // Unknown flags return NoSuchFlag error.
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var b: bool = false;
    try fs.boolVar(&b, "flag", false, "regular flag");
    const result = fs.parse(&.{"--unknown"});
    try testing.expectError(error.NoSuchFlag, result);
}

test "No interspersed mode" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.setInterspersed(false);
    var b: bool = false;
    try fs.boolVar(&b, "flag", false, "");
    try fs.parse(&.{ "--flag", "positional", "--other" });
    try testing.expect(b);
    // After first positional, remaining args are collected as-is
    try testing.expectEqual(@as(usize, 2), fs.args.items.len);
    try testing.expectEqualStrings("positional", fs.args.items[0]);
    try testing.expectEqualStrings("--other", fs.args.items[1]);
}

test "Termination with --" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVar(&b, "flag", false, "");
    try fs.parse(&.{ "--flag", "--", "--not-a-flag" });
    try testing.expect(b);
    try testing.expectEqual(@as(usize, 1), fs.args.items.len);
    try testing.expectEqualStrings("--not-a-flag", fs.args.items[0]);
}

test "Multiple positional args" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var verbose: bool = false;
    try fs.boolVar(&verbose, "verbose", false, "");
    try fs.parse(&.{ "--verbose", "file1.txt", "file2.txt", "file3.txt" });
    try testing.expect(verbose);
    try testing.expectEqual(@as(usize, 3), fs.nArg());
    try testing.expectEqualStrings("file1.txt", fs.arg(0));
    try testing.expectEqualStrings("file2.txt", fs.arg(1));
    try testing.expectEqualStrings("file3.txt", fs.arg(2));
}

test "Flag after positional arg with interspersed=false" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.setInterspersed(false);
    var verbose: bool = false;
    var count: i32 = 0;
    try fs.boolVar(&verbose, "verbose", false, "");
    try fs.intVar(i32, &count, "count", 0, "");
    try fs.parse(&.{ "file.txt", "--verbose", "--count=42" });
    try testing.expect(!verbose);
    try testing.expectEqual(@as(i32, 0), count);
    try testing.expectEqual(@as(usize, 3), fs.nArg());
}

test "Mixed flag types in one parse" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var verbose: bool = false;
    var count: i32 = 0;
    var name: []const u8 = "";
    var rate: f64 = 0.0;
    var slice: std.ArrayListUnmanaged([]const u8) = .empty;
    var state = pflag.StringSliceState{ .value = &slice, .gpa = testing.allocator };

    try fs.boolVar(&verbose, "verbose", false, "");
    try fs.intVar(i32, &count, "count", 0, "");
    try fs.stringVar(&name, "name", "", "");
    try fs.floatVar(f64, &rate, "rate", 0.0, "");
    try fs.stringSliceVar(&state, "tag", &.{}, "");

    try fs.parse(&.{ "--verbose", "--count=42", "--name=test", "--rate=3.14", "--tag=a", "--tag=b" });

    try testing.expect(verbose);
    try testing.expectEqual(@as(i32, 42), count);
    try testing.expectEqualStrings("test", name);
    try testing.expectApproxEqAbs(@as(f64, 3.14), rate, 0.01);
    try testing.expectEqual(@as(usize, 2), slice.items.len);
    try testing.expectEqualStrings("a", slice.items[0]);
    try testing.expectEqualStrings("b", slice.items[1]);
}

test "Complex real-world scenario" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var host: []const u8 = "localhost";
    var port: u32 = 8080;
    var workers: i32 = 4;
    var verbose: bool = false;
    var timeout: i64 = 30;
    var tags: std.ArrayListUnmanaged([]const u8) = .empty;
    var tag_state = pflag.StringSliceState{ .value = &tags, .gpa = testing.allocator };

    try fs.stringVar(&host, "host", "localhost", "server host");
    try fs.uintVar(u32, &port, "port", 8080, "server port");
    try fs.intVar(i32, &workers, "workers", 4, "number of workers");
    try fs.boolVar(&verbose, "verbose", false, "enable verbose logging");
    try fs.durationVar(&timeout, "timeout", 30, "request timeout");
    try fs.stringSliceVar(&tag_state, "tag", &.{}, "tags");

    try fs.parse(&.{
        "--host=0.0.0.0",
        "--port=3000",
        "--workers=8",
        "--verbose",
        "--timeout=60s",
        "--tag=production",
        "--tag=backend",
        "config.yaml",
    });

    try testing.expectEqualStrings("0.0.0.0", host);
    try testing.expectEqual(@as(u32, 3000), port);
    try testing.expectEqual(@as(i32, 8), workers);
    try testing.expect(verbose);
    try testing.expectEqual(@as(i64, 60000000000), timeout); // 60s in nanoseconds
    try testing.expectEqual(@as(usize, 2), tags.items.len);
    try testing.expectEqual(@as(usize, 1), fs.nArg());
    try testing.expectEqualStrings("config.yaml", fs.arg(0));
}

test "Map and slice combined" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;

    var headers: std.StringHashMapUnmanaged([]const u8) = .empty;
    var header_state = pflag.StringToStringState{ .value = &headers, .gpa = testing.allocator };
    var ports: std.ArrayListUnmanaged(i32) = .empty;
    var port_state = pflag.SliceState(i32){ .value = &ports, .gpa = testing.allocator };

    try fs.stringToStringVar(&header_state, "header", "", "HTTP headers");
    try fs.intSliceVar(i32, &port_state, "port", &.{}, "ports");

    try fs.parse(&.{
        "--header=Content-Type=application/json",
        "--header=Authorization=Bearer token",
        "--port=80",
        "--port=443",
        "--port=8080",
    });

    try testing.expectEqual(@as(u32, 2), headers.count());
    try testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
    try testing.expectEqualStrings("Bearer token", headers.get("Authorization").?);
    try testing.expectEqual(@as(usize, 3), ports.items.len);
    try testing.expectEqual(@as(i32, 80), ports.items[0]);
    try testing.expectEqual(@as(i32, 443), ports.items[1]);
    try testing.expectEqual(@as(i32, 8080), ports.items[2]);
}

// ── Comprehensive type parsing (from Go testParse) ──

test "Comprehensive type parsing" {
    var fs = newTestFlagSet();
    defer fs.deinit();

    // Define all flag types
    var bool_flag: bool = false;
    var bool2_flag: bool = false;
    var bool3_flag: bool = false;
    var int_flag: i32 = 0;
    var int8_flag: i8 = 0;
    var int16_flag: i16 = 0;
    var int32_flag: i32 = 0;
    var int64_flag: i64 = 0;
    var uint_flag: u32 = 0;
    var uint8_flag: u8 = 0;
    var uint16_flag: u16 = 0;
    var uint32_flag: u32 = 0;
    var uint64_flag: u64 = 0;
    var string_flag: []const u8 = "0";
    var float32_flag: f32 = 0;
    var float64_flag: f64 = 0;
    var duration_flag: i64 = 0;

    try fs.boolVar(&bool_flag, "bool", false, "bool value");
    try fs.boolVar(&bool2_flag, "bool2", false, "bool2 value");
    try fs.boolVar(&bool3_flag, "bool3", false, "bool3 value");
    try fs.intVar(i32, &int_flag, "int", 0, "int value");
    try fs.intVar(i8, &int8_flag, "int8", 0, "int8 value");
    try fs.intVar(i16, &int16_flag, "int16", 0, "int16 value");
    try fs.intVar(i32, &int32_flag, "int32", 0, "int32 value");
    try fs.intVar(i64, &int64_flag, "int64", 0, "int64 value");
    try fs.uintVar(u32, &uint_flag, "uint", 0, "uint value");
    try fs.uintVar(u8, &uint8_flag, "uint8", 0, "uint8 value");
    try fs.uintVar(u16, &uint16_flag, "uint16", 0, "uint16 value");
    try fs.uintVar(u32, &uint32_flag, "uint32", 0, "uint32 value");
    try fs.uintVar(u64, &uint64_flag, "uint64", 0, "uint64 value");
    try fs.stringVar(&string_flag, "string", "0", "string value");
    try fs.floatVar(f32, &float32_flag, "float32", 0, "float32 value");
    try fs.floatVar(f64, &float64_flag, "float64", 0, "float64 value");
    try fs.durationVar(&duration_flag, "duration", 0, "duration value");

    // Parse all flags at once (matches Go testParse)
    try fs.parse(&.{
        "--bool",
        "--bool2=true",
        "--bool3=false",
        "--int=22",
        "--int8=-8",
        "--int16=-16",
        "--int32=-32",
        "--int64=0x23",
        "--uint=24",
        "--uint8=8",
        "--uint16=16",
        "--uint32=32",
        "--uint64=25",
        "--string=hello",
        "--float32=-172e12",
        "--float64=2718e28",
        "--duration=2m",
    });

    // Verify all parsed values
    try testing.expectEqual(true, bool_flag);
    try testing.expectEqual(true, bool2_flag);
    try testing.expectEqual(false, bool3_flag);
    try testing.expectEqual(@as(i32, 22), int_flag);
    try testing.expectEqual(@as(i8, -8), int8_flag);
    try testing.expectEqual(@as(i16, -16), int16_flag);
    try testing.expectEqual(@as(i32, -32), int32_flag);
    try testing.expectEqual(@as(i64, 0x23), int64_flag);
    try testing.expectEqual(@as(u32, 24), uint_flag);
    try testing.expectEqual(@as(u8, 8), uint8_flag);
    try testing.expectEqual(@as(u16, 16), uint16_flag);
    try testing.expectEqual(@as(u32, 32), uint32_flag);
    try testing.expectEqual(@as(u64, 25), uint64_flag);
    try testing.expectEqualStrings("hello", string_flag);
    try testing.expectApproxEqRel(@as(f32, -172e12), float32_flag, @as(f32, 0.001));
    try testing.expectApproxEqRel(@as(f64, 2718e28), float64_flag, @as(f64, 0.001));
    try testing.expectEqual(@as(i64, 2 * std.time.ns_per_min), duration_flag);

    // Verify getter methods
    try testing.expectEqual(true, try fs.getBool("bool"));
    try testing.expectEqual(@as(i32, 22), try fs.getInt(i32, "int"));
    try testing.expectEqual(@as(i8, -8), try fs.getInt(i8, "int8"));
    try testing.expectEqual(@as(i16, -16), try fs.getInt(i16, "int16"));
    try testing.expectEqual(@as(i32, -32), try fs.getInt(i32, "int32"));
    try testing.expectEqual(@as(i64, 0x23), try fs.getInt(i64, "int64"));
    try testing.expectEqual(@as(u32, 24), try fs.getInt(u32, "uint"));
    try testing.expectEqual(@as(u8, 8), try fs.getInt(u8, "uint8"));
    try testing.expectEqual(@as(u16, 16), try fs.getInt(u16, "uint16"));
    try testing.expectEqual(@as(u32, 32), try fs.getInt(u32, "uint32"));
    try testing.expectEqual(@as(u64, 25), try fs.getInt(u64, "uint64"));
    const str = try fs.getString("string");
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("hello", str);
    try testing.expectApproxEqRel(@as(f32, -172e12), try fs.getFloat(f32, "float32"), @as(f32, 0.001));
    try testing.expectApproxEqRel(@as(f64, 2718e28), try fs.getFloat(f64, "float64"), @as(f64, 0.001));
}

test "Invalid argument returns error - bool" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var b: bool = false;
    try fs.boolVar(&b, "bool", false, "");
    const result = fs.parse(&.{"--bool=x"});
    try testing.expectError(error.InvalidBoolValue, result);
}

test "Invalid argument returns error - int" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var v: i32 = 0;
    try fs.intVar(i32, &v, "int", 0, "");
    // Parse should fail - just verify value is unchanged
    fs.parse(&.{"--int=x"}) catch {};
    try testing.expectEqual(@as(i32, 0), v); // value unchanged
}

test "Invalid argument returns error - uint" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var v: u32 = 0;
    try fs.uintVar(u32, &v, "uint", 0, "");
    const result = fs.parse(&.{"--uint=-1"});
    try testing.expectError(error.Overflow, result);
}

test "Invalid argument returns error - float" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var v: f64 = 0;
    try fs.floatVar(f64, &v, "float64", 0, "");
    // Parse should fail - just verify value is unchanged
    fs.parse(&.{"--float64=x"}) catch {};
    try testing.expectApproxEqAbs(@as(f64, 0), v, 0.001); // value unchanged
}

test "Unknown shorthand flag returns error" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var a: bool = false;
    try fs.boolVarP(&a, "alpha", "a", false, "");
    const result = fs.parse(&.{"-ukn"});
    try testing.expectError(error.NoSuchFlag, result);
    try testing.expectEqual(pflag.ParseError.ErrorKind.unknown_shorthand, fs.lastError().kind);
}

test "Shorthand requiring argument returns error" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var a: bool = false;
    var s: []const u8 = "";
    try fs.boolVarP(&a, "alpha", "a", false, "");
    try fs.stringVarP(&s, "string", "s", "", "");
    // -as means -a then -s, but -s needs a value and none follows
    const result = fs.parse(&.{"-as"});
    try testing.expectError(error.ValueRequired, result);
}

test "parseArgLoop handles consecutive value-consuming flags" {
    // Regression: parseArgLoop was refactored from orderedRemove(0) to index-based.
    // Verify that consecutive flags that each consume a value parse correctly.
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: []const u8 = "";
    var b: []const u8 = "";
    var c: []const u8 = "";
    try fs.stringVarP(&a, "alpha", "a", "", "");
    try fs.stringVarP(&b, "beta", "b", "", "");
    try fs.stringVarP(&c, "gamma", "g", "", "");

    // Long flags with space-separated values
    try fs.parse(&.{ "--alpha", "val1", "--beta", "val2", "--gamma", "val3" });
    try testing.expectEqualStrings("val1", a);
    try testing.expectEqualStrings("val2", b);
    try testing.expectEqualStrings("val3", c);
}

test "parseArgLoop handles mixed long and short flags with values" {
    // Verify index-based iteration handles mixed flag styles correctly
    var fs = newTestFlagSet();
    defer fs.deinit();
    var name: []const u8 = "";
    var count: i32 = 0;
    var output: []const u8 = "";
    try fs.stringVarP(&name, "name", "n", "", "");
    try fs.intVar(i32, &count, "count", 0, "");
    try fs.stringVarP(&output, "output", "o", "", "");

    // Mix of long and short flags, each consuming a value
    try fs.parse(&.{ "-n", "alice", "--count", "42", "-o", "result.txt" });
    try testing.expectEqualStrings("alice", name);
    try testing.expectEqual(@as(i32, 42), count);
    try testing.expectEqualStrings("result.txt", output);
}
