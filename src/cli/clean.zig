//! `kosm clean`: deletes the Zig caches of a config project and of its local kosmoi, apps and
//! adapters, and the package versions in their `zig-pkg/` folders that no manifest uses any
//! more. Zig's global cache is shared with every other Zig project, so it is never touched.

const std = @import("std");
const Context = @import("Context.zig");
const manifest = @import("manifest.zig");
const directory_package = @import("directory_package.zig");

pub const Error = Context.Failed || std.mem.Allocator.Error || std.Io.Writer.Error;

const manifest_name = "build.zig.zon";
const cache_name = ".zig-cache";
const packages_name = "zig-pkg";
/// Manifests are small; this only guards against reading something huge.
const max_manifest_size = 1024 * 1024;

/// One folder `clean` deletes, relative to the config.
const Deletion = struct {
    path: []const u8,
    kind: enum { cache, package },
    size: u64,
};

/// Plans every deletion first, so an unreadable manifest or folder deletes nothing, then
/// deletes and prints what was freed.
pub fn clean(context: Context) Error!void {
    var deletions: std.ArrayList(Deletion) = .empty;
    var global_cache: GlobalCache = .{};
    for (try projects(context)) |project| {
        try planCache(context, project, &deletions);
        try planPackages(context, project, &global_cache, &deletions);
    }
    if (deletions.items.len == 0) return context.stdout.writeAll("nothing to clean\n");

    var freed: u64 = 0;
    var packages: usize = 0;
    for (deletions.items) |deletion| {
        const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, deletion.path });
        std.Io.Dir.cwd().deleteTree(context.io, full_path) catch |err|
            return context.fail("cannot delete {s}: {s}; {Bi:.1} was freed before it", .{ full_path, @errorName(err), freed });
        freed += deletion.size;
        switch (deletion.kind) {
            .cache => try context.stdout.print("deleted {s} ({Bi:.1})\n", .{ deletion.path, deletion.size }),
            .package => packages += 1,
        }
    }
    if (packages != 0) try context.stdout.print("deleted {d} unused package version{s}\n", .{ packages, if (packages == 1) "" else "s" });
    try context.stdout.print("freed {Bi:.1}\n", .{freed});
}

/// The config itself ("") and every local kosmos, app and adapter with a manifest of its own
/// ("kosmoi/frost"): each is a Zig project with its own cache and `zig-pkg/`.
fn projects(context: Context) Error![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    try found.append(context.arena, "");
    for (directory_package.local_directories) |local| {
        const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, local });
        var dir = std.Io.Dir.cwd().openDir(context.io, full_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return context.fail("cannot read {s}: {s}", .{ full_path, @errorName(err) }),
        };
        defer dir.close(context.io);
        var iterator = dir.iterate();
        while (iterator.next(context.io) catch |err| return context.fail("cannot read {s}: {s}", .{ full_path, @errorName(err) })) |entry| {
            if (entry.kind != .directory) continue;
            const project = try std.Io.Dir.path.join(context.arena, &.{ local, entry.name });
            if (try readManifest(context, try std.Io.Dir.path.join(context.arena, &.{ context.config, project, manifest_name })) != null) {
                try found.append(context.arena, project);
            }
        }
    }
    return found.items;
}

fn planCache(context: Context, project: []const u8, deletions: *std.ArrayList(Deletion)) Error!void {
    const path = try std.Io.Dir.path.join(context.arena, &.{ project, cache_name });
    const size = try treeSize(context, path) orelse return;
    try deletions.append(context.arena, .{ .path = path, .kind = .cache, .size = size });
}

/// Every folder in the project's `zig-pkg/` that its manifests no longer reach.
fn planPackages(context: Context, project: []const u8, global_cache: *GlobalCache, deletions: *std.ArrayList(Deletion)) Error!void {
    const packages_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, project, packages_name });
    var dir = std.Io.Dir.cwd().openDir(context.io, packages_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return context.fail("cannot read {s}: {s}", .{ packages_path, @errorName(err) }),
    };
    defer dir.close(context.io);
    const used = try usedHashes(context, project, global_cache);
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch |err| return context.fail("cannot read {s}: {s}", .{ packages_path, @errorName(err) })) |entry| {
        if (entry.kind != .directory or used.contains(entry.name)) continue;
        const path = try std.Io.Dir.path.join(context.arena, &.{ project, packages_name, entry.name });
        const size = try treeSize(context, path) orelse continue;
        try deletions.append(context.arena, .{ .path = path, .kind = .package, .size = size });
    }
}

