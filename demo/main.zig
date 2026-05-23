const std = @import("std");
const pflag = @import("pflag");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

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
    try fs.stringSliceVarP(&tags, "tag", "t", &.{"default"}, "tags (repeatable)");
    var ports: std.ArrayListUnmanaged(i32) = .empty;
    try fs.intSliceVar(i32, &ports, "expose", &.{}, "exposed ports");
    var flags: std.ArrayListUnmanaged(bool) = .empty;
    try fs.boolSliceVar(&flags, "flag", &.{}, "bool flags");
    var scores: std.ArrayListUnmanaged(f32) = .empty;
    try fs.floatSliceVar(f32, &scores, "score", &.{}, "scores");

    var headers: std.StringHashMapUnmanaged(i32) = .empty;
    try fs.stringToIntVar(&headers, "header", 0, "headers as key=value");
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

    h("Flag defaults (before parsing)");
    fs.printDefaults();
    pbuf(&out_writer);

    const alloc = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(alloc);
    const args = if (raw.len > 1) @as([]const []const u8, @ptrCast(raw[1..])) else &.{};
    fs.parse(args) catch |err| {
        const e = fs.lastError();
        h("Parse error");
        p("  error={s}, kind={any}, name={s}", .{ @errorName(err), e.kind, e.name });
    };

    h("Parsed values");
    show("  verbose  ", verbose);
    show("  count    ", count);
    show("  big      ", big);
    show("  port     ", port);
    show("  rate     ", rate);
    p("  name     = {s}", .{name});
    show("  verbosity", verbosity);
    show("  timeout  ", timeout);

    h("Slice values");
    if (tags.items.len > 0) {
        for (tags.items) |t| p("  tag = {s}", .{t});
    } else w("  (none)");
    if (ports.items.len > 0) {
        for (ports.items) |p2| p("  expose = {d}", .{p2});
    } else w("  (none)");
    if (scores.items.len > 0) {
        for (scores.items) |s| p("  score = {d}", .{s});
    } else w("  (none)");

    h("Map values");
    if (headers.count() > 0) {
        var it = headers.iterator();
        while (it.next()) |e| p("  {s} = {d}", .{ e.key_ptr.*, e.value_ptr.* });
    } else w("  (none)");
    if (labels.count() > 0) {
        var it = labels.iterator();
        while (it.next()) |e| p("  {s} = {s}", .{ e.key_ptr.*, e.value_ptr.* });
    } else w("  (none)");

    h("Positional args");
    if (fs.argList().len > 0) {
        for (fs.argList()) |a| p("  {s}", .{a});
    } else w("  (none)");

    h("Flags that were set");
    var ctx = VisitCtx{ .fs = &fs };
    fs.visit(&ctx, visitCb);
    p("", .{});
    p("  nFlag() = {d}, changed(verbose) = {}", .{ fs.nFlag(), fs.changed("verbose") });

    h("Flag usages (text)");
    const usage = fs.flagUsages();
    defer gpa.free(usage);
    w(usage);
    if (fs.getAnnotation("name", "category")) |cat| {
        p("  annotation[name][category] = {s}", .{cat[0]});
    }
}

const VisitCtx = struct { fs: *pflag.FlagSet };
fn visitCb(_: *VisitCtx, f: *pflag.Flag) void {
    p("  --{s} (changed={})", .{ f.name, f.changed });
}

fn w(s: []const u8) void {
    _ = std.os.linux.write(1, s.ptr, s.len);
}
fn h(s: []const u8) void {
    w("\n");
    w(s);
    w("\n");
}
fn show(name: []const u8, v: anytype) void {
    p("{s}= {}", .{ name, v });
}
fn p(comptime fmt: []const u8, args: anytype) void {
    var b: [256]u8 = undefined;
    const m = std.fmt.bufPrint(&b, fmt, args) catch return;
    w(m);
    w("\n");
}
fn pbuf(w_: *std.Io.Writer) void {
    w(std.Io.Writer.buffered(w_));
    w_.end = 0;
}
