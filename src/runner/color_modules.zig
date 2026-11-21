//! The Zig module of a modifier or palette style written through a frontend, generated from
//! what its script declares: a type holding its fields (`Modifier`, `Style`), whose `apply` runs
//! the script's own, and a function giving it as kosm's own value (`modifier(fields)` a
//! `kosm.Modifier`, `style(fields)` a `kosm.Image.Style`). A variation family's module gives
//! its struct of modifiers, `Family`, and `from(mode)` running the script's own.

const std = @import("std");
const kosm = @import("kosm");
const app_modules = @import("app_modules.zig");

const Declaration = kosm.Frontend.Declaration;

pub const Error = app_modules.Error;

/// Declarations of the fields' type a field may not share its name with.
const reserved_fields = [_][]const u8{ "script", "apply" };

/// What the module of one kind of script looks like.
pub const Kind = struct {
    /// The type holding the fields: "Modifier".
    type_name: []const u8,
    /// What the script gives, for messages and docs: "modifier".
    noun: []const u8,
    /// The `kosm.Frontend` type of the type's `script`: "ScriptModifier".
    script_type: []const u8,
    /// `apply`'s parameters after `self`: "color: kosm.Color".
    parameters: []const u8,
    /// Those parameters' names, as `apply` passes them on: "color".
    arguments: []const u8,
    /// The script's function, for messages: "apply(self, color)".
    signature: []const u8,
    /// The function giving kosm's own value: "modifier".
    wrapper: []const u8,
    /// The value it gives: "kosm.Modifier".
    gives: []const u8,
    /// Its doc comment, as `///` lines.
    wrapper_doc: []const u8,
};

/// A modifier's module.
pub const modifier: Kind = .{
    .type_name = "Modifier",
    .noun = "modifier",
    .script_type = "ScriptModifier",
    .parameters = "color: kosm.Color",
    .arguments = "color",
    .signature = "apply(self, color)",
    .wrapper = "modifier",
    .gives = "kosm.Modifier",
    .wrapper_doc = "/// The modifier with `fields` set, as a `kosm.Modifier` to set wherever a modifier goes\n/// or to compose with `then`.\n",
};

/// A palette style's module.
pub const style: Kind = .{
    .type_name = "Style",
    .noun = "palette style",
    .script_type = "ScriptStyle",
    .parameters = "hue: kosm.Color, background: kosm.Color",
    .arguments = "hue, background",
    .signature = "apply(self, hue, background)",
    .wrapper = "style",
    .gives = "kosm.Image.Style",
    .wrapper_doc = "/// The palette style with `fields` set, as a `kosm.Image.Style` to take an image's colors\n/// with.\n",
};

/// The source of the module for `script`, which declares `declaration`. `modules` names every
/// module of the config, which a field's Zig type must start with. Fails with
/// `error.InvalidDeclaration` after setting `diagnostics`, naming the script and line.
pub fn source(arena: std.mem.Allocator, kind: Kind, script: app_modules.Script, declaration: Declaration, modules: []const []const u8, diagnostics: *kosm.Diagnostics) Error![]const u8 {
    if (!declaration.gives("apply")) return app_modules.fail(diagnostics, script, 0, "it gives no {s}; a {s}'s script returns a table with {s} and apply", .{ kind.signature, kind.noun, kind.type_name });
    var imports: std.ArrayList([]const u8) = .empty;
    for (declaration.fields) |field| {
        for (reserved_fields) |reserved| {
            if (std.mem.eql(u8, field.name, reserved)) return app_modules.fail(diagnostics, script, field.line, "a field may not be named '{s}', which the {s}'s Zig module declares; rename it", .{ field.name, kind.noun });
        }
        try app_modules.collectImports(arena, script, field, field.type, modules, &imports, diagnostics);
    }
    std.mem.sort([]const u8, imports.items, {}, app_modules.lessThan);

    var text: std.Io.Writer.Allocating = .init(arena);
    writeModule(&text.writer, kind, script, declaration, imports.items, diagnostics) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.InvalidDeclaration => return error.InvalidDeclaration,
    };
    return text.written();
}

