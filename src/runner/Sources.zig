//! The Zig sources of the config's modules, read to find what reflection cannot give: the doc
//! comments of types, fields and kosmos functions, and the names they are declared under. A
//! type is found by following its declaration from a module's root through declarations,
//! `@import`s and inline structs; what cannot be followed (a type a function returns) simply
//! has no doc, which is never an error.

const Sources = @This();

const std = @import("std");
const Ast = std.zig.Ast;

/// Holds every file read and everything found in it, for the whole run.
arena: std.mem.Allocator,
io: std.Io,
/// Every module a type may be declared in.
modules: []const Module,
/// Files already read, by absolute path; null for one that could not be read or parsed.
files: std.StringHashMapUnmanaged(?*const SourceFile) = .empty,
/// The name of each file, by absolute path: its shortest public path from a module's root
/// ("kosm.Palette"), so a type is named as a user imports it, not by an alias a file keeps
/// to itself. Filled on first use.
public_names: ?std.StringHashMapUnmanaged([]const u8) = null,

pub const Error = std.mem.Allocator.Error;

/// A module's import name and the absolute path of its root file.
pub const Module = struct {
    name: []const u8,
    root: []const u8,
};

/// A struct, union, enum or file in a source, and where names used in it are looked up.
pub const Container = struct {
    /// What it is declared as, from its module: "kosm_kitty.App", "kosm_kitty.App.fonts".
    name: []const u8,
    file: *const SourceFile,
    /// The container's node; `.root` for a whole file.
    node: Ast.Node.Index,
    /// The container written around it in the same file, whose declarations it sees too.
    parent: ?*const Container,
};

/// A type written somewhere in a source, and the container it is written in.
pub const Expression = struct {
    scope: *const Container,
    node: Ast.Node.Index,
};

/// A field of a container as its source writes it.
pub const FieldSource = struct {
    doc: ?[]const u8,
    type: ?Expression,
};

/// A declaration as its source writes it.
pub const Declaration = struct {
    /// Declared as, from its module: "kosm_kitty.App".
    name: []const u8,
    doc: ?[]const u8,
    /// What a constant is set to; null for a function.
    value: ?Expression,
    /// A function's prototype.
    function: ?Function,
};

/// A function's parameter and return types as its source writes them.
pub const Function = struct {
    /// The first parameter's type, when it has one.
    parameter: ?Expression,
    /// Every parameter, in order.
    parameters: []const Parameter = &.{},
    return_type: ?Expression,
};

/// One parameter of a function as its source writes it.
pub const Parameter = struct {
    /// Null for one without a name (`_`).
    name: ?[]const u8,
    type: ?Expression,
};

/// One parsed file.
pub const SourceFile = struct {
    path: []const u8,
    ast: Ast,
};

/// How deeply declarations may refer to each other before a type counts as not found.
const max_depth = 32;

/// The root of module `name`, or null when it is unknown or cannot be read.
pub fn module(sources: *Sources, name: []const u8) Error!?*const Container {
    for (sources.modules) |known| {
        if (!std.mem.eql(u8, known.name, name)) continue;
        const file = try sources.read(known.root) orelse return null;
        return try sources.makeContainer(name, file, .root, null);
    }
    return null;
}

/// The declaration a path of names leads to from module `name`'s root (`&.{ "Theme", "Input" }`),
/// or null when it cannot be followed.
pub fn declarationPath(sources: *Sources, name: []const u8, path: []const []const u8) Error!?Declaration {
    var current = try sources.module(name) orelse return null;
    for (path, 0..) |segment, index| {
        const found = try sources.declaration(current, segment) orelse return null;
        if (index + 1 == path.len) return found;
        const value = found.value orelse return null;
        current = try sources.resolve(value, found.name, 0) orelse return null;
    }
    return null;
}

/// The function a constant declaration names (`pub const from = App.from;`), keeping the
/// constant's doc when it has one; `found` itself when it is a function or names none.
pub fn followAlias(sources: *Sources, found: Declaration) Error!Declaration {
    var current = found;
    var depth: usize = 0;
    while (current.function == null) : (depth += 1) {
        if (depth > max_depth) return found;
        const value = current.value orelse return found;
        const ast = &value.scope.file.ast;
        if (ast.nodeTag(value.node) != .field_access) return found;
        const left, const name_token = ast.nodeData(value.node).node_and_token;
        const namespace = try sources.resolve(.{ .scope = value.scope, .node = left }, "", 0) orelse return found;
        current = try sources.declaration(namespace, ast.tokenSlice(name_token)) orelse return found;
    }
    if (found.doc != null) current.doc = found.doc;
    return current;
}

