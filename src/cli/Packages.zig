//! A config project's `packages.zon`: for each package `kosm add` installed, the url and ref the
//! user asked for, so `kosm update` can fetch them again (D46).

const Packages = @This();

const std = @import("std");

/// Sorted by name.
entries: std.ArrayList(Package) = .empty,

/// What one `kosm add <url>[#ref]` asked for.
pub const Package = struct {
    name: []const u8,
    /// As typed, without the `#ref`.
    url: []const u8,
    /// The branch or tag to follow; null follows the default branch.
    ref: ?[]const u8 = null,

    /// The argument for `zig fetch`: the url, then `#ref` when there is one.
    pub fn fetchArgument(package: Package, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        const ref = package.ref orelse return package.url;
        return std.mem.concat(allocator, u8, &.{ package.url, "#", ref });
    }
};

/// The file name in the config's root.
pub const file_name = "packages.zon";

/// Kept at the top of the file, so nobody deletes it as a copy of build.zig.zon.
const header =
    \\// Written by kosm add, remove and update (D46); edit it through them.
    \\// This file records what you asked for: each package's url and the ref to follow.
    \\// build.zig.zon records the commit and hash that resolved to, which loses the ref,
    \\// so this is not a duplicate: kosm update fetches each package from here.
    \\
;

/// A packages file is a few lines per package; anything bigger is not one.
const max_size = 1024 * 1024;

pub const LoadError = error{ ParseZon, OutOfMemory } || std.Io.Dir.ReadFileAllocError;

/// Reads `path` into `arena`; a missing file has no packages. On `error.ParseZon`,
/// `diagnostics` says what is wrong with the file.
pub fn load(arena: std.mem.Allocator, io: std.Io, path: []const u8, diagnostics: *std.zon.parse.Diagnostics) LoadError!Packages {
    const source = std.Io.Dir.cwd().readFileAllocOptions(io, path, arena, .limited(max_size), .of(u8), 0) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => |other| return other,
    };
    return parse(arena, source, diagnostics);
}

/// Reads `.{ .name = .{ .url = "...", .ref = "..." }, ... }` into `arena`.
pub fn parse(arena: std.mem.Allocator, source: [:0]const u8, diagnostics: *std.zon.parse.Diagnostics) error{ ParseZon, OutOfMemory }!Packages {
    const ast = try std.zig.Ast.parse(arena, source, .{ .mode = .zon });
    const zoir = try std.zig.ZonGen.generate(arena, ast, .{});
    const options: std.zon.parse.FromZoirOptions = .{ .arena = arena, .ast = &ast, .zoir = &zoir, .diagnostics = diagnostics, .ignore_unknown_fields = true };
    // Checks the syntax and that the root is a struct, with the usual diagnostics.
    _ = try std.zon.parse.fromZoir(struct {}, options);
    var packages: Packages = .{};
    const root = switch (std.zig.Zoir.Node.Index.root.get(&zoir)) {
        .struct_literal => |root| root,
        else => return packages,
    };
    for (root.names, 0..) |name, index| {
        var entry_options = options;
        entry_options.node = root.vals.at(@intCast(index));
        entry_options.ignore_unknown_fields = false;
        const entry = try std.zon.parse.fromZoir(struct { url: []const u8, ref: ?[]const u8 = null }, entry_options);
        try packages.put(arena, .{ .name = name.get(&zoir), .url = entry.url, .ref = entry.ref });
    }
    return packages;
}

/// The package named `name`, or null.
pub fn find(packages: Packages, name: []const u8) ?Package {
    const index = packages.indexOf(name) orelse return null;
    return packages.entries.items[index];
}

/// Adds `package`, replacing one of the same name.
pub fn put(packages: *Packages, allocator: std.mem.Allocator, package: Package) std.mem.Allocator.Error!void {
    if (packages.indexOf(package.name)) |index| {
        packages.entries.items[index] = package;
        return;
    }
    const index = for (packages.entries.items, 0..) |existing, index| {
        if (std.mem.lessThan(u8, package.name, existing.name)) break index;
    } else packages.entries.items.len;
    try packages.entries.insert(allocator, index, package);
}

/// Removes the package named `name`; returns whether there was one.
pub fn remove(packages: *Packages, name: []const u8) bool {
    const index = packages.indexOf(name) orelse return false;
    _ = packages.entries.orderedRemove(index);
    return true;
}

fn indexOf(packages: Packages, name: []const u8) ?usize {
    for (packages.entries.items, 0..) |package, index| {
        if (std.mem.eql(u8, package.name, name)) return index;
    }
    return null;
}