fn writeModule(writer: *std.Io.Writer, kind: Kind, script: app_modules.Script, declaration: Declaration, imports: []const []const u8, diagnostics: *kosm.Diagnostics) app_modules.WriteError!void {
    try writer.print("//! The {s} {s} declares, written by kosm from it: edit the script, never this file.\n\n", .{ kind.noun, script.path });
    try writer.writeAll("const kosm = @import(\"kosm\");\n");
    for (imports) |module| try writer.print("const {f} = @import(\"{f}\");\n", .{ std.zig.fmtId(module), std.zig.fmtString(module) });
    try writer.writeAll("\n");
    if (declaration.doc) |doc| try app_modules.writeDoc(writer, "", doc);
    try writer.print("pub const {s} = struct {{\n", .{kind.type_name});
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
        \\    /// Where the {[noun]s}'s script is; it runs the {[noun]s}'s apply.
        \\    pub const script: kosm.Frontend.{[script_type]s} = .{{ .frontend = "{[frontend]f}", .path = "{[path]f}" }};
        \\
        \\    /// Runs the script's `{[signature]s}`.
        \\    pub fn apply(self: {[type_name]s}, {[parameters]s}) kosm.Color {{
        \\        return script.apply({[type_name]s}, self, {[arguments]s});
        \\    }}
        \\
    , .{
        .noun = kind.noun,
        .script_type = kind.script_type,
        .frontend = std.zig.fmtString(script.frontend),
        .path = std.zig.fmtString(script.path),
        .signature = kind.signature,
        .type_name = kind.type_name,
        .parameters = kind.parameters,
        .arguments = kind.arguments,
    });
    try app_modules.writeTypeChecks(writer, script, declaration);
    try writer.print(
        \\}};
        \\
        \\{[doc]s}pub fn {[wrapper]s}(fields: {[type_name]s}) {[gives]s} {{
        \\    return .{{ .function = .of({[type_name]s}, fields) }};
        \\}}
        \\
    , .{ .doc = kind.wrapper_doc, .wrapper = kind.wrapper, .type_name = kind.type_name, .gives = kind.gives });
}

/// The source of the module for the variation family `script`, which declares `declaration`,
/// as `source` writes a modifier's.
pub fn familySource(arena: std.mem.Allocator, script: app_modules.Script, declaration: Declaration, modules: []const []const u8, diagnostics: *kosm.Diagnostics) Error![]const u8 {
    if (!declaration.gives("from")) return app_modules.fail(diagnostics, script, 0, "it gives no from(mode); a variation family's script returns a table with Family and from", .{});
    var imports: std.ArrayList([]const u8) = .empty;
    for (declaration.fields) |field| {
        if (std.mem.eql(u8, field.name, "script")) return app_modules.fail(diagnostics, script, field.line, "a field may not be named 'script', which the family's Zig module declares; rename it", .{});
        try app_modules.collectImports(arena, script, field, field.type, modules, &imports, diagnostics);
    }
    std.mem.sort([]const u8, imports.items, {}, app_modules.lessThan);

    var text: std.Io.Writer.Allocating = .init(arena);
    writeFamily(&text.writer, script, declaration, imports.items, diagnostics) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.InvalidDeclaration => return error.InvalidDeclaration,
    };
    return text.written();
}

fn writeFamily(writer: *std.Io.Writer, script: app_modules.Script, declaration: Declaration, imports: []const []const u8, diagnostics: *kosm.Diagnostics) app_modules.WriteError!void {
    try writer.print("//! The variation family {s} declares, written by kosm from it: edit the script, never this file.\n\n", .{script.path});
    try writer.writeAll("const kosm = @import(\"kosm\");\n");
    for (imports) |module| try writer.print("const {f} = @import(\"{f}\");\n", .{ std.zig.fmtId(module), std.zig.fmtString(module) });
    try writer.writeAll("\n");
    if (declaration.doc) |doc| try app_modules.writeDoc(writer, "", doc);
    try writer.writeAll("pub const Family = struct {\n");
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
        \\    /// Where the family's script is; it runs the family's from.
        \\    pub const script: kosm.Frontend.ScriptFamily = .{{ .frontend = "{f}", .path = "{f}" }};
        \\
    , .{ std.zig.fmtString(script.frontend), std.zig.fmtString(script.path) });
    try app_modules.writeTypeChecks(writer, script, declaration);
    try writer.writeAll(
        \\};
        \\
        \\/// The family's modifiers for `mode`, from the script's `from(mode)`; a base holds it beside
        \\/// the theme.
        \\pub fn from(mode: kosm.Theme.Mode) Family {
        \\    return Family.script.from(Family, mode);
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
    const written = try source(arena.allocator(), modifier, test_script, declaration, &.{"kosm"}, &diagnostics);
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
    try testing.expectError(error.InvalidDeclaration, source(arena.allocator(), modifier, test_script, .{ .functions = &.{}, .fields = &.{} }, &.{"kosm"}, &diagnostics));
    try testing.expectEqualStrings("colors/sepia.lua: it gives no apply(self, color); a modifier's script returns a table with Modifier and apply", diagnostics.message());
    const clashing: Declaration = .{ .functions = &.{"apply"}, .fields = &.{.{ .name = "script", .type = .boolean, .default = .{ .value = .{ .boolean = true } }, .line = 3 }} };
    try testing.expectError(error.InvalidDeclaration, source(arena.allocator(), modifier, test_script, clashing, &.{"kosm"}, &diagnostics));
    try testing.expectEqualStrings("colors/sepia.lua:3: a field may not be named 'script', which the modifier's Zig module declares; rename it", diagnostics.message());
}

