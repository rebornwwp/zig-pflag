//! Error types for pflag. Maps from pflag/errors.go v1.0.9.

pub const ErrorHandling = enum { continue_on_error, exit_on_error, panic_on_error };
pub const ParseErrorsAllowlist = struct { unknown_flags: bool = false };

pub const ParseError = struct {
    kind: ErrorKind,
    name: []const u8 = "",
    value: []const u8 = "",
    shorthands: []const u8 = "",

    pub const ErrorKind = enum {
        not_exist,
        not_defined,
        no_such_flag,
        unknown_flag,
        unknown_shorthand,
        value_required,
        invalid_value,
        help,
    };

    pub fn init(kind: ErrorKind, name: []const u8) ParseError {
        return .{ .kind = kind, .name = name };
    }
};
