//! The Zig module of a package whose root script exports values for building on, generated from
//! what the script declares: a function per value (`look()`), the base the script declares
//! (`Base`) and its `from`, each calling the script's own through `kosm.Frontend.ScriptExports`.

const std = @import("std");
const kosm = @import("kosm");
const app_modules = @import("app_modules.zig");

const Declaration = kosm.Frontend.Declaration;
const ExportsDeclaration = kosm.Frontend.ExportsDeclaration;

pub const Error = app_modules.Error;

/// The module's own declaration besides the exports, which no export may be named.
const script_name = "script";

/// The source of the module for `script`, which declares `declaration`. `modules` names every
/// module the package reaches, which a Zig type must start with. Fails with
/// `error.InvalidDeclaration` after setting `diagnostics`, naming the script and line.
pub fn source(arena: std.mem.Allocator, script: app_modules.Script, declaration: ExportsDeclaration, modules: []const []const u8, diagnostics: *kosm.Diagnostics) Error![]const u8 {
    var imports: std.ArrayList([]const u8) = .empty;
    var checked: std.ArrayList(Declaration.Field) = .empty;
    for (declaration.values) |value| {
        if (std.mem.eql(u8, value.name, script_name) or std.mem.eql(u8, value.name, ExportsDeclaration.base_name))
            return app_modules.fail(diagnostics, script, value.line, "an export may not be named '{s}', which the package's Zig module declares; rename it", .{value.name});
        for (modules) |module| {
            if (std.mem.eql(u8, value.name, module)) return app_modules.fail(diagnostics, script, value.line, "an export may not be named '{s}', the name of a package or module; rename it", .{value.name});
        }
        if (std.mem.eql(u8, value.type, ExportsDeclaration.base_name)) {
            if (declaration.base == null) return app_modules.fail(diagnostics, script, value.line, "{s} gives a {s}, but the script declares none; declare its fields as {s} = {{ ... }}", .{ value.name, ExportsDeclaration.base_name, ExportsDeclaration.base_name });
        } else try addChecked(arena, script, value.name, value.type, value.line, modules, &imports, &checked, diagnostics);
        for (value.parameters) |parameter| {
            if (std.mem.eql(u8, parameter.type, ExportsDeclaration.base_name)) continue;
            try addChecked(arena, script, value.name, parameter.type, value.line, modules, &imports, &checked, diagnostics);
        }
    }
    if (declaration.base) |fields| {
        for (fields) |field| try app_modules.collectImports(arena, script, field, field.type, modules, &imports, diagnostics);
    }
    std.mem.sort([]const u8, imports.items, {}, app_modules.lessThan);

    var text: std.Io.Writer.Allocating = .init(arena);
    writeModule(&text.writer, script, declaration, imports.items, checked.items, diagnostics) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.InvalidDeclaration => return error.InvalidDeclaration,
    };
    return text.written();
}

/// Checks the Zig type `type_name` an export names, adds the module it starts with to `imports`
/// and keeps it as a field for the module's compile-time checks.
fn addChecked(arena: std.mem.Allocator, script: app_modules.Script, name: []const u8, type_name: []const u8, line: usize, modules: []const []const u8, imports: *std.ArrayList([]const u8), checked: *std.ArrayList(Declaration.Field), diagnostics: *kosm.Diagnostics) Error!void {
    const field: Declaration.Field = .{ .name = name, .type = .{ .zig = type_name }, .line = line };
    try app_modules.collectImports(arena, script, field, field.type, modules, imports, diagnostics);
    try checked.append(arena, field);
}