/// The declaration `name` written directly in `scope`, or null.
pub fn declaration(sources: *Sources, scope: *const Container, name: []const u8) Error!?Declaration {
    const ast = &scope.file.ast;
    var buffer: [2]Ast.Node.Index = undefined;
    const decl = ast.fullContainerDecl(&buffer, scope.node) orelse return null;
    for (decl.ast.members) |member| {
        if (ast.fullVarDecl(member)) |variable| {
            if (!std.mem.eql(u8, ast.tokenSlice(variable.ast.mut_token + 1), name)) continue;
            return .{
                .name = try sources.qualified(scope.name, name),
                .doc = try sources.docBefore(scope.file, ast.firstToken(member)),
                .value = if (variable.ast.init_node.unwrap()) |init| .{ .scope = scope, .node = init } else null,
                .function = null,
            };
        }
        if (ast.nodeTag(member) != .fn_decl) continue;
        var parameter_buffer: [1]Ast.Node.Index = undefined;
        const prototype = ast.fullFnProto(&parameter_buffer, member) orelse continue;
        const name_token = prototype.name_token orelse continue;
        if (!std.mem.eql(u8, ast.tokenSlice(name_token), name)) continue;
        var parameters = prototype.iterate(ast);
        var written: std.ArrayList(Parameter) = .empty;
        while (parameters.next()) |parameter| try written.append(sources.arena, .{
            .name = if (parameter.name_token) |token| ast.tokenSlice(token) else null,
            .type = if (parameter.type_expr) |node| .{ .scope = scope, .node = node } else null,
        });
        const first: ?Parameter = if (written.items.len != 0) written.items[0] else null;
        return .{
            .name = try sources.qualified(scope.name, name),
            .doc = try sources.docBefore(scope.file, ast.firstToken(member)),
            .value = null,
            .function = .{
                .parameter = if (first) |parameter| parameter.type else null,
                .parameters = written.items,
                .return_type = if (prototype.ast.return_type.unwrap()) |node| .{ .scope = scope, .node = node } else null,
            },
        };
    }
    return null;
}

/// The field (or union tag) `name` of `scope`, or null.
pub fn field(sources: *Sources, scope: *const Container, name: []const u8) Error!?FieldSource {
    const ast = &scope.file.ast;
    var buffer: [2]Ast.Node.Index = undefined;
    const decl = ast.fullContainerDecl(&buffer, scope.node) orelse return null;
    for (decl.ast.members) |member| {
        const container_field = ast.fullContainerField(member) orelse continue;
        const spelled = ast.tokenSlice(container_field.ast.main_token);
        if (!std.mem.eql(u8, unquoted(spelled), name)) continue;
        // A union tag or enum value without a type parses like a tuple's field.
        const type_node = if (container_field.ast.tuple_like) null else container_field.ast.type_expr.unwrap();
        return .{
            .doc = try sources.docBefore(scope.file, ast.firstToken(member)),
            .type = if (type_node) |node| .{ .scope = scope, .node = node } else null,
        };
    }
    return null;
}

/// The doc comment of the container itself: a file's `//!` lines; null for an inline one, whose
/// doc is the field's or declaration's.
pub fn containerDoc(sources: *Sources, scope: *const Container) Error!?[]const u8 {
    if (scope.node != .root) return null;
    const ast = &scope.file.ast;
    var text: std.ArrayList(u8) = .empty;
    var token: Ast.TokenIndex = 0;
    while (token < ast.tokens.len and ast.tokenTag(token) == .container_doc_comment) : (token += 1) {
        try appendDocLine(sources.arena, &text, ast.tokenSlice(token));
    }
    return if (text.items.len == 0) null else text.items;
}

