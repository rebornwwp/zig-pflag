# Contributing to zig-pflag

Thanks for your interest in contributing!

## License

By contributing to this project, you agree that your contributions will be
licensed under the BSD 3-Clause License that covers this project.

## Prerequisites

- [Zig 0.16.0](https://ziglang.org/download/)

## Development

```bash
# Clone and verify
git clone https://github.com/rebornwwp/zig-pflag.git
cd zig-pflag
zig build test          # Run all 89 tests
zig fmt --check src/    # Check code formatting

# Format code before committing
zig fmt src/

# Run the demo to verify end-to-end behavior
zig build run-demo -- -v --name=zig --count=42
```

## Code Style

- **Zig 0.16.0** standard library conventions
- `zig fmt` for automatic formatting — no manual style decisions
- Comptime generics preferred over code duplication for type families
- Cross-platform: no OS-specific APIs (no `std.os.linux.*`)

## Project Structure

```
src/
├── pflag.zig          # Value interface, Flag, FlagSet, parse engine
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
└── pflag_test.zig     # 89 tests
```

## Checklist Before Submitting

- [ ] All tests pass: `zig build test`
- [ ] Code formatted: `zig fmt src/`
- [ ] Demo still works: `zig build run-demo -- -v -n=zig`
- [ ] No new warnings or errors from `zig build`
- [ ] PR targets the `main` branch
