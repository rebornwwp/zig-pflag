# Changelog

All notable changes to zig-pflag will be documented in this file.

## [Unreleased]

### Added

- `zig build run-examples` step to run all 18 allocator examples at once
- Individual `zig build run-<name>` steps for each allocator example (e.g., `run-int_gpa`, `run-string_arena`)
- Three `std.heap.smp_allocator` examples (`int`/`string`/`floatSlice`) joining the allocator matrix: the thread-safe process-wide singleton is exercised in the same 3×6 type/allocator layout, bringing `build-examples` from 15 to 18 executables
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
- Round-two coverage of the parse-form matrix (suite 209 → 210; the only behavior edit is the slice atomicity fix listed under Changed):
  - `slice_types.zig`: new error-path test — a bad/overflowing element goes through `FlagSet.parse` and surfaces the scalar error kinds (`InvalidCharacter`/`Overflow`/`InvalidBoolValue`) for all four of int/uint/float/bool slices, with assertions that the slice partially populated by a failed parse stays untouched (defaults and previously parsed values) and that the first-Set-replaces `changed` state survives a failure; empty fields in `a,,b` still skip
  - `bool_types.zig`: the `BoolVar` table gains shorthand-with-equals spellings (`-v=false`/`-v=true`) — the `=` strip runs BEFORE `NoOptDefVal`, so bare `-v` is true while `-v=false` is false (matches Go)
  - `parse_test.zig`: the invalid-argument paths now assert the concrete error kind through `fs.parse` (f32 and f64 → `InvalidCharacter`) instead of bare `catch {}`

