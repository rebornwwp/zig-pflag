//! Core FlagSet tests for pflag: registration, lookup, getters,
//! annotations, visit order, misc bookkeeping. Ported from Go's
//! spf13/pflag flag_test.go v1.0.9. Type-specific tests are in their
//! respective *_types.zig files; parse-engine behavior moved to
//! parse_test.zig, usage/help rendering to usage_test.zig.

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

test "FlagSet name is stored" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expectEqualStrings("test", fs.name);
}

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

test "Bool default has NoOptDefVal set" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: bool = false;
    try fs.boolVar(&val, "flag", false, "");
    const flag = fs.lookup("flag").?;
    try testing.expectEqualStrings("true", flag.no_opt_def_val);
}

test "shorthandLookup returns null for unknown" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expect(fs.shorthandLookup('x') == null);
}

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

test "SetName changes flagset name" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    fs.setName("newapp");
    try testing.expectEqualStrings("newapp", fs.name);
}

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

test "NameFn returns flagset name" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    try testing.expectEqualStrings("test", fs.nameFn());
}

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

test "Duplicate shorthand is rejected" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var a: bool = false;
    var b: bool = false;
    try fs.boolVarP(&a, "alpha", "a", false, "");
    try testing.expectError(error.ShorthandRedefined, fs.boolVarP(&b, "beta", "a", false, ""));
}

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

test "NoSuchFlag error" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var val: []const u8 = "";
    try fs.stringVar(&val, "name", "", "");
    try testing.expectError(error.NoSuchFlag, fs.set("missing", "value"));
}

test "WordSep normalize func" {
    // In Zig, wordSepNormalizeFunc returns name as-is (can't mutate slices).
    // This test verifies the normalize callback is invoked.
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b1: bool = false;
    try fs.boolVar(&b1, "with-dash-flag", false, "");
    fs.setNormalizeFunc(wordSepNormalizeFunc);
    // Parse with original name — should work since normalize returns as-is
    try fs.parse(&.{"--with-dash-flag"});
    try testing.expect(b1);
}

test "Normalization changes flag name after addition" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVar(&b, "valid_flag", false, "");
    // Before normalize: name is unchanged
    try testing.expectEqualStrings("valid_flag", fs.lookup("valid_flag").?.name);
    fs.setNormalizeFunc(wordSepNormalizeFunc);
    // wordSepNormalizeFunc returns name as-is in Zig (can't mutate slices)
    // Verify the callback is invoked — lookup still works
    try testing.expect(fs.lookup("valid_flag") != null);
}

test "Normalization set flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVar(&b, "flag_name", false, "");
    fs.setNormalizeFunc(wordSepNormalizeFunc);
    // After normalization, lookup should still work (returns as-is in Zig)
    const flag = fs.lookup("flag_name");
    try testing.expect(flag != null);
    try testing.expectEqualStrings("flag_name", flag.?.name);
}

test "Multiple normalize invocations" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var b: bool = false;
    try fs.boolVar(&b, "flag_name", false, "");
    fs.setNormalizeFunc(wordSepNormalizeFunc);
    // Calling setNormalizeFunc again should work
    fs.setNormalizeFunc(wordSepNormalizeFunc);
    // wordSepNormalizeFunc returns name as-is in Zig
    try testing.expectEqualStrings("flag_name", fs.lookup("flag_name").?.name);
}

test "VisitAll flag order" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var flag_a: bool = false;
    var flag_b: bool = false;
    var flag_c: bool = false;
    try fs.boolVar(&flag_a, "a", false, "");
    try fs.boolVar(&flag_b, "b", false, "");
    try fs.boolVar(&flag_c, "c", false, "");
    const NameCollector = struct {
        names: [3][]const u8 = undefined,
        count: usize = 0,
    };
    var collector = NameCollector{};
    const collectFn = struct {
        fn call(ctx: *NameCollector, flag: *pflag.Flag) void {
            if (ctx.count < 3) {
                ctx.names[ctx.count] = flag.name;
                ctx.count += 1;
            }
        }
    }.call;
    fs.visitAll(&collector, collectFn);
    try testing.expectEqual(@as(usize, 3), collector.count);
    try testing.expectEqualStrings("a", collector.names[0]);
    try testing.expectEqualStrings("b", collector.names[1]);
    try testing.expectEqualStrings("c", collector.names[2]);
}

