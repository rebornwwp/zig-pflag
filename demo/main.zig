const std = @import("std");
const pflag = @import("pflag");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var fs = pflag.FlagSet.init(gpa, "demo");
    defer fs.deinit();
    fs.error_handling = .continue_on_error;
    fs.parse_errors_allowlist.unknown_flags = true;

    var out_buf: [4096]u8 = undefined;
    var out_writer = std.Io.Writer.fixed(&out_buf);
    fs.out_writer = &out_writer;

    var verbose: bool = false;
    try fs.boolVarP(&verbose, "verbose", "v", false, "enable verbose output");
    var count: i32 = 0;
    try fs.intVar(i32, &count, "count", 0, "the count (int32)");
    var big: i64 = 0;
    try fs.intVar(i64, &big, "big", 0, "64-bit integer");
    var port: u16 = 8080;
    try fs.uintVarP(u16, &port, "port", "p", 8080, "port number");
    var rate: f64 = 1.0;
    try fs.floatVar(f64, &rate, "rate", 1.0, "request rate");
    var name: []const u8 = "world";
    try fs.stringVarP(&name, "name", "n", "world", "your name");
    var verbosity: i32 = 0;
    try fs.countVarP(&verbosity, "verbosity", "V", 0, "verbosity level");
    var timeout: i64 = 0;
    try fs.durationVar(&timeout, "timeout", 0, "timeout (30s/5m/2h/1d)");

    var tags: std.ArrayListUnmanaged([]const u8) = .empty;
    defer tags.deinit(gpa);
    tags.append(gpa, "default") catch {};
    try fs.stringSliceVarP(&tags, "tag", "t", &.{}, "tags (repeatable)");
    var ports: std.ArrayListUnmanaged(i32) = .empty;
    try fs.intSliceVar(i32, &ports, "expose", &.{}, "exposed ports");
    var flags: std.ArrayListUnmanaged(bool) = .empty;
    try fs.boolSliceVar(&flags, "flag", &.{}, "bool flags");
    var scores: std.ArrayListUnmanaged(f32) = .empty;
    try fs.floatSliceVar(f32, &scores, "score", &.{}, "scores");

    var headers: std.StringHashMapUnmanaged(i32) = .empty;
    try fs.stringToIntVar(i32, &headers, "header", 0, "headers as key=value");
    var labels: std.StringHashMapUnmanaged([]const u8) = .empty;
    try fs.stringToStringVar(&labels, "label", "", "labels as key=value");

    try fs.markDeprecated("big", "use --count instead");
    var secret: bool = false;
    try fs.boolVar(&secret, "secret", false, "hidden flag");
    try fs.markHidden("secret");

    fs.setNormalizeFunc(struct {
        fn f(_: *pflag.FlagSet, n: []const u8) []const u8 {
            return n;
        }
    }.f);
    try fs.setAnnotation("name", "category", &.{"basic"});

    // Cross-platform stdout writer
    var stdout_buf: [1024]u8 = undefined;
    var stdout_file_writer = std.Io.File.Writer.init(.stdout(), io, &stdout_buf);
    const stdout_writer = &stdout_file_writer.interface;

    try h("Flag defaults (before parsing)", stdout_writer);
    fs.printDefaults();
    pbuf(&out_writer, stdout_writer);

    const alloc = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(alloc);
    const args = if (raw.len > 1) @as([]const []const u8, @ptrCast(raw[1..])) else &.{};
    fs.parse(args) catch |err| {
        const e = fs.lastError();
        try h("Parse error", stdout_writer);
        try p(stdout_writer, "  error={s}, kind={any}, name={s}", .{ @errorName(err), e.kind, e.name });
    };

    try h("Parsed values", stdout_writer);
    try show(stdout_writer, "  verbose  ", verbose);
    try show(stdout_writer, "  count    ", count);
    try show(stdout_writer, "  big      ", big);
    try show(stdout_writer, "  port     ", port);
    try show(stdout_writer, "  rate     ", rate);
    try p(stdout_writer, "  name     = {s}", .{name});
    try show(stdout_writer, "  verbosity", verbosity);
    try show(stdout_writer, "  timeout  ", timeout);

    try h("Slice values", stdout_writer);
    if (tags.items.len > 0) {
        for (tags.items) |t| try p(stdout_writer, "  tag = {s}", .{t});
    } else try w(stdout_writer, "  (none)");
    if (ports.items.len > 0) {
        for (ports.items) |p2| try p(stdout_writer, "  expose = {d}", .{p2});
    } else try w(stdout_writer, "  (none)");
    if (scores.items.len > 0) {
        for (scores.items) |s| try p(stdout_writer, "  score = {d}", .{s});
    } else try w(stdout_writer, "  (none)");

    try h("Map values", stdout_writer);
    if (headers.count() > 0) {
        var it = headers.iterator();
        while (it.next()) |e| try p(stdout_writer, "  {s} = {d}", .{ e.key_ptr.*, e.value_ptr.* });
    } else try w(stdout_writer, "  (none)");
    if (labels.count() > 0) {
        var it = labels.iterator();
        while (it.next()) |e| try p(stdout_writer, "  {s} = {s}", .{ e.key_ptr.*, e.value_ptr.* });
    } else try w(stdout_writer, "  (none)");

    try h("Positional args", stdout_writer);
    if (fs.argList().len > 0) {
        for (fs.argList()) |a| try p(stdout_writer, "  {s}", .{a});
    } else try w(stdout_writer, "  (none)");

    try h("Flags that were set", stdout_writer);
    var ctx = VisitCtx{ .fs = &fs, .stdout_writer = stdout_writer };
    fs.visit(&ctx, visitCb);
    try p(stdout_writer, "", .{});
    try p(stdout_writer, "  nFlag() = {d}, changed(verbose) = {}", .{ fs.nFlag(), fs.changed("verbose") });

    try h("Flag usages (text)", stdout_writer);
    const usage = fs.flagUsages();
    defer gpa.free(usage);
    try w(stdout_writer, usage);
    if (fs.getAnnotation("name", "category")) |cat| {
        try p(stdout_writer, "  annotation[name][category] = {s}", .{cat[0]});
    }

    try stdout_writer.flush();
}

const VisitCtx = struct {
    fs: *pflag.FlagSet,
    stdout_writer: *std.Io.Writer,
};
fn visitCb(ctx: *VisitCtx, f: *pflag.Flag) void {
    p(ctx.stdout_writer, "  --{s} (changed={})", .{ f.name, f.changed }) catch return;
}

fn w(stdout_writer: *std.Io.Writer, s: []const u8) !void {
    try stdout_writer.print("{s}", .{s});
}
fn h(s: []const u8, stdout_writer: *std.Io.Writer) !void {
    try w(stdout_writer, "\n");
    try w(stdout_writer, s);
    try w(stdout_writer, "\n");
}
fn show(stdout_writer: *std.Io.Writer, name: []const u8, v: anytype) !void {
    try p(stdout_writer, "{s}= {}", .{ name, v });
}
fn p(stdout_writer: *std.Io.Writer, comptime fmt: []const u8, args: anytype) !void {
    try stdout_writer.print(fmt ++ "\n", args);
}
fn pbuf(w_: *std.Io.Writer, stdout_writer: *std.Io.Writer) void {
    w(stdout_writer, std.Io.Writer.buffered(w_)) catch return;
    w_.end = 0;
}
