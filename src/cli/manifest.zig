//! Reads and edits `build.zig.zon` manifests: a config project's dependencies and a
//! directory kosmos' own manifest. An edit replaces only the bytes of the entry or value
//! involved, so comments and formatting elsewhere survive.

const std = @import("std");
const Ast = std.zig.Ast;
const Zoir = std.zig.Zoir;

/// `InvalidManifest`: the source is not ZON, or not a struct; `zig build` explains why.
pub const Error = error{ OutOfMemory, InvalidManifest };

/// Zig's package fingerprint: the name's CRC-32 in the high half, a random id in the low half,
/// never 0 or all ones.
pub fn fingerprint(io: std.Io, name: []const u8) u64 {
    var id: u32 = 0;
    while (id == 0 or id == std.math.maxInt(u32)) io.random(std.mem.asBytes(&id));
    return @as(u64, std.hash.Crc32.hash(name)) << 32 | id;
}

/// The names in `.dependencies`, in file order.
pub fn dependencyNames(arena: std.mem.Allocator, source: [:0]const u8) Error![]const []const u8 {
    const parsed = try parse(arena, source);
    const found = parsed.dependencies orelse return &.{};
    const names = try arena.alloc([]const u8, found.names.len);
    for (found.names, names) |name, *slot| slot.* = name.get(&parsed.zoir);
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
    const found = parsed.dependencies orelse return null;
    const index = for (found.names, 0..) |existing, index| {
        if (std.mem.eql(u8, existing.get(&parsed.zoir), name)) break index;
    } else return null;
    const value = found.vals.at(@intCast(index)).getAstNode(&parsed.zoir);
    const range = try entryRange(&parsed.ast, value);
    const lines = wholeLines(source, range);
    return try std.mem.concat(arena, u8, &.{ source[0..lines.start], source[lines.end..] });
}

/// One entry of `.dependencies`: a `url` with its `hash`, or a `path`.
pub const Dependency = struct {
    name: []const u8,
    url: ?[]const u8 = null,
    hash: ?[]const u8 = null,
    /// Relative to the manifest's directory.
    path: ?[]const u8 = null,
    lazy: ?bool = null,
};

