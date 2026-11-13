# Contributing to zig-pflag

Thanks for your interest in contributing!

## License

By contributing to this project, you agree that your contributions will be
licensed under the BSD 3-Clause License that covers this project.

## Prerequisites

- [Zig 0.17.0](https://ziglang.org/download/)

## Development

```bash
# Clone and verify
git clone https://github.com/rebornwwp/zig-pflag.git
cd zig-pflag
zig build test          # Run all 214 tests
zig fmt --check src/ examples/ build.zig   # CI formatting scope

# Format code before committing
zig fmt src/

# Run the demo to verify end-to-end behavior
zig build run-demo -- -v --name=zig --count=42
```

## Code Style

- **Zig 0.17.0** standard library conventions
- `zig fmt` for automatic formatting — no manual style decisions
- Comptime generics preferred over code duplication for type families
- Cross-platform: no OS-specific APIs (no `std.os.linux.*`)

## Project Structure

```
src/
├── value.zig          # Value interface (ptr + vtable)
├── internal.zig       # parseBool, CSV read/write, splitKeyValue
├── usage.zig          # usage rendering layer
├── parse.zig          # argument parsing engine (free functions)
├── cmdline.zig        # global CommandLine singleton (*CL helpers)
├── pflag.zig          # Flag, FlagSet, registration, entry shells
├── errors.zig         # ParseError, ErrorHandling enums
├── bool_types.zig     # Bool flag type
├── int_types.zig      # Int types (i8–i64, comptime-generic)
├── uint_types.zig     # Uint types (u8–u64)
├── float_types.zig    # Float types (f32/f64)
├── string_types.zig   # String flag type
├── count_types.zig    # Count flag type
├── duration_types.zig # Duration type (s/m/h/d)
├── slice_types.zig    # string/int/uint/bool/float slices
├── map_types.zig      # string→int, string→string maps
├── pflag_test.zig     # 46 core FlagSet tests
├── parse_test.zig     # 42 parse-engine tests
├── usage_test.zig     # 28 usage-rendering tests
└── testutil.zig       # shared test helpers
```

## Checklist Before Submitting

- [ ] All tests pass: `zig build test`
- [ ] Code formatted: `zig fmt src/`
- [ ] Demo still works: `zig build run-demo -- -v -n=zig`
- [ ] No new warnings or errors from `zig build`
- [ ] PR targets the `main` branch