/// The hash of every package the project's manifest reaches: its own dependencies, theirs,
/// and those of `.path` dependencies, which a build of the project fetches into the same
/// `zig-pkg/`. A package missing from `zig-pkg/` is read from Zig's global cache, which is
/// where a build unpacks it from again.
fn usedHashes(context: Context, project: []const u8, global_cache: *GlobalCache) Error!std.StringHashMapUnmanaged(void) {
    var used: std.StringHashMapUnmanaged(void) = .empty;
    var visited: std.StringHashMapUnmanaged(void) = .empty;
    var pending: std.ArrayList(Pending) = .empty;
    try pending.append(context.arena, .{ .manifest_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, project, manifest_name }) });
    while (pending.pop()) |next| {
        if ((try visited.getOrPut(context.arena, next.manifest_path)).found_existing) continue;
        const source = try readManifest(context, next.manifest_path) orelse source: {
            // A package folder without a manifest has no dependencies; only a missing folder
            // means the package is in the global cache.
            const hash = next.hash orelse continue;
            if (try exists(context, std.Io.Dir.path.dirname(next.manifest_path).?)) continue;
            break :source try global_cache.manifest(context, hash) orelse continue;
        };
        const dependencies = manifest.dependencies(context.arena, source) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidManifest => return context.fail("{s} is not a valid manifest, so kosm clean cannot tell which packages it uses; nothing was deleted", .{next.manifest_path}),
        };
        const manifest_directory = std.Io.Dir.path.dirname(next.manifest_path) orelse ".";
        for (dependencies) |dependency| {
            if (dependency.hash) |hash| {
                try used.put(context.arena, hash, {});
                const manifest_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, project, packages_name, hash, manifest_name });
                try pending.append(context.arena, .{ .manifest_path = manifest_path, .hash = hash });
            } else if (dependency.path) |path| {
                try pending.append(context.arena, .{ .manifest_path = try std.Io.Dir.path.resolveAlloc(context.arena, &.{ manifest_directory, path, manifest_name }) });
            }
        }
    }
    return used;
}

/// A manifest still to read, and the hash of the package it belongs to; null for a local one.
const Pending = struct { manifest_path: []const u8, hash: ?[]const u8 = null };

/// Zig's global cache, which holds every fetched package as `p/<hash>.tar.gz`. Found through
/// `zig env` the first time a package is missing from a `zig-pkg/`.
const GlobalCache = struct {
    path: ?[]const u8 = null,

    /// The `build.zig.zon` of package `hash` from its tarball, or null when Zig has no tarball
    /// of it: then nothing was fetched through it either.
    fn manifest(global_cache: *GlobalCache, context: Context, hash: []const u8) Error!?[:0]const u8 {
        const tarball_path = try std.Io.Dir.path.join(context.arena, &.{ try global_cache.find(context), "p", try context.arena.print("{s}.tar.gz", .{hash}) });
        const file = std.Io.Dir.cwd().openFile(context.io, tarball_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return context.fail("cannot read {s}: {s}; nothing was deleted", .{ tarball_path, @errorName(err) }),
        };
        defer file.close(context.io);
        var file_buffer: [4096]u8 = undefined;
        var file_reader = file.reader(context.io, &file_buffer);
        var window: [std.compress.flate.max_window_len]u8 = undefined;
        var decompress: std.compress.flate.Decompress = .init(&file_reader.interface, .gzip, &window);
        var file_name_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        var link_name_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        var iterator: std.tar.Iterator = .init(&decompress.reader, .{ .file_name_buffer = &file_name_buffer, .link_name_buffer = &link_name_buffer });
        const wanted = try std.Io.Dir.path.join(context.arena, &.{ hash, manifest_name });
        while (iterator.next() catch |err| return context.fail("cannot read {s}: {s}; nothing was deleted", .{ tarball_path, @errorName(err) })) |entry| {
            if (entry.kind != .file or !std.mem.eql(u8, entry.name, wanted)) continue;
            var contents: std.Io.Writer.Allocating = .init(context.arena);
            iterator.streamRemaining(entry, &contents.writer) catch |err| return context.fail("cannot read {s}: {s}; nothing was deleted", .{ tarball_path, @errorName(err) });
            return try contents.toOwnedSliceSentinel(0);
        }
        return null;
    }

    fn find(global_cache: *GlobalCache, context: Context) Error![]const u8 {
        if (global_cache.path) |path| return path;
        const result = try context.runZig(&.{"env"});
        if (!result.term.success()) {
            try context.stderr.writeAll(result.stderr);
            return context.fail("zig env failed, so kosm clean cannot find Zig's global cache; nothing was deleted", .{});
        }
        var diagnostics: std.zon.parse.Diagnostics = undefined;
        const environment = std.zon.parse.fromSlice(struct { global_cache_dir: []const u8 }, .{
            .gpa = context.arena,
            .arena = context.arena,
            .source = try context.arena.dupeSentinel(u8, result.stdout, 0),
            .diagnostics = &diagnostics,
            .ignore_unknown_fields = true,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseZon => return context.fail("zig env printed no global_cache_dir, so kosm clean cannot find Zig's global cache; nothing was deleted", .{}),
        };
        // `zig env` may print it relative to the directory it ran in, the config.
        const path = try std.Io.Dir.path.resolveAlloc(context.arena, &.{ context.config, environment.global_cache_dir });
        global_cache.path = path;
        return path;
    }
};

fn exists(context: Context, path: []const u8) Error!bool {
    std.Io.Dir.cwd().access(context.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return context.fail("cannot read {s}: {s}; nothing was deleted", .{ path, @errorName(err) }),
    };
    return true;
}

/// A manifest's contents, or null when there is none (a package without one, or a lazy
/// dependency never fetched).
fn readManifest(context: Context, path: []const u8) Error!?[:0]const u8 {
    return std.Io.Dir.cwd().readFileAllocOptions(context.io, path, context.arena, .limited(max_manifest_size), .of(u8), 0) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.FileNotFound, error.NotDir => null,
        else => context.fail("cannot read {s}: {s}; nothing was deleted", .{ path, @errorName(err) }),
    };
}

