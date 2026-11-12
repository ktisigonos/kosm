//! `kosm complete -- <words>`: what a shell may offer for the word being typed, one candidate
//! per line with its description after a tab. The scripts `kosm completions` prints call it.
//! It never reports an error: a config that does not build completes nothing.

const std = @import("std");
const Context = @import("Context.zig");
const Packages = @import("Packages.zig");
const manifest = @import("manifest.zig");
const interface = @import("kosm_interface");

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error;

/// One thing the shell may offer.
const Candidate = struct {
    text: []const u8,
    description: []const u8,
};

const commands = [_]Candidate{
    .{ .text = "init", .description = "create what a config project is missing" },
    .{ .text = "new", .description = "scaffold a kosmos, app or adapter" },
    .{ .text = "apply", .description = "apply a kosmos" },
    .{ .text = "list", .description = "list kosmoi and packages" },
    .{ .text = "colors", .description = "show a kosmos' palettes" },
    .{ .text = "current", .description = "print the last apply as a command" },
    .{ .text = "source", .description = "choose the kosm sources builds use" },
    .{ .text = "add", .description = "install a package from a url" },
    .{ .text = "remove", .description = "remove a package" },
    .{ .text = "update", .description = "fetch packages again" },
    .{ .text = "completions", .description = "print a shell's completion script" },
    .{ .text = "relay", .description = "forward a file to a browser extension" },
};
const kinds = [_]Candidate{
    .{ .text = "kosmos", .description = "a rice" },
    .{ .text = "app", .description = "support for one program" },
    .{ .text = "adapter", .description = "support for one file format" },
};
const shells = [_]Candidate{
    .{ .text = "fish", .description = "completions for fish" },
    .{ .text = "bash", .description = "completions for bash" },
    .{ .text = "zsh", .description = "completions for zsh" },
};
const config_flag: Candidate = .{ .text = "--config", .description = "the config project's directory" };
const apply_flags = [_]Candidate{
    .{ .text = "--diff", .description = "print what would change and write nothing" },
    .{ .text = "--set", .description = "set one value of the kosmos: path=value" },
    config_flag,
};

/// What `addConfigProject` installs for `-Dkosmos=...` and `-Dlist`.
const runner_path = "zig-out/bin/kosmos";
const lister_path = "zig-out/bin/list";

/// Writes the candidates for the last of `words`: the words typed after `kosm`, the last one
/// being the word under the cursor, which may be empty.
pub fn complete(context: Context, words: []const []const u8) Error!void {
    if (words.len <= 1) return writeAll(context.stdout, &commands);
    const command = words[0];
    const current = words[words.len - 1];
    const previous = words[words.len - 2];
    const before = words[1 .. words.len - 1];
    // A directory, which each shell completes itself.
    if (std.mem.eql(u8, previous, config_flag.text)) return;

    if (std.mem.eql(u8, command, "new")) return if (before.len == 0) writeAll(context.stdout, &kinds);
    if (std.mem.eql(u8, command, "completions")) return if (before.len == 0) writeAll(context.stdout, &shells);
    if (std.mem.eql(u8, command, "source")) return if (before.len == 0) writeAll(context.stdout, &.{.{ .text = "--default", .description = "use the installed sources again" }});
    if (std.mem.eql(u8, command, "current")) return;
    // A file, which each shell completes itself.
    if (std.mem.eql(u8, command, "relay")) return;
    if (std.mem.eql(u8, command, "apply")) return completeApply(context, before, previous, current);

    if (std.mem.startsWith(u8, current, "-")) return writeAll(context.stdout, &.{config_flag});
    if (firstPositional(before) != null) return;
    if (std.mem.eql(u8, command, "list") or std.mem.eql(u8, command, "colors")) return writeKosmoi(context);
    if (std.mem.eql(u8, command, "remove")) return writeInstalled(context);
    if (std.mem.eql(u8, command, "update")) return writeUpdatable(context);
}

