//! The Zig module of a modifier written through a frontend, generated from what its script
//! declares: a `Modifier` type holding its fields, whose `apply` runs the script's own, and
//! `modifier(fields)` giving it as a `kosm.Modifier` to set wherever a modifier goes.

const std = @import("std");
const kosm = @import("kosm");
const app_modules = @import("app_modules.zig");

const Declaration = kosm.Frontend.Declaration;

pub const Error = app_modules.Error;

/// Declarations of `Modifier` a field may not share its name with.
const reserved_fields = [_][]const u8{ "script", "apply" };

/// The source of the module for `script`, which declares `declaration`. `modules` names every
/// module of the config, which a field's Zig type must start with. Fails with
/// `error.InvalidDeclaration` after setting `diagnostics`, naming the script and line.
pub fn source(arena: std.mem.Allocator, script: app_modules.Script, declaration: Declaration, modules: []const []const u8, diagnostics: *kosm.Diagnostics) Error![]const u8 {
    if (!declaration.gives("apply")) return app_modules.fail(diagnostics, script, 0, "it gives no apply(self, color); a modifier's script returns a table with Modifier and apply", .{});
    var imports: std.ArrayList([]const u8) = .empty;
    for (declaration.fields) |field| {
        for (reserved_fields) |reserved| {
            if (std.mem.eql(u8, field.name, reserved)) return app_modules.fail(diagnostics, script, field.line, "a field may not be named '{s}', which the modifier's Zig module declares; rename it", .{field.name});
        }
        try app_modules.collectImports(arena, script, field, field.type, modules, &imports, diagnostics);
    }
    std.mem.sort([]const u8, imports.items, {}, app_modules.lessThan);

    var text: std.Io.Writer.Allocating = .init(arena);
    writeModule(&text.writer, script, declaration, imports.items, diagnostics) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.InvalidDeclaration => return error.InvalidDeclaration,
    };
    return text.written();
}

fn writeModule(writer: *std.Io.Writer, script: app_modules.Script, declaration: Declaration, imports: []const []const u8, diagnostics: *kosm.Diagnostics) app_modules.WriteError!void {
    try writer.print("//! The modifier {s} declares, written by kosm from it: edit the script, never this file.\n\n", .{script.path});
    try writer.writeAll("const kosm = @import(\"kosm\");\n");
    for (imports) |module| try writer.print("const {f} = @import(\"{f}\");\n", .{ std.zig.fmtId(module), std.zig.fmtString(module) });
    try writer.writeAll("\n");
    if (declaration.doc) |doc| try app_modules.writeDoc(writer, "", doc);
    try writer.writeAll("pub const Modifier = struct {\n");
    for (declaration.fields) |field| {
        if (field.doc) |doc| try app_modules.writeDoc(writer, "    ", doc);
        try writer.print("    {f}: ", .{std.zig.fmtId(field.name)});
        try app_modules.writeType(writer, field.type);
        try writer.writeAll(" = ");
        try app_modules.writeDefault(writer, script, field, diagnostics);
        try writer.writeAll(",\n");
    }
    if (declaration.fields.len != 0) try writer.writeAll("\n");
    try writer.print(
        \\    /// Where the modifier's script is; it runs the modifier's apply.
        \\    pub const script: kosm.Frontend.ScriptModifier = .{{ .frontend = "{f}", .path = "{f}" }};
        \\
        \\    /// Runs the script's `apply(self, color)`.
        \\    pub fn apply(self: Modifier, color: kosm.Color) kosm.Color {{
        \\        return script.apply(Modifier, self, color);
        \\    }}
        \\
    , .{ std.zig.fmtString(script.frontend), std.zig.fmtString(script.path) });
    try app_modules.writeTypeChecks(writer, script, declaration);
    try writer.writeAll(
        \\};
        \\
        \\/// The modifier with `fields` set, as a `kosm.Modifier` to set wherever a modifier goes
        \\/// or to compose with `then`.
        \\pub fn modifier(fields: Modifier) kosm.Modifier {
        \\    return .{ .function = .of(Modifier, fields) };
        \\}
        \\
    );
}

const testing = std.testing;

const test_script: app_modules.Script = .{ .name = "sepia", .path = "colors/sepia.lua", .frontend = "lua" };

test "a declaration becomes a modifier with documented fields whose apply runs the script" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const declaration: Declaration = .{
        .doc = "Tints toward sepia.",
        .functions = &.{"apply"},
        .fields = &.{
            .{ .name = "amount", .doc = "How far toward sepia, 0..1.", .type = .float, .default = .{ .value = .{ .integer = 1 } }, .line = 4 },
            .{ .name = "tint", .type = .{ .zig = "kosm.Color" }, .line = 5 },
        },
    };
    var diagnostics: kosm.Diagnostics = .{};
    const written = try source(arena.allocator(), test_script, declaration, &.{"kosm"}, &diagnostics);
    try testing.expectEqualStrings(
        \\//! The modifier colors/sepia.lua declares, written by kosm from it: edit the script, never this file.
        \\
        \\const kosm = @import("kosm");
        \\
        \\/// Tints toward sepia.
        \\pub const Modifier = struct {
        \\    /// How far toward sepia, 0..1.
        \\    amount: f64 = 1,
        \\    tint: kosm.Color = .{},
        \\
        \\    /// Where the modifier's script is; it runs the modifier's apply.
        \\    pub const script: kosm.Frontend.ScriptModifier = .{ .frontend = "lua", .path = "colors/sepia.lua" };
        \\
        \\    /// Runs the script's `apply(self, color)`.
        \\    pub fn apply(self: Modifier, color: kosm.Color) kosm.Color {
        \\        return script.apply(Modifier, self, color);
        \\    }
        \\
        \\    comptime {
        \\        if (!@hasDecl(kosm, "Color")) @compileError("colors/sepia.lua:5: tint: kosm has no Color");
        \\        if (@TypeOf(kosm.Color) != type) @compileError("colors/sepia.lua:5: tint: kosm.Color is not a type");
        \\    }
        \\};
        \\
        \\/// The modifier with `fields` set, as a `kosm.Modifier` to set wherever a modifier goes
        \\/// or to compose with `then`.
        \\pub fn modifier(fields: Modifier) kosm.Modifier {
        \\    return .{ .function = .of(Modifier, fields) };
        \\}
        \\
    , written);
}

test "a modifier without apply, or with a field its module declares, fails naming the script" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostics: kosm.Diagnostics = .{};
    try testing.expectError(error.InvalidDeclaration, source(arena.allocator(), test_script, .{ .functions = &.{}, .fields = &.{} }, &.{"kosm"}, &diagnostics));
    try testing.expectEqualStrings("colors/sepia.lua: it gives no apply(self, color); a modifier's script returns a table with Modifier and apply", diagnostics.message());
    const clashing: Declaration = .{ .functions = &.{"apply"}, .fields = &.{.{ .name = "script", .type = .boolean, .default = .{ .value = .{ .boolean = true } }, .line = 3 }} };
    try testing.expectError(error.InvalidDeclaration, source(arena.allocator(), test_script, clashing, &.{"kosm"}, &diagnostics));
    try testing.expectEqualStrings("colors/sepia.lua:3: a field may not be named 'script', which the modifier's Zig module declares; rename it", diagnostics.message());
}