/// Replaces the file at `path` atomically.
pub fn save(packages: Packages, io: std.Io, path: []const u8) !void {
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true });
    defer atomic.deinit(io);
    var buffer: [1024]u8 = undefined;
    var file_writer = atomic.file.writer(io, &buffer);
    packages.write(&file_writer.interface) catch return file_writer.err orelse error.WriteFailed;
    file_writer.interface.flush() catch return file_writer.err orelse error.WriteFailed;
    try atomic.replace(io);
}

/// The whole file, header included.
pub fn write(packages: Packages, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll(header);
    try writer.writeAll(".{\n");
    for (packages.entries.items) |package| {
        try writer.print("    .{f} = .{{ .url = \"{f}\"", .{ std.zig.fmtId(package.name), std.zig.fmtString(package.url) });
        if (package.ref) |ref| try writer.print(", .ref = \"{f}\"", .{std.zig.fmtString(ref)});
        try writer.writeAll(" },\n");
    }
    try writer.writeAll("}\n");
}

const testing = std.testing;

test "a written file reads back the same, sorted by name" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var packages: Packages = .{};
    try packages.put(arena.allocator(), .{ .name = "kosm_zen", .url = "git+https://example.com/zen" });
    try packages.put(arena.allocator(), .{ .name = "kosm_css", .url = "git+https://example.com/\"css\"", .ref = "v1.0" });
    try packages.put(arena.allocator(), .{ .name = "kosm_kitty", .url = "file:///kitty.tar" });
    var output: std.Io.Writer.Allocating = .init(arena.allocator());
    try packages.write(&output.writer);
    try testing.expect(std.mem.startsWith(u8, output.written(), "// Written by kosm add"));
    try testing.expect(std.mem.endsWith(u8, output.written(),
        \\.{
        \\    .kosm_css = .{ .url = "git+https://example.com/\"css\"", .ref = "v1.0" },
        \\    .kosm_kitty = .{ .url = "file:///kitty.tar" },
        \\    .kosm_zen = .{ .url = "git+https://example.com/zen" },
        \\}
        \\
    ));

    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const read = try parse(arena.allocator(), try arena.allocator().dupeSentinel(u8, output.written(), 0), &diagnostics);
    try testing.expectEqual(3, read.entries.items.len);
    try testing.expectEqualStrings("git+https://example.com/\"css\"", read.find("kosm_css").?.url);
    try testing.expectEqualStrings("v1.0", read.find("kosm_css").?.ref.?);
    try testing.expectEqual(null, read.find("kosm_zen").?.ref);
}

test "put replaces a package of the same name and remove drops it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var packages: Packages = .{};
    try packages.put(arena.allocator(), .{ .name = "kosm_css", .url = "old" });
    try packages.put(arena.allocator(), .{ .name = "kosm_css", .url = "new", .ref = "main" });
    try testing.expectEqual(1, packages.entries.items.len);
    try testing.expectEqualStrings("new", packages.find("kosm_css").?.url);
    try testing.expect(packages.remove("kosm_css"));
    try testing.expect(!packages.remove("kosm_css"));
    try testing.expectEqual(null, packages.find("kosm_css"));
}

test "a ref is passed to zig fetch after a #" {
    const with_ref: Package = .{ .name = "x", .url = "git+https://example.com/x", .ref = "main" };
    const argument = try with_ref.fetchArgument(testing.allocator);
    defer testing.allocator.free(argument);
    try testing.expectEqualStrings("git+https://example.com/x#main", argument);
    const without_ref: Package = .{ .name = "x", .url = "file:///x.tar" };
    try testing.expectEqualStrings("file:///x.tar", try without_ref.fetchArgument(testing.allocator));
}

test "a broken file or a bad entry is a parse error" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    try testing.expectError(error.ParseZon, parse(arena.allocator(), ".{ .x = ", &diagnostics));
    try testing.expectError(error.ParseZon, parse(arena.allocator(), "42", &diagnostics));
    try testing.expectError(error.ParseZon, parse(arena.allocator(), ".{ .x = .{ .ref = \"main\" } }", &diagnostics));
    try testing.expectError(error.ParseZon, parse(arena.allocator(), ".{ .x = .{ .url = \"u\", .hash = \"h\" } }", &diagnostics));
    try testing.expectEqual(0, (try parse(arena.allocator(), ".{}", &diagnostics)).entries.items.len);
}
