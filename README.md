# zig-pflag

POSIX/GNU-style flag parsing for Zig, ported from Go's [spf13/pflag](https://github.com/spf13/pflag) v1.0.9.

Zig 0.16.0 · 12 source files · 910 lines · 87 tests

## Quick Start

```zig
const std = @import("std");
const pflag = @import("pflag");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var fs = pflag.FlagSet.init(gpa, "myapp");
    defer fs.deinit();

    var verbose: bool = false;
    var name: []const u8 = "world";
    var count: i32 = 0;

    try fs.boolVarP(&verbose, "verbose", "v", false, "enable verbose output");
    try fs.stringVarP(&name, "name", "n", "world", "your name");
    try fs.intVar(i32, &count, "count", 42, "the count");

    // Read args, skip program name
    const alloc = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(alloc);
    const effective = if (raw.len > 1) raw[1..] else &.{};
    try fs.parse(effective);

    // Use parsed values
    if (verbose) std.debug.print("verbose mode on\n", .{});
    std.debug.print("hello {s}! count={d}\n", .{ name, count });
    std.debug.print("remaining args: {any}\n", .{fs.argList()});
}
```

## Supported Flag Types

| Type | Construction | Parse `--flag=value` / `-f value` |
|------|-------------|-----------------------------------|
| bool | `boolVarP(p, "verbose", "v", false, "")` | `-v` / `--verbose` / `--verbose=true` |
| int i8–i64 | `intVar(i32, p, "count", 0, "")` | `--count=42` / `--count 42` |
| uint u8–u64 | `uintVar(u32, p, "port", 0, "")` | `--port=8080` |
| float f32/f64 | `floatVar(f64, p, "rate", 0, "")` | `--rate=3.14` |
| string | `stringVarP(p, "name", "n", "", "")` | `--name Alice` / `-n Alice` |
| count | `countVarP(p, "v", "v", 0, "")` | `-vvv` (value = 3) |
| duration | `durationVar(p, "timeout", 0, "")` | `--timeout=30s` (ns) |
| stringSlice | `stringSliceVarP(p, "tag", "t", &.{}, "")` | `-t a -t b` |
| intSlice | `intSliceVar(i32, p, "port", &.{}, "")` | `--port=80 --port=443` |
| boolSlice | `boolSliceVar(p, "flag", &.{}, "")` | `--flag --flag` |
| floatSlice | `floatSliceVar(f64, p, "v", &.{}, "")` | `--v=1.0 --v=2.5` |
| uintSlice | `uintSliceVar(u32, p, "p", &.{}, "")` | `--p=80 --p=443` |
| stringToInt | `stringToIntVar(p, "h", 0, "")` | `--h=a=1 --h=b=2` |
| stringToString | `stringToStringVar(p, "l", "", "")` | `--l=env=prod` |

## Demo

A fully working example demonstrating every flag type is included in `demo/main.zig`.

### Run with default values

```bash
zig build run-demo
```

### Run with all flag types exercised

```bash
zig build run-demo -- \
  -v \
  --count=42 \
  --big=9999999999 \
  -p 9090 \
  --rate=3.14 \
  --name=zig \
  -VVV \
  --timeout=30s \
  -t web -t api -t v2 \
  --expose=80 --expose=443 --expose=8080 \
  --flag --flag --flag \
  --score=9.5 --score=8.0 --score=7.5 \
  --header=Content-Length=100 --header=X-Timeout=30 \
  --label=env=prod --label=region=us-east \
  arg1 arg2 arg3
```

### Expected output