/// The container `expression` names, through optionals, error unions, pointers, slices, arrays,
/// declarations and imports; `hint` names it when it is written inline. Null when it cannot be
/// followed.
pub fn resolve(sources: *Sources, expression: Expression, hint: []const u8, depth: usize) Error!?*const Container {
    if (depth > max_depth) return null;
    const ast = &expression.scope.file.ast;
    const node = expression.node;
    const inner: ?Ast.Node.Index = switch (ast.nodeTag(node)) {
        .optional_type => ast.nodeData(node).node,
        .error_union => ast.nodeData(node).node_and_node[1],
        .ptr_type_aligned, .ptr_type_sentinel, .ptr_type, .ptr_type_bit_range => ast.fullPtrType(node).?.ast.child_type,
        .array_type, .array_type_sentinel => ast.fullArrayType(node).?.ast.elem_type,
        else => null,
    };
    if (inner) |child| return sources.resolve(.{ .scope = expression.scope, .node = child }, hint, depth + 1);
    var buffer: [2]Ast.Node.Index = undefined;
    if (ast.fullContainerDecl(&buffer, node) != null) return try sources.makeContainer(hint, expression.scope.file, node, expression.scope);
    switch (ast.nodeTag(node)) {
        .identifier => {
            const name = ast.tokenSlice(ast.nodeMainToken(node));
            var scope: ?*const Container = expression.scope;
            while (scope) |current| : (scope = current.parent) {
                const found = try sources.declaration(current, name) orelse continue;
                return sources.resolveDeclaration(found, depth);
            }
            return null;
        },
        .field_access => {
            const left, const name_token = ast.nodeData(node).node_and_token;
            const namespace = try sources.resolve(.{ .scope = expression.scope, .node = left }, hint, depth + 1) orelse return null;
            const found = try sources.declaration(namespace, ast.tokenSlice(name_token)) orelse return null;
            return sources.resolveDeclaration(found, depth);
        },
        .builtin_call_two, .builtin_call_two_comma, .builtin_call, .builtin_call_comma => {
            if (std.mem.eql(u8, ast.tokenSlice(ast.nodeMainToken(node)), "@This")) return expression.scope;
            const imported = try sources.importName(ast, node) orelse return null;
            if (!std.mem.endsWith(u8, imported, ".zig")) return sources.module(imported);
            const file = try sources.importedFile(expression.scope, imported) orelse return null;
            return try sources.makeContainer(try sources.publicName(file.path) orelse hint, file, .root, null);
        },
        else => return null,
    }
}

/// How many declarations deep `publicName` looks below a module's root.
const max_public_depth = 4;

/// The shortest public path naming the file at `path` from any module's root, or null when no
/// public declaration reaches it.
fn publicName(sources: *Sources, path: []const u8) Error!?[]const u8 {
    if (sources.public_names == null) try sources.findPublicNames();
    return sources.public_names.?.get(path);
}

/// Walks every module's public declarations breadth first, naming each file the first time a
/// declaration reaches it; modules' roots are named after the modules.
fn findPublicNames(sources: *Sources) Error!void {
    sources.public_names = .empty;
    const names = &sources.public_names.?;
    var level: std.ArrayList(*const Container) = .empty;
    for (sources.modules) |known| {
        const file = try sources.read(known.root) orelse continue;
        if (names.contains(file.path)) continue;
        try names.put(sources.arena, file.path, known.name);
        try level.append(sources.arena, try sources.makeContainer(known.name, file, .root, null));
    }
    for (0..max_public_depth) |_| {
        var next: std.ArrayList(*const Container) = .empty;
        for (level.items) |scope| {
            const ast = &scope.file.ast;
            var buffer: [2]Ast.Node.Index = undefined;
            const decl = ast.fullContainerDecl(&buffer, scope.node) orelse continue;
            for (decl.ast.members) |member| {
                const variable = ast.fullVarDecl(member) orelse continue;
                if (variable.visib_token == null) continue;
                const init = variable.ast.init_node.unwrap() orelse continue;
                const name = try sources.qualified(scope.name, ast.tokenSlice(variable.ast.mut_token + 1));
                // Named only by the import itself: resolving through other declarations here
                // would ask for the names being found.
                const imported = try sources.importName(ast, init) orelse {
                    var inline_buffer: [2]Ast.Node.Index = undefined;
                    if (ast.fullContainerDecl(&inline_buffer, init) != null) try next.append(sources.arena, try sources.makeContainer(name, scope.file, init, scope));
                    continue;
                };
                if (!std.mem.endsWith(u8, imported, ".zig")) continue;
                const found = try sources.importedFile(scope, imported) orelse continue;
                if (names.contains(found.path)) continue;
                try names.put(sources.arena, found.path, name);
                try next.append(sources.arena, try sources.makeContainer(name, found, .root, null));
            }
        }
        level = next;
    }
}

/// What `node` imports ("App.zig", "kosm") when it is `@import("...")`; null otherwise.
fn importName(sources: *Sources, ast: *const Ast, node: Ast.Node.Index) Error!?[]const u8 {
    switch (ast.nodeTag(node)) {
        .builtin_call_two, .builtin_call_two_comma => {},
        else => return null,
    }
    if (!std.mem.eql(u8, ast.tokenSlice(ast.nodeMainToken(node)), "@import")) return null;
    var buffer: [2]Ast.Node.Index = undefined;
    const parameters = ast.builtinCallParams(&buffer, node) orelse return null;
    if (parameters.len != 1 or ast.nodeTag(parameters[0]) != .string_literal) return null;
    return std.zig.string_literal.parseAlloc(sources.arena, ast.tokenSlice(ast.nodeMainToken(parameters[0]))) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => null,
    };
}