/// Every entry of `.dependencies`, in file order.
pub fn dependencies(arena: std.mem.Allocator, source: [:0]const u8) Error![]const Dependency {
    const parsed = try parse(arena, source);
    const found = parsed.dependencies orelse return &.{};
    const result = try arena.alloc(Dependency, found.names.len);
    for (found.names, result, 0..) |name, *slot, index| {
        var diagnostics: std.zon.parse.Diagnostics = undefined;
        const Fields = struct { url: ?[]const u8 = null, hash: ?[]const u8 = null, path: ?[]const u8 = null, lazy: ?bool = null };
        const fields = std.zon.parse.fromZoir(Fields, .{
            .arena = arena,
            .ast = &parsed.ast,
            .zoir = &parsed.zoir,
            .node = found.vals.at(@intCast(index)),
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseZon => return error.InvalidManifest,
        };
        slot.* = .{ .name = name.get(&parsed.zoir), .url = fields.url, .hash = fields.hash, .path = fields.path, .lazy = fields.lazy };
    }
    return result;
}

/// The top-level string field `name` (`.minimum_zig_version`), or null when it is missing or
/// not a string.
pub fn stringField(arena: std.mem.Allocator, source: [:0]const u8, name: []const u8) Error!?[]const u8 {
    const parsed = try parse(arena, source);
    const index = fieldIndex(&parsed, name) orelse return null;
    return switch (parsed.root.vals.at(@intCast(index)).get(&parsed.zoir)) {
        .string_literal => |text| text,
        else => null,
    };
}

/// The package name, the top-level `.name = .identifier`; null when it is missing or not an
/// enum literal.
pub fn packageName(arena: std.mem.Allocator, source: [:0]const u8) Error!?[]const u8 {
    const parsed = try parse(arena, source);
    const index = fieldIndex(&parsed, "name") orelse return null;
    return switch (parsed.root.vals.at(@intCast(index)).get(&parsed.zoir)) {
        .enum_literal => |literal| literal.get(&parsed.zoir),
        else => null,
    };
}

/// `source` with the top-level field `name` set to `value`, a ZON expression: the old value's
/// bytes are replaced, or the field is added after the last one.
pub fn withField(arena: std.mem.Allocator, source: [:0]const u8, name: []const u8, value: []const u8) Error![]const u8 {
    const parsed = try parse(arena, source);
    const ast = &parsed.ast;
    if (fieldIndex(&parsed, name)) |index| {
        const node = parsed.root.vals.at(@intCast(index)).getAstNode(&parsed.zoir);
        const first = ast.firstToken(node);
        const last = ast.lastToken(node);
        const end = ast.tokenStart(last) + ast.tokenSlice(last).len;
        return std.mem.concat(arena, u8, &.{ source[0..ast.tokenStart(first)], value, source[end..] });
    }
    const closing = ast.lastToken(Zoir.Node.Index.root.getAstNode(&parsed.zoir));
    const previous = closing - 1;
    const after_previous = ast.tokenStart(previous) + ast.tokenSlice(previous).len;
    const separator = if (ast.tokenTag(previous) == .comma or ast.tokenTag(previous) == .l_brace) "" else ",";
    const field = try arena.print("{s}\n    .{f} = {s},", .{ separator, std.zig.fmtId(name), value });
    return std.mem.concat(arena, u8, &.{ source[0..after_previous], field, source[after_previous..] });
}

const StructLiteral = @FieldType(Zoir.Node, "struct_literal");

const Parsed = struct {
    ast: Ast,
    zoir: Zoir,
    root: StructLiteral,
    /// The `.dependencies` struct, or null when it is missing or empty.
    dependencies: ?StructLiteral,
};

fn fieldIndex(parsed: *const Parsed, name: []const u8) ?usize {
    for (parsed.root.names, 0..) |field, index| {
        if (std.mem.eql(u8, field.get(&parsed.zoir), name)) return index;
    }
    return null;
}

fn parse(arena: std.mem.Allocator, source: [:0]const u8) Error!Parsed {
    const ast = try Ast.parse(arena, source, .{ .mode = .zon });
    if (ast.errors.len != 0) return error.InvalidManifest;
    const zoir = try std.zig.ZonGen.generate(arena, ast, .{});
    if (zoir.hasCompileErrors()) return error.InvalidManifest;
    const root = switch (Zoir.Node.Index.root.get(&zoir)) {
        .struct_literal => |root| root,
        else => return error.InvalidManifest,
    };
    var parsed: Parsed = .{ .ast = ast, .zoir = zoir, .root = root, .dependencies = null };
    const index = fieldIndex(&parsed, "dependencies") orelse return parsed;
    parsed.dependencies = switch (root.vals.at(@intCast(index)).get(&zoir)) {
        .struct_literal => |found| found,
        .empty_literal => null,
        else => return error.InvalidManifest,
    };
    return parsed;
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

test "dependency entries are read with their url, hash or path" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const found = try dependencies(arena.allocator(), config_manifest);
    try testing.expectEqual(4, found.len);
    try testing.expectEqualStrings("../kosm", found[0].path.?);
    try testing.expectEqual(null, found[0].url);
    try testing.expectEqualStrings("git+https://example.com/kosm_kitty?ref=main#0123", found[1].url.?);
    try testing.expectEqualStrings("kosm_kitty-0.0.0-AAAA", found[1].hash.?);
    try testing.expectError(error.InvalidManifest, dependencies(arena.allocator(), ".{ .dependencies = .{ .x = .{ .url = 1 } } }"));
}

test "a field's value is replaced in place, or added after the last field" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const replaced = try withField(arena.allocator(), config_manifest, "paths", ".{ \"root.zig\" }");
    try testing.expectEqualStrings(config_manifest[0 .. config_manifest.len - "    .paths = .{\"\"},\n}".len] ++ "    .paths = .{ \"root.zig\" },\n}", replaced);
    const added = try withField(arena.allocator(), ".{\n    .name = .nord,\n    // kept\n}\n", "paths", ".{}");
    try testing.expectEqualStrings(".{\n    .name = .nord,\n    .paths = .{},\n    // kept\n}\n", added);
    const without_comma = try withField(arena.allocator(), ".{ .name = .nord }", "paths", ".{}");
    try testing.expectEqualStrings(".{ .name = .nord,\n    .paths = .{}, }", without_comma);
    try testing.expectEqualStrings("0.17.0", (try stringField(arena.allocator(), ".{ .minimum_zig_version = \"0.17.0\" }", "minimum_zig_version")).?);
    try testing.expectEqual(null, try stringField(arena.allocator(), ".{ .name = .nord }", "minimum_zig_version"));
}