```
Flag defaults (before parsing)
  -v, --verbose
    	enable verbose output
      --count=0
    	the count (int32)
      --big=0
    	64-bit integer (deprecated: use --count instead)
  -p, --port=8080
    	port number
      --rate=1
    	request rate
  -n, --name=world
    	your name
  -V, --verbosity=0
    	verbosity level
      --timeout=0s
    	timeout (30s/5m/2h/1d)
  -t, --tag
    	tags (repeatable)
      --expose
    	exposed ports
      --flag
    	bool flags
      --score
    	scores
      --header
    	headers as key=value
      --label
    	labels as key=value

Parsed values
  verbose  = true
  count    = 42
  big      = 9999999999
  port     = 9090
  rate     = 3.14
  name     = zig
  verbosity= 3
  timeout  = 30000000000

Slice values
  tag = default
  tag = web
  tag = api
  tag = v2
  expose = 80
  expose = 443
  expose = 8080
  score = 9.5
  score = 8
  score = 7.5

Map values
  X-Timeout = 30
  Content-Length = 100
  env = prod
  region = us-east

Positional args
  arg1
  arg2
  arg3

Flags that were set
  --verbose (changed=true)
  --count (changed=true)
  --big (changed=true)
  --port (changed=true)
  --rate (changed=true)
  --name (changed=true)
  --verbosity (changed=true)
  --timeout (changed=true)
  --tag (changed=true)
  --expose (changed=true)
  --flag (changed=true)
  --score (changed=true)
  --header (changed=true)
  --label (changed=true)

  nFlag() = 14, changed(verbose) = true

Flag usages (text)
  -v, --verbose
    	enable verbose output
      --count=0
    	the count (int32)
      --big=0
    	64-bit integer (deprecated)
  -p, --port=8080
    	port number
      --rate=1
    	request rate
  -n, --name=world
    	your name
  -V, --verbosity=0
    	verbosity level
      --timeout=0s
    	timeout (30s/5m/2h/1d)
  -t, --tag
    	tags (repeatable)
      --expose
    	exposed ports
      --flag
    	bool flags
      --score
    	scores
      --header
    	headers as key=value
      --label
    	labels as key=value
  annotation[name][category] = basic
```

## FlagSet API

| Method | Description |
|--------|-------------|
| `parse(args)` | Parse `[]const []const u8` argument list |
| `parseAll(args, callback)` | Parse with custom per-flag callback |
| `lookup(name)` | Find flag by name |
| `shorthandLookup(c)` | Find flag by shorthand char |
| `set(name, value)` | Set flag value programmatically |
| `changed(name)` | Check if flag was set by user |
| `arg(i)` | Get i‑th positional argument |
| `argList()` / `nArg()` | Positional args after flags |
| `nFlag()` | Count of flags that were set |
| `visit(ctx, fn)` / `visitAll(ctx, fn)` | Iterate set/all flags |
| `markHidden(name)` | Hide flag from usage |
| `markDeprecated(name, msg)` | Mark flag as deprecated |
| `markShorthandDeprecated(name, msg)` | Mark shorthand as deprecated |
| `setAnnotation(name, key, values)` | Attach metadata to flag |
| `getAnnotation(name, key)` | Read flag metadata |
| `flagUsages()` / `printDefaults()` | Format / print usage text |
| `setNormalizeFunc(fn)` | Custom flag name normalizer |
| `getNormalizeFunc()` | Get current normalizer |
| `addFlagSet(other)` | Merge another FlagSet |
| `hasFlags()` / `hasAvailableFlags()` | Query flag state |
| `lastError()` | Details of last parse error |

## File Layout

```
src/
├── pflag.zig          # Value, Flag, FlagSet, parse engine
├── errors.zig         # ParseError, ErrorHandling
├── bool_types.zig     # Bool flag type
├── int_types.zig      # Int types (i8–i64, comptime-generic)
├── uint_types.zig     # Uint types (u8–u64)
├── float_types.zig    # Float types (f32/f64)
├── string_types.zig   # String flag type
├── count_types.zig    # Count flag type
├── duration_types.zig # Duration type (s/m/h/d)
├── slice_types.zig    # string/int/uint/bool/float slices
├── map_types.zig      # string→int, string→string maps
└── pflag_test.zig     # 87 tests
```

## Usage with zig-cobra

```zig
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;

var flags = pflag.FlagSet.init(allocator, "mycmd");
defer flags.deinit();
var name: []const u8 = "world";
flags.stringVarP(&name, "name", "n", "world", "your name") catch {};

var cmd = cobra.Command{
    .use   = "mycmd",
    .short = "A CLI app",
    .flags = &flags,
    .run   = myRunFn,
};
```

## License

MIT
