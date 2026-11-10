//! The build of a directory package: its one-line `build.zig` calls `package`, so the
//! same directory works inside a config, when fetched by others, and when developed on its own.

const std = @import("std");

/// A manifest is a few hundred bytes; this only guards against reading something huge.
const max_manifest_size = 1024 * 1024;

/// Exposes `root.zig` as a module named like the package's manifest `.name`, importing
/// every dependency by its name, and adds a `test` step running its tests.
pub fn package(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const name = manifestName(b) catch |err| {
        b.getInstallStep().dependOn(&b.addFail(b.fmt("cannot read .name from build.zig.zon: {s}", .{@errorName(err)})).step);
        return;
    };

    var imports: std.ArrayList(std.Build.Module.Import) = .empty;
    var grammars: std.ArrayList(*std.Build.Dependency) = .empty;
    for (b.available_deps) |available| {
        const dependency_name = available[0];
        const dependency = b.dependency(dependency_name, .{ .target = target, .optimize = optimize });
        if (isGrammar(b, dependency)) {
            grammars.append(b.allocator, dependency) catch @panic("OOM");
            continue;
        }
        // A dependency without a module of its own name (say, C sources) is wired up by hand.
        const module = dependency.builder.modules.get(dependency_name) orelse continue;
        imports.append(b.allocator, .{ .name = dependency_name, .module = module }) catch @panic("OOM");
    }
    const module = b.addModule(name, .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports.items,
    });
    for (grammars.items) |grammar| addGrammar(b, module, grammar);
    const tests = b.addTest(.{ .root_module = module });
    b.step("test", "Run the package's tests").dependOn(&b.addRunArtifact(tests).step);
}

/// Whether `dependency` is a tree-sitter grammar: it holds a generated `src/parser.c`.
pub fn isGrammar(b: *std.Build, dependency: *std.Build.Dependency) bool {
    const parser = dependency.builder.root.joinString(b.allocator, "src/parser.c") catch @panic("OOM");
    std.Io.Dir.cwd().access(b.graph.io, parser, .{}) catch return false;
    return true;
}

/// Compiles grammar `dependency`'s `src/parser.c`, and `src/scanner.c` when it has one, into
/// `module`. Nobody writes C: the grammar's generator did.
pub fn addGrammar(b: *std.Build, module: *std.Build.Module, dependency: *std.Build.Dependency) void {
    module.link_libc = true;
    module.addIncludePath(dependency.path("src"));
    module.addCSourceFile(.{ .file = dependency.path("src/parser.c"), .flags = &.{"-std=c11"} });
    const scanner = dependency.builder.root.joinString(b.allocator, "src/scanner.c") catch @panic("OOM");
    std.Io.Dir.cwd().access(b.graph.io, scanner, .{}) catch return;
    module.addCSourceFile(.{ .file = dependency.path("src/scanner.c"), .flags = &.{"-std=c11"} });
}

/// The identifier after `.name = .` in the package's `build.zig.zon`. Read by hand because a
/// fetched package's directory is named after its hash, not its name.
fn manifestName(b: *std.Build) ![]const u8 {
    const io = b.graph.io;
    const path = try b.root.joinString(b.allocator, "build.zig.zon");
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, b.allocator, .limited(max_manifest_size));
    const source = try b.allocator.dupeSentinel(u8, text, 0);
    return nameIn(source) orelse error.MissingName;
}

/// The first top-level `.name = .identifier` in a manifest.
fn nameIn(source: [:0]const u8) ?[]const u8 {
    var tokenizer: std.zig.Tokenizer = .init(source);
    const pattern = [_]std.zig.Token.Tag{ .period, .identifier, .equal, .period, .identifier };
    var window: [pattern.len]std.zig.Token = undefined;
    var count: usize = 0;
    var depth: usize = 0;
    while (true) {
        const token = tokenizer.next();
        switch (token.tag) {
            .eof => return null,
            .l_brace => depth += 1,
            .r_brace => depth -|= 1,
            else => {},
        }
        std.mem.copyForwards(std.zig.Token, window[0 .. pattern.len - 1], window[1..]);
        window[pattern.len - 1] = token;
        count += 1;
        if (count < pattern.len or depth != 1) continue;
        const matches = for (window, pattern) |seen, tag| {
            if (seen.tag != tag) break false;
        } else true;
        const key = source[window[1].loc.start..window[1].loc.end];
        if (matches and std.mem.eql(u8, key, "name")) return source[window[4].loc.start..window[4].loc.end];
    }
}

test "the manifest name is read from the top level only" {
    const manifest =
        \\.{
        \\    .version = "0.0.0",
        \\    .dependencies = .{ .other = .{ .name = .wrong } },
        \\    .name = .kosm_kitty,
        \\}
    ;
    try std.testing.expectEqualStrings("kosm_kitty", nameIn(manifest).?);
    try std.testing.expectEqual(null, nameIn(".{ .version = \"0.0.0\" }"));
}
