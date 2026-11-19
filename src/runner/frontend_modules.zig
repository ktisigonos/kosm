//! The Zig modules of frontends written through a frontend: kosm reads what each script declares
//! while it builds the config, and writes a module giving `frontend`, a `kosm.Frontend` whose
//! functions run the script's own. Like an app's, a module is written only when its contents
//! change, so editing a function compiles nothing.

const std = @import("std");
const kosm = @import("kosm");
const app_modules = @import("app_modules.zig");

const FrontendDeclaration = kosm.Frontend.FrontendDeclaration;

/// The functions a script may give, by `kosm.Frontend`'s names.
const functions = [_][]const u8{ "load", "variants", "complete" };

pub const Error = app_modules.Error;

/// The source of the module for `script`, which declares `declaration`. Fails with
/// `error.InvalidDeclaration` after setting `diagnostics`, naming the script.
pub fn source(arena: std.mem.Allocator, script: app_modules.Script, declaration: FrontendDeclaration, diagnostics: *kosm.Diagnostics) Error![]const u8 {
    try check(script, declaration, diagnostics);
    var text: std.Io.Writer.Allocating = .init(arena);
    writeModule(&text.writer, script, declaration) catch return error.OutOfMemory;
    return text.written();
}

fn check(script: app_modules.Script, declaration: FrontendDeclaration, diagnostics: *kosm.Diagnostics) error{InvalidDeclaration}!void {
    if (declaration.name.len == 0) return fail(diagnostics, script.path, "it gives no name; a frontend's name is its language's, as \"json\"", .{});
    if (!isPlainName(declaration.name)) return fail(diagnostics, script.path, "its name '{s}' names a folder of completion files, so it is letters, digits, '_' and '-'", .{declaration.name});
    if (declaration.extensions.len == 0) return fail(diagnostics, script.path, "it claims no extensions, so it reads no kosmos; give them as {{ \".json\" }}", .{});
    for (declaration.extensions) |extension| {
        if (extension.len < 2 or extension[0] != '.') return fail(diagnostics, script.path, "extension '{s}' does not start with a dot, as \".json\"", .{extension});
        if (std.mem.eql(u8, extension, ".zig") or std.mem.eql(u8, extension, ".zon")) return fail(diagnostics, script.path, "it claims '{s}', which is Zig's", .{extension});
    }
    if (declaration.editor_file) |file| {
        if (!isPlainName(file.path) and !isDotName(file.path)) return fail(diagnostics, script.path, "its editor file '{s}' is no file name; it is a file in the config's root, as \".luarc.json\"", .{file.path});
    }
    for (declaration.functions) |function| {
        for (functions) |known| {
            if (std.mem.eql(u8, function, known)) break;
        } else return fail(diagnostics, script.path, "'{s}' is no function of a frontend; a frontend gives load, variants and complete", .{function});
    }
    if (!declaration.gives("load")) return fail(diagnostics, script.path, "it gives no load(source, path, variant), so it reads no kosmos", .{});
}

/// Whether `name` is letters, digits, `_`, `-` and `.`, not starting with a dot.
fn isPlainName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    for (name) |character| {
        if (!std.ascii.isAlphanumeric(character) and character != '_' and character != '-' and character != '.') return false;
    }
    return !std.mem.eql(u8, name, "..");
}

/// Whether `name` is a hidden file's name, ".luarc.json".
fn isDotName(name: []const u8) bool {
    return name.len > 1 and name[0] == '.' and name[1] != '.' and isPlainName(name[1..]);
}

