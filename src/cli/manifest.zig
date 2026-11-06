//! Reads and edits the dependencies in a config project's `build.zig.zon` (D46). An edit replaces
//! only the bytes of the entry involved, so comments and formatting elsewhere survive (D35).

const std = @import("std");
const Ast = std.zig.Ast;
const Zoir = std.zig.Zoir;

/// `InvalidManifest`: the source is not ZON, or not a struct; `zig build` explains why.
pub const Error = error{ OutOfMemory, InvalidManifest };

/// The names in `.dependencies`, in file order.
pub fn dependencyNames(arena: std.mem.Allocator, source: [:0]const u8) Error![]const []const u8 {
    const parsed = try parse(arena, source);
    const dependencies = parsed.dependencies orelse return &.{};
    const names = try arena.alloc([]const u8, dependencies.names.len);
    for (dependencies.names, names) |name, *slot| slot.* = name.get(&parsed.zoir);
    return names;
}

/// Whether `.dependencies` has an entry `name`.
pub fn hasDependency(arena: std.mem.Allocator, source: [:0]const u8, name: []const u8) Error!bool {
    for (try dependencyNames(arena, source)) |existing| {
        if (std.mem.eql(u8, existing, name)) return true;
    }
    return false;
}

/// `source` without the dependency `name`, or null when there is none. When the entry has
/// lines to itself, those lines go; otherwise only the entry and its comma.
pub fn withoutDependency(arena: std.mem.Allocator, source: [:0]const u8, name: []const u8) Error!?[]const u8 {
    const parsed = try parse(arena, source);
    const dependencies = parsed.dependencies orelse return null;
    const index = for (dependencies.names, 0..) |existing, index| {
        if (std.mem.eql(u8, existing.get(&parsed.zoir), name)) break index;
    } else return null;
    const value = dependencies.vals.at(@intCast(index)).getAstNode(&parsed.zoir);
    const range = try entryRange(&parsed.ast, value);
    const lines = wholeLines(source, range);
    return try std.mem.concat(arena, u8, &.{ source[0..lines.start], source[lines.end..] });
}

const Parsed = struct {
    ast: Ast,
    zoir: Zoir,
    /// The `.dependencies` struct, or null when it is missing or empty.
    dependencies: ?Dependencies,

    const Dependencies = @FieldType(Zoir.Node, "struct_literal");
};

fn parse(arena: std.mem.Allocator, source: [:0]const u8) Error!Parsed {
    const ast = try Ast.parse(arena, source, .{ .mode = .zon });
    if (ast.errors.len != 0) return error.InvalidManifest;
    const zoir = try std.zig.ZonGen.generate(arena, ast, .{});
    if (zoir.hasCompileErrors()) return error.InvalidManifest;
    const root = switch (Zoir.Node.Index.root.get(&zoir)) {
        .struct_literal => |root| root,
        else => return error.InvalidManifest,
    };
    for (root.names, 0..) |field, index| {
        if (!std.mem.eql(u8, field.get(&zoir), "dependencies")) continue;
        return switch (root.vals.at(@intCast(index)).get(&zoir)) {
            .struct_literal => |dependencies| .{ .ast = ast, .zoir = zoir, .dependencies = dependencies },
            .empty_literal => .{ .ast = ast, .zoir = zoir, .dependencies = null },
            else => error.InvalidManifest,
        };
    }
    return .{ .ast = ast, .zoir = zoir, .dependencies = null };
}

const Range = struct { start: usize, end: usize };

/// The bytes of `.name = value`, and the comma after it if there is one.
fn entryRange(ast: *const Ast, value: Ast.Node.Index) Error!Range {
    const first = ast.firstToken(value);
    if (first < 3 or ast.tokenTag(first - 1) != .equal or ast.tokenTag(first - 2) != .identifier or ast.tokenTag(first - 3) != .period)
        return error.InvalidManifest;
    var last = ast.lastToken(value);
    if (ast.tokenTag(last + 1) == .comma) last += 1;
    return .{ .start = ast.tokenStart(first - 3), .end = ast.tokenStart(last) + ast.tokenSlice(last).len };
}