fn writeModule(writer: *std.Io.Writer, script: app_modules.Script, declaration: ExportsDeclaration, imports: []const []const u8, checked: []const Declaration.Field, diagnostics: *kosm.Diagnostics) app_modules.WriteError!void {
    try writer.print("//! The values {s} exports, written by kosm from it: edit the script, never this file.\n\n", .{script.path});
    try writer.writeAll("const kosm = @import(\"kosm\");\n");
    for (imports) |module| try writer.print("const {f} = @import(\"{f}\");\n", .{ std.zig.fmtId(module), std.zig.fmtString(module) });
    try writer.print(
        \\
        \\/// Where the package's script is; it runs the functions below.
        \\pub const script: kosm.Frontend.ScriptExports = .{{ .frontend = "{f}", .path = "{f}" }};
        \\
    , .{ std.zig.fmtString(script.frontend), std.zig.fmtString(script.path) });
    if (declaration.base) |fields| {
        try writer.writeAll("\n");
        if (declaration.base_doc) |doc| try app_modules.writeDoc(writer, "", doc);
        try writer.print("pub const {s} = struct {{\n", .{ExportsDeclaration.base_name});
        for (fields) |field| {
            if (field.doc) |doc| try app_modules.writeDoc(writer, "    ", doc);
            try writer.print("    {f}: ", .{std.zig.fmtId(field.name)});
            try app_modules.writeType(writer, field.type);
            try writer.writeAll(" = ");
            try app_modules.writeDefault(writer, script, field, diagnostics);
            try writer.writeAll(",\n");
        }
        try app_modules.writeTypeChecks(writer, script, .{ .fields = fields, .functions = &.{} });
        try writer.writeAll("};\n");
    }
    for (declaration.values) |value| try writeValue(writer, declaration, value, imports);
    if (checked.len != 0) try app_modules.writeTypeChecks(writer, script, .{ .fields = checked, .functions = &.{} });
}

fn writeValue(writer: *std.Io.Writer, declaration: ExportsDeclaration, value: ExportsDeclaration.Value, imports: []const []const u8) std.Io.Writer.Error!void {
    try writer.writeAll("\n");
    if (value.doc) |doc| try app_modules.writeDoc(writer, "", doc);
    try writer.print("pub fn {f}(", .{std.zig.fmtId(value.name)});
    for (value.parameters, 0..) |parameter, position| {
        if (position != 0) try writer.writeAll(", ");
        try writeParameterName(writer, declaration, parameter.name, imports);
        try writer.print(": {s}", .{parameter.type});
    }
    try writer.print(") {s} {{\n    return script.give({s}, \"{f}\", .{{", .{ value.type, value.type, std.zig.fmtString(value.name) });
    for (value.parameters, 0..) |parameter, position| {
        try writer.writeAll(if (position == 0) " " else ", ");
        try writeParameterName(writer, declaration, parameter.name, imports);
    }
    try writer.writeAll(if (value.parameters.len == 0) "});\n}\n" else " });\n}\n");
}

/// A parameter's name, with `_` after it when the module declares that name already (a base's
/// `from(look)` beside the export `look`), as Zig forbids shadowing it.
fn writeParameterName(writer: *std.Io.Writer, declaration: ExportsDeclaration, name: []const u8, imports: []const []const u8) std.Io.Writer.Error!void {
    const taken = std.mem.eql(u8, name, "kosm") or std.mem.eql(u8, name, script_name) or std.mem.eql(u8, name, ExportsDeclaration.base_name) or
        for (declaration.values) |value| {
            if (std.mem.eql(u8, value.name, name)) break true;
        } else for (imports) |module| {
            if (std.mem.eql(u8, module, name)) break true;
        } else false;
    if (taken) try writer.print("{s}_", .{name}) else try writer.print("{f}", .{std.zig.fmtId(name)});
}

const testing = std.testing;

const test_script: app_modules.Script = .{ .name = "kosm_frost", .path = "~~kosm_frost/root.lua", .frontend = "lua" };

