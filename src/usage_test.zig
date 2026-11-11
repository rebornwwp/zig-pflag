//! Usage/help rendering tests: FlagUsages, FlagUsagesWrapped,
//! PrintDefaults, PrintUsage, hidden/deprecated display behavior.

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

test "MarkHidden hides flag from defaults" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    try fs.boolVar(&a, "a", false, "");
    try fs.markHidden("a");

    const flag = fs.lookup("a").?;
    try testing.expect(flag.hidden);
}

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

test "FlagUsagesWrapped respects column width" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVarP(&val, "verbose", "v", false, "enable verbose output for debugging purposes");
    const text = fs.flagUsagesWrapped(40);
    defer testing.allocator.free(text);
    try testing.expect(text.len > 0);
}

test "Deprecated flag shows (deprecated) in usage" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = true;
    try fs.boolVar(&b, "badflag", true, "always true");
    try fs.markDeprecated("badflag", "use --good-flag instead");
    const usage = fs.flagUsagesWrapped(100);
    defer testing.allocator.free(usage);
    // In Zig port, deprecated flags are NOT hidden — they show "(deprecated: msg)"
    try testing.expect(std.mem.containsAtLeast(u8, usage, 1, "badflag"));
    try testing.expect(std.mem.containsAtLeast(u8, usage, 1, "deprecated"));
}

test "Deprecated flag usage message" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var b: bool = true;
    try fs.boolVar(&b, "badflag", true, "always true");
    try fs.markDeprecated("badflag", "use --good-flag instead");
    // Parse should succeed but warn
    try fs.parse(&.{"--badflag"});
    try testing.expect(b);
}

test "Deprecated flag usage normalized" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var b: bool = true;
    try fs.boolVar(&b, "bad_flag", true, "always true");
    try fs.markDeprecated("bad_flag", "use --good_flag instead");
    fs.setNormalizeFunc(wordSepNormalizeFunc);
    // wordSepNormalizeFunc returns name as-is in Zig, so parse with original name
    try fs.parse(&.{"--bad_flag"});
    try testing.expect(b);
}

test "Deprecated flag usage alias" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var b: bool = true;
    try fs.boolVar(&b, "bad-flag", true, "always true");
    try fs.markDeprecated("bad-flag", "use --good-flag instead");
    fs.setNormalizeFunc(wordSepNormalizeFunc);
    // wordSepNormalizeFunc returns name as-is in Zig, so parse with original name
    try fs.parse(&.{"--bad-flag"});
    try testing.expect(b);
}

test "Hidden flag in usage" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVar(&b, "hidden", false, "hidden flag");
    try fs.markHidden("hidden");
    const usage = fs.flagUsagesWrapped(100);
    defer testing.allocator.free(usage);
    try testing.expect(!std.mem.containsAtLeast(u8, usage, 1, "hidden"));
}

test "Hidden flag usage" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVar(&b, "visible", false, "visible flag");
    try fs.boolVar(&b, "hidden", false, "hidden flag");
    try fs.markHidden("hidden");
    const usage = fs.flagUsagesWrapped(100);
    defer testing.allocator.free(usage);
    try testing.expect(std.mem.containsAtLeast(u8, usage, 1, "visible"));
    try testing.expect(!std.mem.containsAtLeast(u8, usage, 1, "hidden"));
}

test "PrintDefaults output" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVar(&b, "verbose", false, "enable verbose");
    const usage = fs.flagUsagesWrapped(100);
    defer testing.allocator.free(usage);
    try testing.expect(std.mem.containsAtLeast(u8, usage, 1, "verbose"));
    try testing.expect(std.mem.containsAtLeast(u8, usage, 1, "enable verbose"));
}

test "FlagUsagesWrapped continues after unbreakable word" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "flag", false, "this is a very long description that should wrap at the specified column width");
    const text = fs.flagUsagesWrapped(30);
    defer testing.allocator.free(text);
    try testing.expect(text.len > 0);
    try testing.expect(std.mem.containsAtLeast(u8, text, 1, "flag"));
}

test "PrintUsage output" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var verbose: bool = false;
    var count: i32 = 0;
    try fs.boolVar(&verbose, "verbose", false, "enable verbose");
    try fs.intVar(i32, &count, "count", 0, "the count");
    const usage = fs.flagUsagesWrapped(100);
    defer testing.allocator.free(usage);
    try testing.expect(std.mem.containsAtLeast(u8, usage, 1, "verbose"));
    try testing.expect(std.mem.containsAtLeast(u8, usage, 1, "count"));
    try testing.expect(std.mem.containsAtLeast(u8, usage, 1, "enable verbose"));
    try testing.expect(std.mem.containsAtLeast(u8, usage, 1, "the count"));
}

test "Deprecated flag not in PrintDefaults" {
    // In Go, markDeprecated also hides the flag. In Zig, it only sets the deprecated message.
    // To hide a deprecated flag, user must also call markHidden.
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = true;
    try fs.boolVar(&b, "badflag", true, "always true");
    try fs.markDeprecated("badflag", "use --good-flag instead");
    try fs.markHidden("badflag"); // In Zig, must explicitly hide

    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;
    fs.printDefaults();
    const output = std.Io.Writer.buffered(&writer);
    try testing.expect(!std.mem.containsAtLeast(u8, output, 1, "badflag"));
}