test "a palette style's module takes the hue and the background and gives a kosm.Image.Style" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const pastel: app_modules.Script = .{ .name = "pastel", .path = "colors/pastel.lua", .frontend = "lua" };
    var diagnostics: kosm.Diagnostics = .{};
    const written = try source(arena.allocator(), style, pastel, .{ .functions = &.{"apply"}, .fields = &.{} }, &.{"kosm"}, &diagnostics);
    try testing.expectEqualStrings(
        \\//! The palette style colors/pastel.lua declares, written by kosm from it: edit the script, never this file.
        \\
        \\const kosm = @import("kosm");
        \\
        \\pub const Style = struct {
        \\    /// Where the palette style's script is; it runs the palette style's apply.
        \\    pub const script: kosm.Frontend.ScriptStyle = .{ .frontend = "lua", .path = "colors/pastel.lua" };
        \\
        \\    /// Runs the script's `apply(self, hue, background)`.
        \\    pub fn apply(self: Style, hue: kosm.Color, background: kosm.Color) kosm.Color {
        \\        return script.apply(Style, self, hue, background);
        \\    }
        \\};
        \\
        \\/// The palette style with `fields` set, as a `kosm.Image.Style` to take an image's colors
        \\/// with.
        \\pub fn style(fields: Style) kosm.Image.Style {
        \\    return .{ .function = .of(Style, fields) };
        \\}
        \\
    , written);
}

test "a variation family's module holds its modifiers and runs the script's from(mode)" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const glow: app_modules.Script = .{ .name = "glow", .path = "colors/glow.lua", .frontend = "lua" };
    const declaration: Declaration = .{
        .doc = "Glows for highlighted elements.",
        .functions = &.{"from"},
        .fields = &.{.{ .name = "soft", .doc = "A soft glow.", .type = .{ .zig = "kosm.Modifier" }, .line = 5 }},
    };
    var diagnostics: kosm.Diagnostics = .{};
    const written = try familySource(arena.allocator(), glow, declaration, &.{"kosm"}, &diagnostics);
    try testing.expectEqualStrings(
        \\//! The variation family colors/glow.lua declares, written by kosm from it: edit the script, never this file.
        \\
        \\const kosm = @import("kosm");
        \\
        \\/// Glows for highlighted elements.
        \\pub const Family = struct {
        \\    /// A soft glow.
        \\    soft: kosm.Modifier = .{},
        \\
        \\    /// Where the family's script is; it runs the family's from.
        \\    pub const script: kosm.Frontend.ScriptFamily = .{ .frontend = "lua", .path = "colors/glow.lua" };
        \\
        \\    comptime {
        \\        if (!@hasDecl(kosm, "Modifier")) @compileError("colors/glow.lua:5: soft: kosm has no Modifier");
        \\        if (@TypeOf(kosm.Modifier) != type) @compileError("colors/glow.lua:5: soft: kosm.Modifier is not a type");
        \\    }
        \\};
        \\
        \\/// The family's modifiers for `mode`, from the script's `from(mode)`; a base holds it beside
        \\/// the theme.
        \\pub fn from(mode: kosm.Theme.Mode) Family {
        \\    return Family.script.from(Family, mode);
        \\}
        \\
    , written);
    try testing.expectError(error.InvalidDeclaration, familySource(arena.allocator(), glow, .{ .functions = &.{}, .fields = &.{} }, &.{"kosm"}, &diagnostics));
    try testing.expectEqualStrings("colors/glow.lua: it gives no from(mode); a variation family's script returns a table with Family and from", diagnostics.message());
}
