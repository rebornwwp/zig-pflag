# Changelog

All notable changes to zig-pflag will be documented in this file.

## [Unreleased]

### Added

- `zig build run-examples` step to run all 12 allocator examples at once
- Individual `zig build run-<name>` steps for each allocator example (e.g., `run-int_gpa`, `run-string_arena`)
- 98 new tests (110 → 208 total) covering:
  - Complete slice type test suites (int32/int64/uint/float32/float64/bool/int/string_slice/string_array)
  - Error path tests (invalid values, overflow, unknown flags)
  - Boundary condition tests (empty values, Unicode, negative numbers, scientific notation)
  - Integration tests (mixed flag types, real-world scenarios)
  - Remaining Go pflag tests (BoolP, StringSlice, StringArray, Usage formatting)

### Changed

- **Minimum Zig version is now 0.17.0** (tagged `v0.16.0` marks the last Zig 0.16.x release)
- Build system: `if (b.args) |args| run.addArgs(args)` replaced with `run.addPassthruArgs()` (Zig 0.17 build system maker/configurer separation)
- `std.fmt.allocPrint(gpa, ...)` replaced with `gpa.print(...)` (moved to `std.mem.Allocator` in Zig 0.17)
- `gpa` examples migrated from deprecated `std.heap.DebugAllocator` to thread-safe `std.heap.SafeAllocator`
- `build.zig.zon`: `minimum_zig_version` bumped to `0.17.0`

## [0.1.0] - 2026-05-24

### Added

- Initial port of Go's [spf13/pflag v1.0.9](https://github.com/spf13/pflag) to Zig 0.16.0
- POSIX/GNU-style flag parsing with `--long` and `-s` shorthand support
- 14 flag types covering basic, slice, and map types:
  - Basic: `bool`, `int` (i8–i64), `uint` (u8–u64), `float` (f32/f64), `string`, `count`, `duration`
  - Slice: `stringSlice`, `stringArray`, `intSlice`, `uintSlice`, `boolSlice`, `floatSlice`
  - Map: `stringToInt` (comptime-generic: i32/i64/u32/u64), `stringToString`
- Comptime-generic type constructors (`intVar(T)`, `uintVar(T)`, `floatVar(T)`, `stringToIntVar(T)`)
- `FlagSet` API: `parse`, `parseAll`, `lookup`, `shorthandLookup`, `set`, `changed`, `arg`/`argList`/`nArg`, `nFlag`, `visit`/`visitAll`, `markHidden`, `markDeprecated`, `markShorthandDeprecated`, `setAnnotation`/`getAnnotation`, `flagUsages`/`printDefaults`, `setNormalizeFunc`, `addFlagSet`, `hasFlags`/`hasAvailableFlags`, `lastError`
- Error handling modes: `continue_on_error`, `exit_on_error`, `panic_on_error`
- Parse errors allowlist (`unknown_flags`, `help`)
- Comptime-generic `stringToInt` supporting `i32`, `i64`, `u32`, `u64`
- Cross-platform `std.Io.Writer` support (no Linux-specific syscalls)
- Memory-safe: all flag types clean up allocated memory via `FlagSet.deinit()`
- 89 tests ported and adapted from Go pflag test suite
- Full demo application exercising all flag types (`zig build run-demo`)

### Fixed

- `std.os.linux.write` replaced with cross-platform `std.Io.Writer` for stdout output
- Memory leaks eliminated across all value types (proper `deinit` implementations)