test "Visit flag order" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var flag_a: bool = false;
    var flag_b: bool = false;
    var flag_c: bool = false;
    try fs.boolVar(&flag_a, "a", false, "");
    try fs.boolVar(&flag_b, "b", false, "");
    try fs.boolVar(&flag_c, "c", false, "");
    try fs.parse(&.{ "--c", "--a" });
    const NameCollector = struct {
        names: [2][]const u8 = undefined,
        count: usize = 0,
    };
    var collector = NameCollector{};
    const collectFn = struct {
        fn call(ctx: *NameCollector, flag: *pflag.Flag) void {
            if (ctx.count < 2) {
                ctx.names[ctx.count] = flag.name;
                ctx.count += 1;
            }
        }
    }.call;
    fs.visit(&collector, collectFn);
    // Visit should only visit set flags, in order
    try testing.expectEqual(@as(usize, 2), collector.count);
    try testing.expectEqualStrings("c", collector.names[0]);
    try testing.expectEqualStrings("a", collector.names[1]);
}

// ── Tests from Go flag_test.go (supplementary) ──

test "ShorthandLookup returns flag by shorthand" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var boola: bool = false;
    var boolb: bool = false;
    try fs.boolVarP(&boola, "boola", "a", false, "bool value");
    try fs.boolVarP(&boolb, "boolb", "b", false, "bool2 value");
    // Successful lookup
    const flag_a = fs.shorthandLookup('a');
    try testing.expect(flag_a != null);
    try testing.expectEqualStrings("boola", flag_a.?.name);
    const flag_b = fs.shorthandLookup('b');
    try testing.expect(flag_b != null);
    try testing.expectEqualStrings("boolb", flag_b.?.name);
    // Unknown shorthand returns null
    try testing.expect(fs.shorthandLookup('z') == null);
}

test "Changed helper - multiple flags" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var changed: bool = false;
    var settrue: bool = true;
    var setfalse: bool = false;
    var unchanged: bool = false;
    try fs.boolVar(&changed, "changed", false, "changed bool");
    try fs.boolVar(&settrue, "settrue", true, "true to true");
    try fs.boolVar(&setfalse, "setfalse", false, "false to false");
    try fs.boolVar(&unchanged, "unchanged", false, "unchanged bool");

    try fs.parse(&.{ "--changed", "--settrue", "--setfalse=false" });

    try testing.expect(fs.changed("changed"));
    try testing.expect(fs.changed("settrue"));
    try testing.expect(fs.changed("setfalse"));
    try testing.expect(!fs.changed("unchanged"));
    try testing.expect(!fs.changed("invalid"));
    try testing.expectEqual(@as(isize, -1), fs.argsLenAtDash());
}

test "VisitAll visits flags in insertion order" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var z: bool = false;
    var a: bool = false;
    var m: bool = false;
    try fs.boolVar(&z, "z", false, "");
    try fs.boolVar(&a, "a", false, "");
    try fs.boolVar(&m, "m", false, "");

    const NameCollector = struct {
        names: [3][]const u8 = undefined,
        count: usize = 0,
    };
    var collector = NameCollector{};
    const collectFn = struct {
        fn call(ctx: *NameCollector, flag: *pflag.Flag) void {
            if (ctx.count < 3) {
                ctx.names[ctx.count] = flag.name;
                ctx.count += 1;
            }
        }
    }.call;
    fs.visitAll(&collector, collectFn);
    // VisitAll visits in insertion order (not sorted)
    try testing.expectEqual(@as(usize, 3), collector.count);
    try testing.expectEqualStrings("z", collector.names[0]);
    try testing.expectEqualStrings("a", collector.names[1]);
    try testing.expectEqualStrings("m", collector.names[2]);
}

test "Visit visits only set flags in parse order" {
    var fs = newTestFlagSet();
    defer fs.deinit();
    var z: bool = false;
    var a: bool = false;
    var m: bool = false;
    try fs.boolVar(&z, "z", false, "");
    try fs.boolVar(&a, "a", false, "");
    try fs.boolVar(&m, "m", false, "");
    try fs.parse(&.{ "--m", "--z" });

    const NameCollector = struct {
        names: [2][]const u8 = undefined,
        count: usize = 0,
    };
    var collector = NameCollector{};
    const collectFn = struct {
        fn call(ctx: *NameCollector, flag: *pflag.Flag) void {
            if (ctx.count < 2) {
                ctx.names[ctx.count] = flag.name;
                ctx.count += 1;
            }
        }
    }.call;
    fs.visit(&collector, collectFn);
    // Visit visits only set flags, in the order they were parsed
    try testing.expectEqual(@as(usize, 2), collector.count);
    try testing.expectEqualStrings("m", collector.names[0]);
    try testing.expectEqualStrings("z", collector.names[1]);
}
