//! Example: bind struct fields to command-line flags, parse, and print.
const std = @import("std");
const pflag = @import("pflag");

const ServerConfig = struct {
    port: u16 = 8080,
    host: []const u8 = "127.0.0.1",
    workers: i32 = 4,
    verbose: bool = false,
    timeout_ns: i64 = 30 * std.time.ns_per_s,
    rate_limit: f64 = 100.0,
    tags: std.ArrayListUnmanaged([]const u8) = .empty,

    pub fn print(self: ServerConfig) void {
        std.debug.print("ServerConfig {{\n", .{});
        std.debug.print("  port       = {d}\n", .{self.port});
        std.debug.print("  host       = {s}\n", .{self.host});
        std.debug.print("  workers    = {d}\n", .{self.workers});
        std.debug.print("  verbose    = {}\n", .{self.verbose});
        std.debug.print("  timeout    = {d}s\n", .{@divFloor(self.timeout_ns, std.time.ns_per_s)});
        std.debug.print("  rate_limit = {d}\n", .{self.rate_limit});
        std.debug.print("  tags       = ", .{});
        if (self.tags.items.len == 0) {
            std.debug.print("(none)\n", .{});
        } else {
            for (self.tags.items, 0..) |tag, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{tag});
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("}}\n", .{});
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var fs = pflag.FlagSet.init(gpa, "struct-config");
    defer fs.deinit();

    // Bind struct fields to flags
    var cfg: ServerConfig = .{};

    try fs.uintVarP(u16, &cfg.port, "port", "p", cfg.port, "listen port");
    try fs.stringVarP(&cfg.host, "host", "h", cfg.host, "bind address");
    try fs.intVarP(i32, &cfg.workers, "workers", "w", cfg.workers, "worker threads");
    try fs.boolVarP(&cfg.verbose, "verbose", "v", cfg.verbose, "verbose output");
    try fs.durationVarP(&cfg.timeout_ns, "timeout", "t", cfg.timeout_ns, "request timeout");
    try fs.floatVarP(f64, &cfg.rate_limit, "rate-limit", "r", cfg.rate_limit, "rate limit (req/s)");

    var tags_state = pflag.StringSliceState{ .value = &cfg.tags, .gpa = gpa };
    try fs.stringSliceVarP(&tags_state, "tag", "T", &.{}, "tags (repeatable)");

    // Parse args (skip program name)
    const alloc = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(alloc);
    const effective = if (raw.len > 1) raw[1..] else &.{};
    try fs.parse(effective);

    // Print parsed struct
    std.debug.print("Parsed server config:\n", .{});
    cfg.print();
}