/// The bytes the files under `path` (relative to the config) take, or null when it does not exist.
fn treeSize(context: Context, path: []const u8) Error!?u64 {
    const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, path });
    var dir = std.Io.Dir.cwd().openDir(context.io, full_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return context.fail("cannot read {s}: {s}; nothing was deleted", .{ full_path, @errorName(err) }),
    };
    defer dir.close(context.io);
    var walker = try dir.walk(context.arena);
    defer walker.deinit();
    var size: u64 = 0;
    while (walker.next(context.io) catch |err| return context.fail("cannot read {s}: {s}; nothing was deleted", .{ full_path, @errorName(err) })) |entry| {
        if (entry.kind != .file) continue;
        const stat = entry.dir.statFile(context.io, entry.basename, .{ .follow_symlinks = false }) catch |err|
            return context.fail("cannot read {s}/{s}: {s}; nothing was deleted", .{ full_path, entry.path, @errorName(err) });
        size += stat.size;
    }
    return size;
}

const testing = std.testing;

/// A temp config whose files are written from `path`/`contents` pairs.
const TestConfig = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,

    fn init(test_config: *TestConfig, contents: []const [2][]const u8) !void {
        test_config.tmp = testing.tmpDir(.{});
        test_config.arena = .init(testing.allocator);
        test_config.stdout = .init(test_config.arena.allocator());
        test_config.stderr = .init(test_config.arena.allocator());
        for (contents) |file| {
            if (std.Io.Dir.path.dirname(file[0])) |directory| try test_config.tmp.dir.createDirPath(testing.io, directory);
            try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
        }
    }

    fn deinit(test_config: *TestConfig) void {
        test_config.arena.deinit();
        test_config.tmp.cleanup();
    }

    fn context(test_config: *TestConfig) !Context {
        const arena = test_config.arena.allocator();
        return .{
            .io = testing.io,
            .arena = arena,
            .config = try test_config.tmp.dir.realPathFileAlloc(testing.io, ".", arena),
            .stdout = &test_config.stdout.writer,
            .stderr = &test_config.stderr.writer,
        };
    }

    fn exists(test_config: *TestConfig, path: []const u8) bool {
        test_config.tmp.dir.access(testing.io, path, .{}) catch return false;
        return true;
    }
};

fn testManifest(comptime dependencies: []const u8) []const u8 {
    return ".{ .name = .test_package, .version = \"0.0.0\", .dependencies = .{" ++ dependencies ++ "}, .paths = .{\"\"} }\n";
}