test "exports become typed functions calling the script, and a base its struct and from" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const declaration: ExportsDeclaration = .{
        .values = &.{
            .{ .name = "look", .type = "kosm_base.Look", .doc = "Frost's look.", .line = 3 },
            .{ .name = "from", .type = "Base", .parameters = &.{.{ .name = "look", .type = "kosm_base.Look" }}, .line = 9 },
            .{ .name = "kosmos", .type = "Base", .line = 12 },
        },
        .base = &.{
            .{ .name = "official", .type = .{ .zig = "kosm_base.Base" }, .doc = "The official apps.", .line = 6 },
            .{ .name = "bars", .type = .integer, .default = .{ .value = .{ .integer = 0 } }, .line = 7 },
        },
        .base_doc = "Frost's base.",
    };
    var diagnostics: kosm.Diagnostics = .{};
    const written = try source(arena.allocator(), test_script, declaration, &.{ "kosm", "kosm_base" }, &diagnostics);
    try testing.expectEqualStrings(
        \\//! The values ~~kosm_frost/root.lua exports, written by kosm from it: edit the script, never this file.
        \\
        \\const kosm = @import("kosm");
        \\const kosm_base = @import("kosm_base");
        \\
        \\/// Where the package's script is; it runs the functions below.
        \\pub const script: kosm.Frontend.ScriptExports = .{ .frontend = "lua", .path = "~~kosm_frost/root.lua" };
        \\
        \\/// Frost's base.
        \\pub const Base = struct {
        \\    /// The official apps.
        \\    official: kosm_base.Base = .{},
        \\    bars: i64 = 0,
        \\
        \\    comptime {
        \\        if (!@hasDecl(kosm_base, "Base")) @compileError("~~kosm_frost/root.lua:6: official: kosm_base has no Base");
        \\        if (@TypeOf(kosm_base.Base) != type) @compileError("~~kosm_frost/root.lua:6: official: kosm_base.Base is not a type");
        \\    }
        \\};
        \\
        \\/// Frost's look.
        \\pub fn look() kosm_base.Look {
        \\    return script.give(kosm_base.Look, "look", .{});
        \\}
        \\
        \\pub fn from(look_: kosm_base.Look) Base {
        \\    return script.give(Base, "from", .{ look_ });
        \\}
        \\
        \\pub fn kosmos() Base {
        \\    return script.give(Base, "kosmos", .{});
        \\}
        \\
        \\    comptime {
        \\        if (!@hasDecl(kosm_base, "Look")) @compileError("~~kosm_frost/root.lua:3: look: kosm_base has no Look");
        \\        if (@TypeOf(kosm_base.Look) != type) @compileError("~~kosm_frost/root.lua:3: look: kosm_base.Look is not a type");
        \\        if (!@hasDecl(kosm_base, "Look")) @compileError("~~kosm_frost/root.lua:9: from: kosm_base has no Look");
        \\        if (@TypeOf(kosm_base.Look) != type) @compileError("~~kosm_frost/root.lua:9: from: kosm_base.Look is not a type");
        \\    }
        \\
    , written);
}

test "exports kosm cannot write fail naming the script's line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const modules: []const []const u8 = &.{ "kosm", "kosm_base" };
    const Case = struct { declaration: ExportsDeclaration, message: []const u8 };
    const cases = [_]Case{
        .{ .declaration = .{ .values = &.{.{ .name = "script", .type = "kosm_base.Look", .line = 2 }} }, .message = "~~kosm_frost/root.lua:2: an export may not be named 'script', which the package's Zig module declares; rename it" },
        .{ .declaration = .{ .values = &.{.{ .name = "kosm_base", .type = "kosm_base.Look", .line = 2 }} }, .message = "~~kosm_frost/root.lua:2: an export may not be named 'kosm_base', the name of a package or module; rename it" },
        .{ .declaration = .{ .values = &.{.{ .name = "kosmos", .type = "Base", .line = 4 }} }, .message = "~~kosm_frost/root.lua:4: kosmos gives a Base, but the script declares none; declare its fields as Base = { ... }" },
        .{ .declaration = .{ .values = &.{.{ .name = "look", .type = "kosm_frozen.Look", .line = 5 }} }, .message = "~~kosm_frost/root.lua:5: look: there is no package or module 'kosm_frozen' for kosm_frozen.Look" },
    };
    for (cases) |case| {
        var diagnostics: kosm.Diagnostics = .{};
        try testing.expectError(error.InvalidDeclaration, source(allocator, test_script, case.declaration, modules, &diagnostics));
        try testing.expectEqualStrings(case.message, diagnostics.message());
    }
}
