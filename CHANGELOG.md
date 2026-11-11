# Changelog

All notable changes to zig-pflag will be documented in this file.

## [Unreleased]

### Added

- `zig build run-examples` step to run all 12 allocator examples at once
- Individual `zig build run-<name>` steps for each allocator example (e.g., `run-int_gpa`, `run-string_arena`)
- `zig build docs` step: HTML API documentation via the compiler's `-femit-docs` bundle (index.html + wasm viewer + sources.tar for every reachable module) written to `zig-out/docs`; opt-in, not part of the CI sequence
- Full `///` documentation coverage for the public API surface (every `Flag`/`FlagSet` field and method incl. all 40+ registration helpers, `Value`/`VTable` methods, the 16 `xxxValue` constructors, global `*CL` helpers, and the top-level entry-shell semantics — parse defaults, ownership contracts, Zig-vs-Go divergences like radix-0 leading zeros and silent float saturation); mechanically verified as comment-only changes with the 209-test suite green
- 98 new tests (110 → 208 total) covering:
  - Complete slice type test suites (int32/int64/uint/float32/float64/bool/int/string_slice/string_array)
  - Error path tests (invalid values, overflow, unknown flags)
  - Boundary condition tests (empty values, Unicode, negative numbers, scientific notation)
  - Integration tests (mixed flag types, real-world scenarios)
  - Remaining Go pflag tests (BoolP, StringSlice, StringArray, Usage formatting)
- Post-refactor scalar coverage expansion (expectations measured against actual Zig 0.17 behavior) —
  suite total 205 → 209 blocks, hundreds of new table cases:
  - `int_types.zig`: radix-0 forms (`+42`, `0X2A`, `0b101010`, underscores, and the Zig-vs-Go divergence that a leading `0` stays DECIMAL: `010` → 10), glued/`=`/separate shorthand syntax, full min/max bounds + off-by-one overflow across i8/i16/i32/i64, six invalid forms per width, `string()` decimal normalization incl. `@typeName`
  - `uint_types.zig`: same matrix for u8–u64 plus `-1`/`-9999` → Overflow and `-0` → 0 signed-zero edge
  - `float_types.zig`: `.5`/`5.`/`1E3`/exponents/underscores, specials (`inf`/`-Inf`/`infinity`/`NaN` lowercase forms), silent saturation documented (`1e400` → +inf, `1e-400` → 0, f32 `4e38` → inf, no ErrRange like Go), decimal `string()` forms (`1e20` → `100000000000000000000`)
  - `bool_types.zig`: extra spellings (`T`/`F`/`tRuE`), direct-`set()` forms incl. empty-string-is-true
  - `count_types.zig`: explicit negative/hex/plus values, `=N`-then-bare increment composition, typeName assertion
  - `duration_types.zig`: negative/plus/zero values, malformed-input taxonomy (`InvalidDuration` vs `InvalidCharacter` vs parse-stage `Overflow`)
  - `slice_types.zig`: radix-0/underscore/negative/exponent elements in int/uint/float slice sets

### Changed

- **Minimum Zig version is now 0.17.0** (tagged `v0.16.0` marks the last Zig 0.16.x release)
- Build system: `if (b.args) |args| run.addArgs(args)` replaced with `run.addPassthruArgs()` (Zig 0.17 build system maker/configurer separation)
- `std.fmt.allocPrint(gpa, ...)` replaced with `gpa.print(...)` (moved to `std.mem.Allocator` in Zig 0.17)
- `gpa` examples migrated from deprecated `std.heap.DebugAllocator` to thread-safe `std.heap.SafeAllocator`
- `build.zig.zon`: `minimum_zig_version` bumped to `0.17.0`
- **Layered internal refactor** — public API frozen (everything stays reachable through `pflag.zig`, examples and downstream users need no change); file layout now deliberately deviates from upstream's monolithic flag.go:
  - `Value` interface (`ptr` + `VTable`) moved from `src/pflag.zig` to new `src/value.zig`; the nine `*_types.zig` import the interface directly, removing `pflag.zig ⇄ *_types.zig` import cycles
  - new `src/internal.zig` leaf module owns shared `parseBool`, `readAsCSV`/`writeAsCSV`, and `splitKeyValue`; `slice_types` no longer imports `bool_types`
- **BREAKING (pre-0.1 window): public surface shrunk 51 → 44 → 27 root names.** Stage one: the module namespace tables `pflag.errors` and the nine `pflag.<kind>_types` are withdrawn and become file-private imports; helpers migrated to flat paths (`pflag.bool_types.parseBool` → `pflag.parseBool`; `pflag.slice_types.readAsCSV`/`writeAsCSV` → flat). Stage two: the type-erasure extension chain — `pflag.Value`, the 16 `xxxValue` ctors, `FlagSet.varP` and `FlagSet.addFlag` — is demoted to internal plumbing (all in-repo examples/tests referenced none of them; the README never promised them). Rationale: the port exposes basic functionality only; new flag kinds are contributed as `*_types.zig` files (AGENTS.md checklist) importing `value.zig` at source level, rather than downstream vtable implementations. `Flag`/`FlagSet` stay public (returned and consumed by `lookup`/`visit`/registration); the six public State structs stay (callers construct them). Custom-value extension can be reinstated additively if demand appears.
  - usage/help rendering extracted to `src/usage.zig`; the previously duplicated string-based and writer-based render stacks were unified behind `std.Io.Writer` (its user-visible consequence is listed separately below — it is not purely internal)
  - the process-global CommandLine singleton and `*CL` helpers moved to `src/cmdline.zig`, flat-re-exported from `pflag.zig` (the flat names are the only public access; `pflag.cmdline` itself is file-private)
  - the parse engine (`argLoop`/`longArg`/`shortArg`, `applyValue`/`doFailWith`/`markParsed`) lives in `src/parse.zig` as free functions taking `*FlagSet`; `FlagSet.parse`/`parseAll` are thin delegating shells; `pflag.zig` shrank 879 → ~560 lines
  - int/uint/float slice vtables now share `makeNumSliceVtable(T, comptime parse)`; behavior unchanged (the 205-test suite stayed green throughout, zero test edits)
  - `src/pflag_test.zig` split by concern: parse-engine tests → `parse_test.zig` (42), usage-rendering tests → `usage_test.zig` (28), shared helpers → `testutil.zig`, core registry/getter tests stay in `pflag_test.zig` (46)
- **User-visible text change in usage output** (result of unifying the duplicated render stacks, worth calling out despite living under "internal"): `FlagUsages`/`FlagUsagesWrapped` now render deprecated flags as `" (deprecated: msg)"`, matching `PrintDefaults`; previously the string-returning path emitted only `" (deprecated)"` with no message. If you diff help text or snapshot it, this line changes.

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