/// The file `imported` ("sections/Fonts.zig") names from the file of `scope`, or null when it
/// cannot be read.
fn importedFile(sources: *Sources, scope: *const Container, imported: []const u8) Error!?*const SourceFile {
    const directory = std.Io.Dir.path.dirname(scope.file.path) orelse return null;
    return sources.read(try std.Io.Dir.path.resolveAlloc(sources.arena, &.{ directory, imported }));
}

fn resolveDeclaration(sources: *Sources, found: Declaration, depth: usize) Error!?*const Container {
    const value = found.value orelse return null;
    return sources.resolve(value, found.name, depth + 1);
}

fn makeContainer(sources: *Sources, name: []const u8, file: *const SourceFile, node: Ast.Node.Index, parent: ?*const Container) Error!*const Container {
    const created = try sources.arena.create(Container);
    created.* = .{ .name = name, .file = file, .node = node, .parent = parent };
    return created;
}

/// The parsed file at `path`, read once; null when it cannot be read or does not parse.
fn read(sources: *Sources, path: []const u8) Error!?*const SourceFile {
    if (sources.files.get(path)) |known| return known;
    const parsed = try sources.parse(path);
    try sources.files.put(sources.arena, try sources.arena.dupe(u8, path), parsed);
    return parsed;
}

/// Far beyond any source; a guard against reading something else by mistake.
const size_limit = 16 * 1024 * 1024;

fn parse(sources: *Sources, path: []const u8) Error!?*const SourceFile {
    const bytes = std.Io.Dir.cwd().readFileAllocOptions(sources.io, path, sources.arena, .limited(size_limit), .of(u8), 0) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    const ast = try Ast.parse(sources.arena, bytes, .{});
    if (ast.errors.len != 0) return null;
    const file = try sources.arena.create(SourceFile);
    file.* = .{ .path = try sources.arena.dupe(u8, path), .ast = ast };
    return file;
}

fn qualified(sources: *Sources, scope: []const u8, name: []const u8) Error![]const u8 {
    return sources.arena.print("{s}.{s}", .{ scope, name });
}

/// The `///` lines right before `token`, joined by newlines without their slashes; null for none.
fn docBefore(sources: *Sources, file: *const SourceFile, token: Ast.TokenIndex) Error!?[]const u8 {
    const ast = &file.ast;
    var first = token;
    while (first > 0 and ast.tokenTag(first - 1) == .doc_comment) first -= 1;
    if (first == token) return null;
    var text: std.ArrayList(u8) = .empty;
    for (first..token) |line| try appendDocLine(sources.arena, &text, ast.tokenSlice(@intCast(line)));
    return text.items;
}

/// Appends one doc comment line without its `///` or `//!` and the space after it.
fn appendDocLine(arena: std.mem.Allocator, text: *std.ArrayList(u8), line: []const u8) Error!void {
    var content = line[3..];
    if (std.mem.startsWith(u8, content, " ")) content = content[1..];
    if (text.items.len != 0) try text.append(arena, '\n');
    try text.appendSlice(arena, std.mem.trimEnd(u8, content, " \t\r"));
}

/// A field name as reflection gives it: `@"error"` is `error`.
fn unquoted(spelled: []const u8) []const u8 {
    if (std.mem.startsWith(u8, spelled, "@\"") and spelled.len >= 3) return spelled[2 .. spelled.len - 1];
    return spelled;
}

const testing = std.testing;

/// Writes `files` (path, then contents) into a temporary folder and returns sources whose one
/// module, `app`, has the first file as its root.
fn testSources(arena: std.mem.Allocator, tmp: *testing.TmpDir, files: []const [2][]const u8) !Sources {
    for (files) |file| {
        if (std.Io.Dir.path.dirname(file[0])) |directory| try tmp.dir.createDirPath(testing.io, directory);
        try tmp.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
    }
    const root = try tmp.dir.realPathFileAlloc(testing.io, files[0][0], arena);
    const modules = try arena.dupe(Module, &.{.{ .name = "app", .root = root }});
    return .{ .arena = arena, .io = testing.io, .modules = modules };
}