test "clean deletes the caches and only the package versions no manifest reaches" {
    var test_config: TestConfig = undefined;
    try test_config.init(&.{
        .{ "build.zig.zon", testManifest(".a = .{ .url = \"x\", .hash = \"a-new\" }, .kosm = .{ .path = \"../elsewhere\" }") },
        .{ "zig-pkg/a-new/build.zig.zon", testManifest(".c = .{ .url = \"x\", .hash = \"c-pinned\", .lazy = true }") },
        .{ "zig-pkg/a-old/root.zig", "0123456789" },
        .{ "zig-pkg/c-pinned/root.zig", "" },
        .{ ".zig-cache/o/1/kosmos", "0123456789" },
        .{ "kosmoi/frost/build.zig.zon", testManifest(".a = .{ .url = \"x\", .hash = \"a-new\" }, .ice = .{ .path = \"../ice\" }") },
        .{ "kosmoi/frost/zig-pkg/a-new/build.zig.zon", testManifest("") },
        .{ "kosmoi/frost/zig-pkg/a-old/root.zig", "0123456789" },
        .{ "kosmoi/frost/zig-pkg/d-through-path/root.zig", "" },
        .{ "kosmoi/frost/.zig-cache/h/x", "01234" },
        .{ "kosmoi/ice/build.zig.zon", testManifest(".d = .{ .url = \"x\", .hash = \"d-through-path\" }") },
        .{ "kosmoi/loose.zig", "" },
    });
    defer test_config.deinit();

    try clean(try test_config.context());
    const output = test_config.stdout.written();
    try testing.expect(std.mem.find(u8, output, "deleted .zig-cache (10B)\n") != null);
    try testing.expect(std.mem.find(u8, output, "deleted kosmoi/frost/.zig-cache (5B)\n") != null);
    try testing.expect(std.mem.endsWith(u8, output, "deleted 2 unused package versions\nfreed 35B\n"));

    for ([_][]const u8{ "zig-pkg/a-new", "zig-pkg/c-pinned", "kosmoi/frost/zig-pkg/a-new", "kosmoi/frost/zig-pkg/d-through-path", "kosmoi/loose.zig" }) |kept| {
        try testing.expect(test_config.exists(kept));
    }
    for ([_][]const u8{ "zig-pkg/a-old", ".zig-cache", "kosmoi/frost/zig-pkg/a-old", "kosmoi/frost/.zig-cache" }) |deleted| {
        try testing.expect(!test_config.exists(deleted));
    }

    test_config.stdout.clearRetainingCapacity();
    try clean(try test_config.context());
    try testing.expectEqualStrings("nothing to clean\n", test_config.stdout.written());
}

test "a package missing from zig-pkg is read from Zig's global cache" {
    var test_config: TestConfig = undefined;
    try test_config.init(&.{
        .{ "build.zig.zon", testManifest(".b = .{ .url = \"x\", .hash = \"b-only-in-cache\" }") },
        .{ "zig-pkg/e-pinned-by-b/root.zig", "" },
        .{ "zig-pkg/e-old/root.zig", "" },
    });
    defer test_config.deinit();
    const arena = test_config.arena.allocator();

    var tarball: std.Io.Writer.Allocating = .init(arena);
    var buffer: [std.compress.flate.max_window_len]u8 = undefined;
    var gzip: std.compress.flate.Compress.Raw = try .init(&tarball.writer, &buffer, .gzip);
    var tar: std.tar.Writer = .{ .underlying_writer = &gzip.writer };
    try tar.writeFileBytes("b-only-in-cache/build.zig.zon", testManifest(".e = .{ .url = \"x\", .hash = \"e-pinned-by-b\" }"), .{});
    try tar.finishPedantically();
    try gzip.finish();
    try test_config.tmp.dir.createDirPath(testing.io, "global/p");
    try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = "global/p/b-only-in-cache.tar.gz", .data = tarball.written() });

    var environ = try testing.environ.createMap(arena);
    var context = try test_config.context();
    try environ.put("ZIG_GLOBAL_CACHE_DIR", try std.Io.Dir.path.join(arena, &.{ context.config, "global" }));
    context.environ_map = &environ;

    try clean(context);
    try testing.expect(test_config.exists("zig-pkg/e-pinned-by-b"));
    try testing.expect(!test_config.exists("zig-pkg/e-old"));
}

test "clean deletes nothing when a manifest cannot be read" {
    var test_config: TestConfig = undefined;
    try test_config.init(&.{
        .{ "build.zig.zon", testManifest(".a = .{ .url = \"x\", .hash = \"a-new\" }") },
        .{ "zig-pkg/a-new/build.zig.zon", ".{ .dependencies = " },
        .{ "zig-pkg/a-old/root.zig", "" },
        .{ ".zig-cache/o/1/kosmos", "" },
    });
    defer test_config.deinit();

    try testing.expectError(error.Failed, clean(try test_config.context()));
    try testing.expect(std.mem.find(u8, test_config.stderr.written(), "a-new/build.zig.zon is not a valid manifest") != null);
    try testing.expect(test_config.exists("zig-pkg/a-old"));
    try testing.expect(test_config.exists(".zig-cache"));
}