fn writeModule(writer: *std.Io.Writer, script: app_modules.Script, declaration: FrontendDeclaration) std.Io.Writer.Error!void {
    try writer.print(
        \\//! The frontend {s} declares, written by kosm from it: edit the script, never this file.
        \\
        \\const kosm = @import("kosm");
        \\
        \\/// Where the frontend's script is; it runs the frontend's functions.
        \\pub const script: kosm.Frontend.ScriptFrontend = .{{ .frontend = "{f}", .path = "{f}" }};
        \\
        \\const functions = kosm.Frontend.ScriptFrontend.Functions(script);
        \\
        \\/// The {f} frontend, written in {f}.
        \\pub const frontend: kosm.Frontend = .{{
        \\    .name = "{f}",
        \\    .extensions = &.{{
    , .{
        script.path,
        std.zig.fmtString(script.frontend),
        std.zig.fmtString(script.path),
        std.zig.fmtString(declaration.name),
        std.zig.fmtString(script.frontend),
        std.zig.fmtString(declaration.name),
    });
    for (declaration.extensions, 0..) |extension, index| try writer.print("{s}\"{f}\"", .{ if (index == 0) " " else ", ", std.zig.fmtString(extension) });
    try writer.writeAll(" },\n");
    for (functions) |function| {
        if (declaration.gives(function)) try writer.print("    .{s} = functions.{s},\n", .{ function, function });
    }
    if (declaration.editor_file) |file| try writer.print("    .editor_file = .{{ .path = \"{f}\", .contents = \"{f}\" }},\n", .{ std.zig.fmtString(file.path), std.zig.fmtString(file.contents) });
    try writer.writeAll("};\n");
}

/// Records why `where` cannot become a module.
fn fail(diagnostics: *kosm.Diagnostics, where: []const u8, comptime format: []const u8, arguments: anytype) error{InvalidDeclaration} {
    var buffer: [512]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, format, arguments) catch buffer[0..];
    diagnostics.set("", "", "{s}: {s}", .{ where, message });
    return error.InvalidDeclaration;
}

const testing = std.testing;

const test_script: app_modules.Script = .{ .name = "json", .path = "frontends/json.lua", .frontend = "lua" };

test "a declaration becomes a frontend with its data and the functions the script gives" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const declaration: FrontendDeclaration = .{
        .name = "json",
        .extensions = &.{ ".json", ".jsonc" },
        .editor_file = .{ .path = ".jsonrc", .contents = "{ \"a\": 1 }\n" },
        .functions = &.{ "complete", "load" },
    };
    var diagnostics: kosm.Diagnostics = .{};
    try testing.expectEqualStrings(
        \\//! The frontend frontends/json.lua declares, written by kosm from it: edit the script, never this file.
        \\
        \\const kosm = @import("kosm");
        \\
        \\/// Where the frontend's script is; it runs the frontend's functions.
        \\pub const script: kosm.Frontend.ScriptFrontend = .{ .frontend = "lua", .path = "frontends/json.lua" };
        \\
        \\const functions = kosm.Frontend.ScriptFrontend.Functions(script);
        \\
        \\/// The json frontend, written in lua.
        \\pub const frontend: kosm.Frontend = .{
        \\    .name = "json",
        \\    .extensions = &.{ ".json", ".jsonc" },
        \\    .load = functions.load,
        \\    .complete = functions.complete,
        \\    .editor_file = .{ .path = ".jsonrc", .contents = "{ \"a\": 1 }\n" },
        \\};
        \\
    , try source(arena.allocator(), test_script, declaration, &diagnostics));
}

test "a frontend declaration kosm cannot write fails naming the script" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const Case = struct { declaration: FrontendDeclaration, message: []const u8 };
    const cases = [_]Case{
        .{ .declaration = .{ .name = "", .extensions = &.{".json"}, .functions = &.{"load"} }, .message = "frontends/json.lua: it gives no name; a frontend's name is its language's, as \"json\"" },
        .{ .declaration = .{ .name = "../x", .extensions = &.{".json"}, .functions = &.{"load"} }, .message = "frontends/json.lua: its name '../x' names a folder of completion files, so it is letters, digits, '_' and '-'" },
        .{ .declaration = .{ .name = "json", .functions = &.{"load"} }, .message = "frontends/json.lua: it claims no extensions, so it reads no kosmos; give them as { \".json\" }" },
        .{ .declaration = .{ .name = "json", .extensions = &.{"json"}, .functions = &.{"load"} }, .message = "frontends/json.lua: extension 'json' does not start with a dot, as \".json\"" },
        .{ .declaration = .{ .name = "json", .extensions = &.{".zig"}, .functions = &.{"load"} }, .message = "frontends/json.lua: it claims '.zig', which is Zig's" },
        .{ .declaration = .{ .name = "json", .extensions = &.{".json"}, .editor_file = .{ .path = "../.vimrc", .contents = "" }, .functions = &.{"load"} }, .message = "frontends/json.lua: its editor file '../.vimrc' is no file name; it is a file in the config's root, as \".luarc.json\"" },
        .{ .declaration = .{ .name = "json", .extensions = &.{".json"}, .functions = &.{ "load", "parse" } }, .message = "frontends/json.lua: 'parse' is no function of a frontend; a frontend gives load, variants and complete" },
        .{ .declaration = .{ .name = "json", .extensions = &.{".json"}, .functions = &.{"variants"} }, .message = "frontends/json.lua: it gives no load(source, path, variant), so it reads no kosmos" },
    };
    for (cases) |case| {
        var diagnostics: kosm.Diagnostics = .{};
        try testing.expectError(error.InvalidDeclaration, source(arena.allocator(), test_script, case.declaration, &diagnostics));
        try testing.expectEqualStrings(case.message, diagnostics.message());
    }
}