test "fields and declarations are found through imports, aliases, inline structs, optionals and lists" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var sources = try testSources(arena, &tmp, &.{
        .{
            "root.zig",
            \\//! The app.
            \\/// The settings.
            \\pub const App = @import("App.zig");
            \\pub const Shared = @import("Shared.zig");
            \\
        },
        .{ "Shared.zig", "on: bool = false,\n" },
        .{
            "App.zig",
            \\//! Every setting,
            \\//! grouped.
            \\const Self = @This();
            \\/// Font settings.
            \\fonts: struct {
            \\    /// Size in points.
            \\    /// Default: 10.
            \\    size: u16 = 10,
            \\} = .{},
            \\cursor: ?[]const sections.Cursor = null,
            \\@"error": u8 = 0,
            \\me: ?*const Self = null,
            \\shared: Own = .{},
            \\const Own = @import("Shared.zig");
            \\const sections = struct {
            \\    pub const Cursor = @import("sections/Cursor.zig");
            \\};
            \\
        },
        .{
            "sections/Cursor.zig",
            \\/// Whether it blinks.
            \\blink: bool = false,
            \\
        },
    });
    const app = (try sources.declarationPath("app", &.{"App"})).?;
    try testing.expectEqualStrings("app.App", app.name);
    try testing.expectEqualStrings("The settings.", app.doc.?);
    const container = (try sources.resolve(app.value.?, app.name, 0)).?;
    try testing.expectEqualStrings("Every setting,\ngrouped.", (try sources.containerDoc(container)).?);

    const fonts = (try sources.field(container, "fonts")).?;
    try testing.expectEqualStrings("Font settings.", fonts.doc.?);
    const fonts_container = (try sources.resolve(fonts.type.?, "app.App.fonts", 0)).?;
    try testing.expectEqualStrings("app.App.fonts", fonts_container.name);
    try testing.expectEqualStrings("Size in points.\nDefault: 10.", (try sources.field(fonts_container, "size")).?.doc.?);

    const cursor = (try sources.field(container, "cursor")).?;
    try testing.expectEqual(null, cursor.doc);
    const cursor_container = (try sources.resolve(cursor.type.?, "unused", 0)).?;
    try testing.expectEqualStrings("app.App.sections.Cursor", cursor_container.name);
    try testing.expectEqualStrings("Whether it blinks.", (try sources.field(cursor_container, "blink")).?.doc.?);

    // A file is named by its public path, not by the alias a file keeps to itself.
    try testing.expectEqualStrings("app.Shared", (try sources.resolve((try sources.field(container, "shared")).?.type.?, "unused", 0)).?.name);
    try testing.expect(try sources.field(container, "error") != null);
    try testing.expectEqual(container.node, (try sources.resolve((try sources.field(container, "me")).?.type.?, "unused", 0)).?.node);
}

test "a kosmos function gives its parameter and return types, and what cannot be followed is null" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var sources = try testSources(arena, &tmp, &.{
        .{
            "root.zig",
            \\const kosm = @import("kosm");
            \\pub const Params = struct { size: u8 = 1 };
            \\pub const group = struct {
            \\    /// A variant.
            \\    pub fn iced(params: Params) !Made(u8) {
            \\        _ = params;
            \\    }
            \\};
            \\fn Made(comptime T: type) type {
            \\    return struct { value: T };
            \\}
            \\pub const missing = @import("missing.zig");
            \\pub const other = kosm.Color;
            \\/// The group's variant.
            \\pub const alias = group.iced;
            \\
        },
    });
    const alias = try sources.followAlias((try sources.declarationPath("app", &.{"alias"})).?);
    try testing.expectEqualStrings("The group's variant.", alias.doc.?);
    try testing.expectEqualStrings("params", alias.function.?.parameters[0].name.?);
    const iced = (try sources.declarationPath("app", &.{ "group", "iced" })).?;
    try testing.expectEqualStrings("A variant.", iced.doc.?);
    const function = iced.function.?;
    try testing.expectEqualStrings("app.Params", (try sources.resolve(function.parameter.?, "unused", 0)).?.name);
    try testing.expectEqual(null, try sources.resolve(function.return_type.?, "unused", 0));
    try testing.expectEqual(null, try sources.resolve((try sources.declarationPath("app", &.{"missing"})).?.value.?, "unused", 0));
    try testing.expectEqual(null, try sources.resolve((try sources.declarationPath("app", &.{"other"})).?.value.?, "unused", 0));
    try testing.expectEqual(null, try sources.declarationPath("app", &.{ "group", "none" }));
}
