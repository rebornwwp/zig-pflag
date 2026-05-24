# Changelog

All notable changes to zig-pflag will be documented in this file.

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