/// `kosm apply`: the kosmos first, then its flags; after `--set`, its paths.
fn completeApply(context: Context, before: []const []const u8, previous: []const u8, current: []const u8) Error!void {
    const kosmos = firstPositional(before) orelse {
        if (std.mem.startsWith(u8, current, "-")) return writeAll(context.stdout, &.{config_flag});
        return writeKosmoi(context);
    };
    if (std.mem.eql(u8, previous, "--set")) {
        // Past the `=` a value is being typed, which only the user knows.
        if (std.mem.findScalar(u8, current, '=') != null) return;
        return writeKosmosCandidates(context, kosmos, .paths);
    }
    // Every parameter takes a value, so after one nothing is offered.
    if (std.mem.startsWith(u8, previous, "--") and !std.mem.eql(u8, previous, "--diff")) return;
    try writeAll(context.stdout, &apply_flags);
    try writeKosmosCandidates(context, kosmos, .parameters);
}

/// The first word that is neither a flag nor `--config`'s directory.
fn firstPositional(words: []const []const u8) ?[]const u8 {
    var index: usize = 0;
    while (index < words.len) : (index += 1) {
        if (std.mem.eql(u8, words[index], config_flag.text)) {
            index += 1;
        } else if (!std.mem.startsWith(u8, words[index], "-")) return words[index];
    }
    return null;
}

fn writeAll(writer: *std.Io.Writer, candidates: []const Candidate) Error!void {
    for (candidates) |candidate| try writer.print("{s}\t{s}\n", .{ candidate.text, candidate.description });
}

/// Every kosmos and variant, as the config's lister names them.
fn writeKosmoi(context: Context) Error!void {
    const listed = try runForCompletions(context, "-Dlist", lister_path) orelse return;
    try context.stdout.writeAll(listed);
}

const KosmosCandidates = enum { parameters, paths };

/// The parameters of `kosmos` as flags, or its `--set` paths each ending in `=`, as its
/// runner reports them.
fn writeKosmosCandidates(context: Context, kosmos: []const u8, wanted: KosmosCandidates) Error!void {
    const reported = try runForCompletions(context, try context.arena.print("-Dkosmos={s}", .{kosmos}), runner_path) orelse return;
    const kind = switch (wanted) {
        .parameters => "param",
        .paths => "set",
    };
    var lines = std.mem.splitScalar(u8, reported, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        if (!std.mem.eql(u8, fields.first(), kind)) continue;
        const text = fields.next() orelse continue;
        try context.stdout.print("{s}{s}\t{s}\n", .{ text, if (wanted == .paths) "=" else "", fields.rest() });
    }
}

/// Builds the config with `option` and runs `program` asking for completions; null when the
/// config does not build or the program fails. `--diff` goes along so that a runner too old
/// to know about completions still writes nothing.
fn runForCompletions(context: Context, option: []const u8, program: []const u8) Error!?[]const u8 {
    var quiet = context;
    var discarded: std.Io.Writer.Discarding = .init(&.{});
    quiet.stderr = &discarded.writer;
    const build = quiet.runZig(&.{ "build", option }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    if (!build.term.success()) return null;

    var environ: std.process.Environ.Map = if (context.environ_map) |map| try map.clone(context.arena) else .init(context.arena);
    try environ.put(interface.completions_variable, "1");
    try environ.put(interface.environment_variable, try context.arena.print("{d}", .{interface.version}));
    quiet.environ_map = &environ;
    const result = quiet.run(&.{ try std.Io.Dir.path.join(context.arena, &.{ context.config, program }), "--diff" }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    return if (result.term.success()) result.stdout else null;
}

/// Every package in the config's manifest but kosm, which can't be removed.
fn writeInstalled(context: Context) Error!void {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, "build.zig.zon" });
    const source = std.Io.Dir.cwd().readFileAllocOptions(context.io, path, context.arena, .limited(16 * 1024 * 1024), .of(u8), 0) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return,
    };
    const names = manifest.dependencyNames(context.arena, source) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidManifest => return,
    };
    for (names) |name| {
        if (!std.mem.eql(u8, name, "kosm")) try context.stdout.print("{s}\tinstalled package\n", .{name});
    }
}

/// Every package `kosm update` can fetch again: those in packages.zon.
fn writeUpdatable(context: Context) Error!void {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, Packages.file_name });
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const packages = Packages.load(context.arena, context.io, path, &diagnostics) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return,
    };
    for (packages.entries.items) |package| try context.stdout.print("{s}\t{s}\n", .{ package.name, package.url });
}