- `examples/demo.zig` now exercises every ported flag family: added the last missing registrations — `uintSlice` (`--udp=53 --udp=123,9`), `stringArray` (`--file=report.txt --file=a,b`, demonstrating verbatim storage vs the CSV-splitting slices), and the `stringState` family (`-w, --workdir`: library-owned string whose `set()` dupes, versus legacy `stringVar` borrowing the caller's slice) — plus per-element printout of the bool slice, uint slice and string array values. README and README_CN demo commands and expected-output fences were re-captured byte-for-byte from `zig build run-demo`, replacing snapshots that still carried the pre-refactor tab-indented usage rendering and a stale `tag = default` line (first-Set-replaces means `-t` parses show only the new values).

- FlagSet-managed state allocation (phase 1: `string`): `FlagSet.stringVarOwned` / `stringVarOwnedP` — the set itself allocates and owns the backing `StringState`, dupes the default and every parsed value through `FlagSet.gpa`, and frees the lot (duped strings via the existing vtable deinit, state shells via a new `managed_states` registry drained strictly after all flags deinit) at `FlagSet.deinit()`. Config structs bind plain `*[]const u8` fields — no `*State` members, stored allocators, or teardown choreography; registration failure (redefinitions, shorthand validation, any OOM) leaves set and binding untouched. Global-set twins `pflag.stringCLOwned` / `pflag.stringCLOwnedP` free via `deinitCommandLine()`. `stringStateVar*` stays as the explicit-ownership path; owned flags must not be shared through `addFlagSet` (documented ownership rule). `struct_config.zig` migrated to the owned API; README/README_CN memory notes extended; suite 210 → 214 (poisoned-buffer proof that values are duped, registration-error rollback incl. dupe-after-`ShorthandTooLong`, mixed explicit/legacy/owned sets, `checkAllAllocationFailures` OOM matrix)

### Changed

- **Minimum Zig version is now 0.17.0** (tagged `v0.16.0` marks the last Zig 0.16.x release)
- Build system: `if (b.args) |args| run.addArgs(args)` replaced with `run.addPassthruArgs()` (Zig 0.17 build system maker/configurer separation)
- `std.fmt.allocPrint(gpa, ...)` replaced with `gpa.print(...)` (moved to `std.mem.Allocator` in Zig 0.17)
- `gpa` examples migrated from deprecated `std.heap.DebugAllocator` to thread-safe `std.heap.SafeAllocator`
- `build.zig.zon`: `minimum_zig_version` bumped to `0.17.0`
- **Layered internal refactor** — public API frozen (everything stays reachable through `pflag.zig`, examples and downstream users need no change); file layout now deliberately deviates from upstream's monolithic flag.go:
  - `Value` interface (`ptr` + `VTable`) moved from `src/pflag.zig` to new `src/value.zig`; the nine `*_types.zig` import the interface directly, removing `pflag.zig ⇄ *_types.zig` import cycles
  - new `src/internal.zig` leaf module owns shared `parseBool`, `readAsCSV`/`writeAsCSV`, and `splitKeyValue`; `slice_types` no longer imports `bool_types`
- **BREAKING (pre-0.1 window): public surface shrunk 51 → 44 → 27 root names.** Stage one: the module namespace tables `pflag.errors` and the nine `pflag.<kind>_types` are withdrawn and become file-private imports; helpers migrated to flat paths (`pflag.bool_types.parseBool` → `pflag.parseBool`; `pflag.slice_types.readAsCSV`/`writeAsCSV` → flat). Stage two: the type-erasure machinery was trimmed and then reshaped to the upstream contract — `FlagSet.varP`/`addFlag` and `pflag.Value` are **kept public** (mirroring Go, where `Value` + `VarP`/`AddFlag` are the supported downstream extension point and only the `new*Value` ctors are package-private), while the 16 public `xxxValue` ctors and all module namespace tables remain withdrawn.
  - usage/help rendering extracted to `src/usage.zig`; the previously duplicated string-based and writer-based render stacks were unified behind `std.Io.Writer` (its user-visible consequence is listed separately below — it is not purely internal)
  - the process-global CommandLine singleton and `*CL` helpers moved to `src/cmdline.zig`, flat-re-exported from `pflag.zig` (the flat names are the only public access; `pflag.cmdline` itself is file-private)
  - the parse engine (`argLoop`/`longArg`/`shortArg`, `applyValue`/`doFailWith`/`markParsed`) lives in `src/parse.zig` as free functions taking `*FlagSet`; `FlagSet.parse`/`parseAll` are thin delegating shells; `pflag.zig` shrank 879 → ~560 lines
  - int/uint/float slice vtables now share `makeNumSliceVtable(T, comptime parse)`; behavior unchanged (the 205-test suite stayed green throughout, zero test edits)
  - `src/pflag_test.zig` split by concern: parse-engine tests → `parse_test.zig` (42), usage-rendering tests → `usage_test.zig` (28), shared helpers → `testutil.zig`, core registry/getter tests stay in `pflag_test.zig` (46)
- **User-visible text change in usage output** (result of unifying the duplicated render stacks, worth calling out despite living under "internal"): `FlagUsages`/`FlagUsagesWrapped` now render deprecated flags as `" (deprecated: msg)"`, matching `PrintDefaults`; previously the string-returning path emitted only `" (deprecated)"` with no message. If you diff help text or snapshot it, this line changes.
- **Numeric/bool slices now commit atomically on a failed element** (upstream-parity fix): `intSlice`/`uintSlice`/`floatSlice` (via `makeNumSliceVtable`) and `boolSlice` used to clear defaults (first Set) and append already-converted elements *before* a later bad element errored, so a failing `Set` could leave the bound slice half-populated and consume the replace-defaults state. They now build the parsed list in a local buffer first, like upstream: on error nothing commits, `changed` stays unset, and defaults or previously parsed values survive. (`-0` still parses to zero in uint slices, and real negatives yield `Overflow`, matching the scalar widths via Zig's radix-0 `parseInt`.)

### Fixed

- `formatDuration(0)` now returns `"0s"`, matching upstream's canonical zero spelling; previously the day-branch guard (`0 % ns_per_day == 0`) captured zero first, so duration defaults rendered as `--timeout=0d` in usage output. A zero case was added to the format/parse round-trip table (test count unchanged).

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