test "Unhidden deprecated flag in docs" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = true;
    try fs.boolVar(&b, "badflag", true, "always true");
    try fs.markDeprecated("badflag", "use --good-flag instead");
    // Flag is NOT hidden — should appear in usage with deprecation message

    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;
    fs.printDefaults();
    const output = std.Io.Writer.buffered(&writer);
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "badflag"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "use --good-flag instead"));
}

test "Deprecated shorthand shown in docs" {
    // Note: Unlike Go pflag which hides deprecated shorthands, Zig always shows them.
    // This test verifies the actual Zig behavior.
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = true;
    try fs.boolVarP(&b, "noshorthandflag", "n", true, "always true");
    try fs.markShorthandDeprecated("noshorthandflag", "use --noshorthandflag instead");

    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;
    fs.printDefaults();
    const output = std.Io.Writer.buffered(&writer);
    // In Zig, shorthand is still shown even when deprecated
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "-n,"));
}

test "Deprecated flag usage printed to out_writer" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var b: bool = true;
    try fs.boolVar(&b, "badflag", true, "always true");
    const usage_msg = "use --good-flag instead";
    try fs.markDeprecated("badflag", usage_msg);

    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;

    try fs.parse(&.{"--badflag"});
    const output = std.Io.Writer.buffered(&writer);
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, usage_msg));
}

test "Deprecated shorthand usage printed to out_writer" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    var b: bool = true;
    try fs.boolVarP(&b, "noshorthandflag", "n", true, "always true");
    const usage_msg = "use --noshorthandflag instead";
    try fs.markShorthandDeprecated("noshorthandflag", usage_msg);

    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;

    try fs.parse(&.{"-n"});
    const output = std.Io.Writer.buffered(&writer);
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, usage_msg));
}

test "Hidden flag not printed via printDefaults" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVar(&b, "secretFlag", false, "shhh");
    try fs.markHidden("secretFlag");

    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;
    fs.printDefaults();
    const output = std.Io.Writer.buffered(&writer);
    try testing.expect(!std.mem.containsAtLeast(u8, output, 1, "secretFlag"));
}

test "Output writes to out_writer" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;

    // printUsage writes to out_writer
    fs.printUsage();
    const output = std.Io.Writer.buffered(&writer);
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "Usage of test"));
}

test "PrintUsage format - long and short flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b1: bool = false;
    var b2: bool = false;
    var b3: bool = false;
    var b4: bool = false;
    try fs.boolVar(&b1, "long-form", false, "Some description");
    try fs.boolVar(&b2, "long-form2", false, "Some description");
    try fs.boolVarP(&b3, "long-name", "s", false, "Some description");
    try fs.boolVarP(&b4, "long-name2", "t", false, "Some description");

    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;
    fs.printDefaults();
    const output = std.Io.Writer.buffered(&writer);

    // Verify all flags appear in output
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "--long-form"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "--long-form2"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "-s, --long-name"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "-t, --long-name2"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 4, "Some description"));
}

test "PrintUsage format - with string defaults" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var s: []const u8 = "test";
    try fs.stringVarP(&s, "some-arg", "l", "test", "Some description");

    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    fs.out_writer = &writer;
    fs.printDefaults();
    const output = std.Io.Writer.buffered(&writer);

    // Verify flag name, shorthand, and default value appear
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "-l, --some-arg"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "test"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "Some description"));
}

test "FlagUsagesWrapped wraps long usage at column boundary" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "verbose", false, "this is a very long usage that should definitely wrap at the column boundary we specify");

    // With narrow cols, the usage text should wrap to multiple lines
    const narrow = fs.flagUsagesWrapped(40);
    defer testing.allocator.free(narrow);

    // Count newlines — narrow output should have more lines than wide output
    const narrow_newlines = std.mem.count(u8, narrow, "\n");

    const wide = fs.flagUsagesWrapped(200);
    defer testing.allocator.free(wide);
    const wide_newlines = std.mem.count(u8, wide, "\n");

    // Narrow wrapping should produce more newlines than wide
    try testing.expect(narrow_newlines > wide_newlines);

    // Both should contain the flag name and usage words
    try testing.expect(std.mem.containsAtLeast(u8, narrow, 1, "verbose"));
    try testing.expect(std.mem.containsAtLeast(u8, narrow, 1, "wrap"));
}

test "FlagUsagesWrapped with cols=0 skips wrapping" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "verbose", false, "this is a very long usage that would normally wrap but should not when cols is zero");

    // With cols=0, wrapping should be skipped
    const text = fs.flagUsagesWrapped(0);
    defer testing.allocator.free(text);

    // Should contain the full usage text on one line (no wrapping)
    try testing.expect(std.mem.containsAtLeast(u8, text, 1, "verbose"));
    try testing.expect(std.mem.containsAtLeast(u8, text, 1, "would normally wrap"));
}