const testing = std.testing;

/// The candidates for `words` in a config directory that holds nothing, as lines.
fn testComplete(arena: std.mem.Allocator, config: []const u8, words: []const []const u8) ![]const u8 {
    var stdout: std.Io.Writer.Allocating = .init(arena);
    var stderr: std.Io.Writer.Allocating = .init(arena);
    try complete(.{ .io = testing.io, .arena = arena, .config = config, .stdout = &stdout.writer, .stderr = &stderr.writer }, words);
    try testing.expectEqualStrings("", stderr.written());
    return stdout.written();
}

test "the first word completes to the commands, and new, completions and source to their choices" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try tmp.dir.realPathFileAlloc(testing.io, ".", arena.allocator());

    const first = try testComplete(arena.allocator(), config, &.{""});
    try testing.expectStringStartsWith(first, "init\tcreate what a config project is missing\nnew\t");
    try testing.expect(std.mem.find(u8, first, "\napply\tapply a kosmos\n") != null);
    try testing.expect(std.mem.find(u8, first, "\ncolors\t") != null);
    try testing.expectEqualStrings(first, try testComplete(arena.allocator(), config, &.{}));
    try testing.expectEqualStrings("kosmos\ta rice\napp\tsupport for one program\nadapter\tsupport for one file format\n", try testComplete(arena.allocator(), config, &.{ "new", "" }));
    try testing.expectEqualStrings("", try testComplete(arena.allocator(), config, &.{ "new", "app", "" }));
    try testing.expectStringStartsWith(try testComplete(arena.allocator(), config, &.{ "completions", "f" }), "fish\t");
    try testing.expectStringStartsWith(try testComplete(arena.allocator(), config, &.{ "source", "" }), "--default\t");
    try testing.expectEqualStrings("", try testComplete(arena.allocator(), config, &.{ "current", "" }));
}

test "a directory after --config is left to the shell, and a flag being typed gets --config" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try tmp.dir.realPathFileAlloc(testing.io, ".", arena.allocator());

    try testing.expectEqualStrings("", try testComplete(arena.allocator(), config, &.{ "apply", "--config", "" }));
    try testing.expectEqualStrings("--config\tthe config project's directory\n", try testComplete(arena.allocator(), config, &.{ "list", "--" }));
    try testing.expectEqualStrings("--config\tthe config project's directory\n", try testComplete(arena.allocator(), config, &.{ "apply", "-" }));
}

test "remove and update complete to the config's packages, and a second name to nothing" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try tmp.dir.realPathFileAlloc(testing.io, ".", arena.allocator());
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "build.zig.zon", .data = ".{ .name = .config, .dependencies = .{ .kosm = .{ .path = \"k\" }, .kosm_kitty = .{ .path = \"a\" }, .mine = .{ .path = \"b\" } } }\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "packages.zon", .data = ".{ .kosm = .{ .url = \"https://example.com/kosm\" }, .kosm_kitty = .{ .url = \"https://example.com/kitty\" } }\n" });

    try testing.expectEqualStrings("kosm_kitty\tinstalled package\nmine\tinstalled package\n", try testComplete(arena.allocator(), config, &.{ "remove", "" }));
    try testing.expectEqualStrings("kosm\thttps://example.com/kosm\nkosm_kitty\thttps://example.com/kitty\n", try testComplete(arena.allocator(), config, &.{ "update", "" }));
    try testing.expectEqualStrings("", try testComplete(arena.allocator(), config, &.{ "remove", "mine", "" }));
}

test "a config that does not build completes no kosmos, silently" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try tmp.dir.realPathFileAlloc(testing.io, ".", arena.allocator());

    try testing.expectEqualStrings("", try testComplete(arena.allocator(), config, &.{ "apply", "" }));
    try testing.expectEqualStrings("", try testComplete(arena.allocator(), config, &.{ "apply", "frost", "--set", "" }));
    // The flags kosm itself takes need no build.
    try testing.expectStringStartsWith(try testComplete(arena.allocator(), config, &.{ "apply", "frost", "" }), "--diff\t");
    try testing.expectEqualStrings("", try testComplete(arena.allocator(), config, &.{ "apply", "frost", "--blur", "" }));
}