/// `range` grown to whole lines when only spaces, and a comment after it, share its lines.
fn wholeLines(source: []const u8, range: Range) Range {
    var start = range.start;
    while (start > 0 and isBlank(source[start - 1])) start -= 1;
    if (start != 0 and source[start - 1] != '\n') return range;
    var end = range.end;
    while (end < source.len and isBlank(source[end])) end += 1;
    if (std.mem.startsWith(u8, source[end..], "//")) end = std.mem.findScalarPos(u8, source, end, '\n') orelse source.len;
    if (end != source.len and source[end] != '\n') return range;
    return .{ .start = start, .end = @min(end + 1, source.len) };
}

fn isBlank(byte: u8) bool {
    return byte == ' ' or byte == '\t';
}

const testing = std.testing;

const config_manifest =
    \\.{
    \\    .name = .config,
    \\    .version = "0.0.0",
    \\    .dependencies = .{
    \\        .kosm = .{ .path = "../kosm" }, // the kosm this config runs on
    \\        .kosm_kitty = .{
    \\            .url = "git+https://example.com/kosm_kitty?ref=main#0123",
    \\            .hash = "kosm_kitty-0.0.0-AAAA",
    \\        },
    \\        .@"kosm_css" = .{ .url = "file:///x.tar", .hash = "kosm_css-0.0.0-BBBB" }, .last = .{ .path = "last" } },
    \\    .paths = .{""},
    \\}
;

test "dependency names come in file order, quoted names unquoted" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const names = try dependencyNames(arena.allocator(), config_manifest);
    try testing.expectEqual(4, names.len);
    try testing.expectEqualStrings("kosm_kitty", names[1]);
    try testing.expectEqualStrings("kosm_css", names[2]);
    try testing.expect(try hasDependency(arena.allocator(), config_manifest, "last"));
    try testing.expect(!try hasDependency(arena.allocator(), config_manifest, "kosm_zen"));
    try testing.expectEqual(0, (try dependencyNames(arena.allocator(), ".{ .name = .x, .dependencies = .{} }")).len);
}

test "removing an entry on its own lines removes exactly those lines" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const removed = (try withoutDependency(arena.allocator(), config_manifest, "kosm_kitty")).?;
    try testing.expectEqualStrings(
        \\.{
        \\    .name = .config,
        \\    .version = "0.0.0",
        \\    .dependencies = .{
        \\        .kosm = .{ .path = "../kosm" }, // the kosm this config runs on
        \\        .@"kosm_css" = .{ .url = "file:///x.tar", .hash = "kosm_css-0.0.0-BBBB" }, .last = .{ .path = "last" } },
        \\    .paths = .{""},
        \\}
    , removed);
}

test "removing an entry sharing its line keeps the rest of the line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const without_css = (try withoutDependency(arena.allocator(), config_manifest, "kosm_css")).?;
    try testing.expect(std.mem.find(u8, without_css, "        .last = .{ .path = \"last\" } },\n") != null);
    const without_last = (try withoutDependency(arena.allocator(), config_manifest, "last")).?;
    try testing.expect(std.mem.find(u8, without_last, "\"kosm_css-0.0.0-BBBB\" },  },\n") != null);
    const without_kosm = (try withoutDependency(arena.allocator(), config_manifest, "kosm")).?;
    try testing.expect(std.mem.find(u8, without_kosm, "the kosm this config") == null);
    try testing.expectEqual(config_manifest.len - without_kosm.len, "        .kosm = .{ .path = \"../kosm\" }, // the kosm this config runs on\n".len);
}

test "removing a missing entry or editing a broken manifest changes nothing" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(null, try withoutDependency(arena.allocator(), config_manifest, "kosm_zen"));
    try testing.expectEqual(null, try withoutDependency(arena.allocator(), ".{ .name = .x }", "kosm"));
    try testing.expectError(error.InvalidManifest, dependencyNames(arena.allocator(), ".{ .dependencies = .{ "));
    try testing.expectError(error.InvalidManifest, dependencyNames(arena.allocator(), "42"));
}
