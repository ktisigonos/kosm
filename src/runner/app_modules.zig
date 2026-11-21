//! The Zig modules of apps written through a frontend (and, through `adapter_modules` and
//! `frontend_modules`, of adapters and frontends): kosm reads what each script declares
//! while it builds the config, and writes a module giving `App`, `from` and `App.apply` like a
//! Zig app's, its functions running the script's own. A module is written only when its contents
//! change, so a script edit that leaves its declaration alone compiles nothing.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const Target = @import("Target.zig");

const Declaration = kosm.Frontend.Declaration;

/// A script app, as the build of a config hands it over.
pub const Script = struct {
    /// The module's name: "cava".
    name: []const u8,
    /// The script relative to the config, for messages and `ScriptApp.path`: "apps/cava/root.lua".
    path: []const u8,
    /// The frontend reading it, by `Frontend.name`.
    frontend: []const u8,
};

/// The functions a generated module calls; any other a script gives is its own.
const known_functions = [_][]const u8{ "from", "apply", "reload" };

/// Declarations of `App` a field may not share its name with.
const reserved_fields = [_][]const u8{ "script", "apply", "reload" };

pub const Error = std.mem.Allocator.Error || error{InvalidDeclaration};

/// The source of the module for `script`, which declares `declaration`. `modules` names every
/// module of the config, which a field's Zig type must start with. Fails with
/// `error.InvalidDeclaration` after setting `diagnostics`, naming the script and line.
pub fn source(arena: std.mem.Allocator, script: Script, declaration: Declaration, modules: []const []const u8, diagnostics: *kosm.Diagnostics) Error![]const u8 {
    if (!declaration.gives("apply")) return fail(diagnostics, script, 0, "it gives no apply(self, output); an app's script returns a table with App, apply and usually from", .{});
    var imports: std.ArrayList([]const u8) = .empty;
    for (declaration.fields) |field| {
        for (reserved_fields) |reserved| {
            if (std.mem.eql(u8, field.name, reserved)) return fail(diagnostics, script, field.line, "a field may not be named '{s}', which the app's Zig module declares; rename it", .{field.name});
        }
        try collectImports(arena, script, field, field.type, modules, &imports, diagnostics);
    }
    std.mem.sort([]const u8, imports.items, {}, lessThan);

    var text: std.Io.Writer.Allocating = .init(arena);
    const writer = &text.writer;
    writeModule(writer, script, declaration, imports.items, diagnostics) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.InvalidDeclaration => return error.InvalidDeclaration,
    };
    return text.written();
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.order(u8, left, right) == .lt;
}

/// Adds the module each Zig type in `field_type` starts with, once; `kosm` is always imported.
fn collectImports(arena: std.mem.Allocator, script: Script, field: Declaration.Field, field_type: Declaration.Type, modules: []const []const u8, imports: *std.ArrayList([]const u8), diagnostics: *kosm.Diagnostics) Error!void {
    switch (field_type) {
        .optional => |child| {
            if (child.* == .optional) return fail(diagnostics, script, field.line, "{s}: an optional of an optional; one optional is enough", .{field.name});
            return collectImports(arena, script, field, child.*, modules, imports, diagnostics);
        },
        .list => |child| return collectImports(arena, script, field, child.*, modules, imports, diagnostics),
        .zig => |name| {
            var segments = std.mem.splitScalar(u8, name, '.');
            const module = segments.first();
            while (segments.next()) |segment| {
                if (!isIdentifier(segment)) return fail(diagnostics, script, field.line, "{s}: '{s}' is no Zig type's name", .{ field.name, name });
            }
            if (!isIdentifier(module) or std.mem.findScalar(u8, name, '.') == null)
                return fail(diagnostics, script, field.line, "{s}: '{s}' is no Zig type's name; name it from its package, as kosm.Color or kosm_cursor.App", .{ field.name, name });
            if (std.mem.eql(u8, module, "kosm")) return;
            const known = for (modules) |candidate| {
                if (std.mem.eql(u8, candidate, module)) break true;
            } else false;
            if (!known) return fail(diagnostics, script, field.line, "{s}: there is no package or module '{s}' for {s}", .{ field.name, module, name });
            for (imports.items) |existing| {
                if (std.mem.eql(u8, existing, module)) return;
            }
            try imports.append(arena, module);
        },
        .boolean, .integer, .float, .text => {},
    }
}

fn isIdentifier(text: []const u8) bool {
    if (text.len == 0 or !(std.ascii.isAlphabetic(text[0]) or text[0] == '_')) return false;
    for (text) |character| {
        if (!std.ascii.isAlphanumeric(character) and character != '_') return false;
    }
    return true;
}

const WriteError = std.Io.Writer.Error || error{InvalidDeclaration};

fn writeModule(writer: *std.Io.Writer, script: Script, declaration: Declaration, imports: []const []const u8, diagnostics: *kosm.Diagnostics) WriteError!void {
    try writer.print("//! The app {s} declares, written by kosm from it: edit the script, never this file.\n\n", .{script.path});
    try writer.writeAll("const kosm = @import(\"kosm\");\n");
    for (imports) |module| try writer.print("const {f} = @import(\"{f}\");\n", .{ std.zig.fmtId(module), std.zig.fmtString(module) });
    try writer.writeAll("\n");
    if (declaration.doc) |doc| try writeDoc(writer, "", doc);
    try writer.writeAll("pub const App = struct {\n");
    for (declaration.fields) |field| {
        if (field.doc) |doc| try writeDoc(writer, "    ", doc);
        try writer.print("    {f}: ", .{std.zig.fmtId(field.name)});
        try writeType(writer, field.type);
        try writer.writeAll(" = ");
        try writeDefault(writer, script, field, diagnostics);
        try writer.writeAll(",\n");
    }
    if (declaration.fields.len != 0) try writer.writeAll("\n");
    try writer.print(
        \\    /// Where the app's script is; it runs the app's functions.
        \\    pub const script: kosm.Frontend.ScriptApp = .{{ .frontend = "{f}", .path = "{f}" }};
        \\
        \\    /// Runs the script's `apply(self, output)`.
        \\    pub fn apply(self: App, output: *kosm.Output) !void {{
        \\        return script.apply(App, self, output);
        \\    }}
        \\
    , .{ std.zig.fmtString(script.frontend), std.zig.fmtString(script.path) });
    if (declaration.gives("reload")) try writer.writeAll(
        \\
        \\    /// Runs the script's `reload(self, reloader)`.
        \\    pub fn reload(self: App, reloader: *kosm.Reloader) !void {
        \\        return script.reload(App, self, reloader);
        \\    }
        \\
    );
    try writeTypeChecks(writer, script, declaration);
    try writer.writeAll("};\n");
    if (declaration.gives("from")) try writer.writeAll(
        \\
        \\/// The app the script's `from(theme)` gives.
        \\pub fn from(theme: kosm.Theme) App {
        \\    return App.script.from(App, theme);
        \\}
        \\
    );
}

/// `doc` as `///` lines, each indented by `indent`.
fn writeDoc(writer: *std.Io.Writer, indent: []const u8, doc: []const u8) std.Io.Writer.Error!void {
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, doc, "\n"), '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimEnd(u8, line, " \t\r");
        if (trimmed.len == 0) try writer.print("{s}///\n", .{indent}) else try writer.print("{s}/// {s}\n", .{ indent, trimmed });
    }
}

fn writeType(writer: *std.Io.Writer, field_type: Declaration.Type) std.Io.Writer.Error!void {
    switch (field_type) {
        .boolean => try writer.writeAll("bool"),
        .integer => try writer.writeAll("i64"),
        .float => try writer.writeAll("f64"),
        .text => try writer.writeAll("[]const u8"),
        .optional => |child| {
            try writer.writeAll("?");
            try writeType(writer, child.*);
        },
        .list => |child| {
            try writer.writeAll("[]const ");
            try writeType(writer, child.*);
        },
        .zig => |name| try writer.writeAll(name),
    }
}

fn writeDefault(writer: *std.Io.Writer, script: Script, field: Declaration.Field, diagnostics: *kosm.Diagnostics) WriteError!void {
    const given = field.default orelse switch (field.type) {
        .optional => return writer.writeAll("null"),
        .list => return writer.writeAll("&.{}"),
        .zig => return writer.writeAll(".{}"),
        .boolean, .integer, .float, .text => return fail(diagnostics, script, field.line, "{s}: {s} needs a default, as kosm.{s}({s}); or make it kosm.optional(kosm.{s})", .{
            field.name, described(field.type), @tagName(field.type), exampleDefault(field.type), @tagName(field.type),
        }),
    };
    const scalar = switch (field.type) {
        .optional => |child| child.*,
        else => field.type,
    };
    switch (scalar) {
        .boolean => if (given.value == .boolean) return writer.print("{}", .{given.value.boolean}),
        .integer => if (given.value == .integer) return writer.print("{d}", .{given.value.integer}),
        .float => switch (given.value) {
            .integer => |integer| return writer.print("{d}", .{integer}),
            .float => |float| if (std.math.isFinite(float)) return writer.print("{d}", .{float}),
            else => {},
        },
        .text => if (given.value == .string) return writer.print("\"{f}\"", .{std.zig.fmtString(given.value.string)}),
        .optional, .list, .zig => return fail(diagnostics, script, field.line, "{s}: only a boolean, integer, float or text takes a default; this one starts as its type's own", .{field.name}),
    }
    return fail(diagnostics, script, field.line, "{s}: the default does not fit {s}", .{ field.name, described(scalar) });
}

/// A scalar type as messages name it: "an integer".
fn described(field_type: Declaration.Type) []const u8 {
    return switch (field_type) {
        .boolean => "a boolean",
        .integer => "an integer",
        .float => "a float",
        else => "text",
    };
}

fn exampleDefault(field_type: Declaration.Type) []const u8 {
    return switch (field_type) {
        .boolean => "false",
        .integer => "0",
        .float => "1.5",
        else => "\"text\"",
    };
}

/// One compile-time check per Zig type a field names, so a type that does not exist fails
/// naming the script's line instead of this file's.
fn writeTypeChecks(writer: *std.Io.Writer, script: Script, declaration: Declaration) std.Io.Writer.Error!void {
    var wrote_any = false;
    for (declaration.fields) |field| {
        const name = zigName(field.type) orelse continue;
        if (!wrote_any) try writer.writeAll("\n    comptime {\n");
        wrote_any = true;
        var end = std.mem.findScalar(u8, name, '.').?;
        while (end < name.len) {
            const next = std.mem.findScalarPos(u8, name, end + 1, '.') orelse name.len;
            try writer.print("        if (!@hasDecl({s}, \"{s}\")) @compileError(\"{f}:{d}: {f}: {f} has no {f}\");\n", .{
                name[0..end],                  name[end + 1 .. next],           std.zig.fmtString(script.path),           field.line,
                std.zig.fmtString(field.name), std.zig.fmtString(name[0..end]), std.zig.fmtString(name[end + 1 .. next]),
            });
            end = next;
        }
        try writer.print("        if (@TypeOf({s}) != type) @compileError(\"{f}:{d}: {f}: {f} is not a type\");\n", .{
            name, std.zig.fmtString(script.path), field.line, std.zig.fmtString(field.name), std.zig.fmtString(name),
        });
    }
    if (wrote_any) try writer.writeAll("    }\n");
}

/// The Zig type `field_type` names, through optionals and lists, or null.
fn zigName(field_type: Declaration.Type) ?[]const u8 {
    return switch (field_type) {
        .optional, .list => |child| zigName(child.*),
        .zig => |name| name,
        else => null,
    };
}

fn fail(diagnostics: *kosm.Diagnostics, script: Script, line: usize, comptime format: []const u8, arguments: anytype) error{InvalidDeclaration} {
    var buffer: [512]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, format, arguments) catch buffer[0..];
    if (line == 0) diagnostics.set("", "", "{s}: {s}", .{ script.path, message }) else diagnostics.set("", "", "{s}:{d}: {s}", .{ script.path, line, message });
    return error.InvalidDeclaration;
}

/// Writes the module of each script app, adapter and frontend the process arguments name, for the build of a config:
/// `<output folder> <module>,<module>... [<name>=<path in the config>=<absolute path>]...`. Each
/// is `<output folder>/<name>.zig`, rewritten only when its contents change; stdout lists them,
/// so the build caches the run. Returns the exit status, 1 after printing what went wrong.
pub fn run(init: std.process.Init, comptime sources: []const Target.AdapterSource) !u8 {
    const arena = init.arena.allocator();
    var stderr_buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    var diagnostics: kosm.Diagnostics = .{};
    writeAll(init, arena, comptime discovery.frontends(sources), &stdout.interface, &diagnostics) catch |err| switch (err) {
        error.InvalidDeclaration => {
            try diagnostics.write(&stderr.interface);
            try stderr.interface.flush();
            return 1;
        },
        else => |other| return other,
    };
    try stdout.interface.flush();
    return 0;
}

fn writeAll(init: std.process.Init, arena: std.mem.Allocator, frontends: []const discovery.DeclaredFrontend, stdout: *std.Io.Writer, diagnostics: *kosm.Diagnostics) !void {
    const arguments = try init.minimal.args.toSlice(arena);
    if (arguments.len < 3) {
        diagnostics.set("", "", "the generator of app modules needs an output folder and the config's modules", .{});
        return error.InvalidDeclaration;
    }
    const output_folder = arguments[1];
    var modules: std.ArrayList([]const u8) = .empty;
    var names = std.mem.splitScalar(u8, arguments[2], ',');
    while (names.next()) |name| if (name.len != 0) try modules.append(arena, name);
    std.Io.Dir.cwd().createDirPath(init.io, output_folder) catch |err| {
        diagnostics.set("", "", "cannot create {s}: {s}", .{ output_folder, @errorName(err) });
        return error.InvalidDeclaration;
    };
    for (arguments[3..]) |argument| {
        const first = std.mem.findScalar(u8, argument, '=') orelse return badArgument(diagnostics, argument);
        const second = std.mem.findScalarPos(u8, argument, first + 1, '=') orelse return badArgument(diagnostics, argument);
        const name = argument[0..first];
        const path = argument[first + 1 .. second];
        const text = std.Io.Dir.cwd().readFileAlloc(init.io, argument[second + 1 ..], arena, .limited(max_script_size)) catch |err| {
            diagnostics.set("", "", "cannot read {s}: {s}", .{ path, @errorName(err) });
            return error.InvalidDeclaration;
        };
        const module = try generate(arena, frontends, name, path, text, modules.items, diagnostics);
        const target = try std.Io.Dir.path.join(arena, &.{ output_folder, try arena.print("{s}.zig", .{name}) });
        try writeIfChanged(init.io, arena, target, module, diagnostics);
        try stdout.print("{s}\n", .{path});
    }
}

/// Scripts are small; this only guards against reading something huge.
const max_script_size = 16 * 1024 * 1024;

fn badArgument(diagnostics: *kosm.Diagnostics, argument: []const u8) error{InvalidDeclaration} {
    diagnostics.set("", "", "expected <name>=<path in the config>=<absolute path>, got '{s}'", .{argument});
    return error.InvalidDeclaration;
}

/// The module of script `path`, read by the frontend claiming its extension.
pub fn generate(arena: std.mem.Allocator, frontends: []const discovery.DeclaredFrontend, name: []const u8, path: []const u8, text: []const u8, modules: []const []const u8, diagnostics: *kosm.Diagnostics) Error![]const u8 {
    const extension = std.Io.Dir.path.extension(path);
    const found = for (frontends) |candidate| {
        if (candidate.frontend.claims(extension)) break candidate.frontend;
    } else {
        diagnostics.set("", "", "{s}: no frontend claims '{s}' files; an app or adapter is Zig, or a script a frontend of the config reads", .{ path, extension });
        return error.InvalidDeclaration;
    };
    const script: Script = .{ .name = name, .path = path, .frontend = found.name };
    var context: kosm.Frontend.Context = .{ .arena = arena, .path = path };
    const declared = try declaredBy(found, &context, path, text, diagnostics);
    if (declared == .adapter) {
        const declare = found.declare_adapter orelse {
            diagnostics.set("", "", "{s}: the {s} frontend writes no adapters", .{ path, found.name });
            return error.InvalidDeclaration;
        };
        const declaration = declare(&context, text) catch |err| return declareFailed(err, context, path, diagnostics);
        return @import("adapter_modules.zig").source(arena, script, declaration, found.counts_from, diagnostics);
    }
    if (declared == .frontend) {
        const declare = found.declare_frontend orelse {
            diagnostics.set("", "", "{s}: the {s} frontend writes no frontends", .{ path, found.name });
            return error.InvalidDeclaration;
        };
        const declaration = declare(&context, text) catch |err| return declareFailed(err, context, path, diagnostics);
        return @import("frontend_modules.zig").source(arena, script, declaration, diagnostics);
    }
    const declare = found.declare orelse {
        diagnostics.set("", "", "{s}: the {s} frontend writes no apps", .{ path, found.name });
        return error.InvalidDeclaration;
    };
    const declaration = declare(&context, text) catch |err| return declareFailed(err, context, path, diagnostics);
    return source(arena, script, declaration, modules, diagnostics);
}

/// What script `path` gives: in the config, what its folder holds; a package's root script
/// says it itself, through its frontend.
fn declaredBy(frontend: kosm.Frontend, context: *kosm.Frontend.Context, path: []const u8, text: []const u8, diagnostics: *kosm.Diagnostics) Error!kosm.Frontend.Declared {
    if (std.mem.startsWith(u8, path, adapters_folder)) return .adapter;
    if (std.mem.startsWith(u8, path, frontends_folder)) return .frontend;
    if (std.mem.startsWith(u8, path, apps_folder)) return .app;
    const declares = frontend.declares orelse {
        diagnostics.set("", "", "{s}: the {s} frontend cannot tell what a package's root script gives, so it cannot be one", .{ path, frontend.name });
        return error.InvalidDeclaration;
    };
    return declares(context, text) catch |err| declareFailed(err, context.*, path, diagnostics);
}

/// The config's folder of adapters, whose scripts declare adapters rather than apps.
const adapters_folder = "adapters/";
/// The config's folder of frontends, whose scripts declare frontends.
const frontends_folder = "frontends/";
/// The config's folder of apps.
const apps_folder = "apps/";

fn declareFailed(err: kosm.Frontend.Error, context: kosm.Frontend.Context, path: []const u8, diagnostics: *kosm.Diagnostics) Error {
    switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidScript => {
            const message = context.message orelse "it cannot be read, and the frontend did not say why";
            if (std.mem.startsWith(u8, message, path)) diagnostics.set("", "", "{s}", .{message}) else diagnostics.set("", "", "{s}: {s}", .{ path, message });
            return error.InvalidDeclaration;
        },
    }
}

/// Writes `contents` to `path` unless it holds them already, so an unchanged module keeps its
/// time and compiles nothing.
fn writeIfChanged(io: std.Io, arena: std.mem.Allocator, path: []const u8, contents: []const u8, diagnostics: *kosm.Diagnostics) error{InvalidDeclaration}!void {
    if (std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_script_size))) |existing| {
        if (std.mem.eql(u8, existing, contents)) return;
    } else |_| {}
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = contents }) catch |err| {
        diagnostics.set("", "", "cannot write {s}: {s}", .{ path, @errorName(err) });
        return error.InvalidDeclaration;
    };
}

const testing = std.testing;

const test_script: Script = .{ .name = "cava", .path = "apps/cava/root.lua", .frontend = "lua" };

test "a declaration becomes an app with typed, documented fields and functions running the script" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const text_type: Declaration.Type = .text;
    const color_type: Declaration.Type = .{ .zig = "kosm.Color" };
    const declaration: Declaration = .{
        .doc = "Cava, the audio visualizer.",
        .functions = &.{ "from", "apply", "reload" },
        .fields = &.{
            .{ .name = "bars", .doc = "How many bars; 0 fills the terminal.", .type = .integer, .default = .{ .value = .{ .integer = 0 } }, .line = 3 },
            .{ .name = "sensitivity", .type = .float, .default = .{ .value = .{ .integer = 100 } }, .line = 4 },
            .{ .name = "method", .doc = "The output method.\nncurses by default.", .type = .{ .optional = &text_type }, .line = 6 },
            .{ .name = "gradient", .type = .{ .list = &color_type }, .line = 7 },
            .{ .name = "cursor", .type = .{ .zig = "kosm_cursor.App" }, .line = 8 },
            .{ .name = "type", .type = .boolean, .default = .{ .value = .{ .boolean = true } }, .line = 9 },
            .{ .name = "title", .type = .text, .default = .{ .value = .{ .string = "say \"hi\"" } }, .line = 10 },
        },
    };
    var diagnostics: kosm.Diagnostics = .{};
    const written = try source(arena.allocator(), test_script, declaration, &.{ "kosm", "kosm_cursor" }, &diagnostics);
    try testing.expectEqualStrings(
        \\//! The app apps/cava/root.lua declares, written by kosm from it: edit the script, never this file.
        \\
        \\const kosm = @import("kosm");
        \\const kosm_cursor = @import("kosm_cursor");
        \\
        \\/// Cava, the audio visualizer.
        \\pub const App = struct {
        \\    /// How many bars; 0 fills the terminal.
        \\    bars: i64 = 0,
        \\    sensitivity: f64 = 100,
        \\    /// The output method.
        \\    /// ncurses by default.
        \\    method: ?[]const u8 = null,
        \\    gradient: []const kosm.Color = &.{},
        \\    cursor: kosm_cursor.App = .{},
        \\    @"type": bool = true,
        \\    title: []const u8 = "say \"hi\"",
        \\
        \\    /// Where the app's script is; it runs the app's functions.
        \\    pub const script: kosm.Frontend.ScriptApp = .{ .frontend = "lua", .path = "apps/cava/root.lua" };
        \\
        \\    /// Runs the script's `apply(self, output)`.
        \\    pub fn apply(self: App, output: *kosm.Output) !void {
        \\        return script.apply(App, self, output);
        \\    }
        \\
        \\    /// Runs the script's `reload(self, reloader)`.
        \\    pub fn reload(self: App, reloader: *kosm.Reloader) !void {
        \\        return script.reload(App, self, reloader);
        \\    }
        \\
        \\    comptime {
        \\        if (!@hasDecl(kosm, "Color")) @compileError("apps/cava/root.lua:7: gradient: kosm has no Color");
        \\        if (@TypeOf(kosm.Color) != type) @compileError("apps/cava/root.lua:7: gradient: kosm.Color is not a type");
        \\        if (!@hasDecl(kosm_cursor, "App")) @compileError("apps/cava/root.lua:8: cursor: kosm_cursor has no App");
        \\        if (@TypeOf(kosm_cursor.App) != type) @compileError("apps/cava/root.lua:8: cursor: kosm_cursor.App is not a type");
        \\    }
        \\};
        \\
        \\/// The app the script's `from(theme)` gives.
        \\pub fn from(theme: kosm.Theme) App {
        \\    return App.script.from(App, theme);
        \\}
        \\
    , written);
}

test "a declaration kosm cannot write fails naming the script's line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const modules: []const []const u8 = &.{ "kosm", "kosm_cursor" };
    const Case = struct { field: Declaration.Field, message: []const u8 };
    const inner_optional: Declaration.Type = .{ .optional = &.text };
    const cases = [_]Case{
        .{ .field = .{ .name = "bars", .type = .integer, .line = 3 }, .message = "apps/cava/root.lua:3: bars: an integer needs a default, as kosm.integer(0); or make it kosm.optional(kosm.integer)" },
        .{ .field = .{ .name = "bars", .type = .integer, .default = .{ .value = .{ .float = 1.5 } }, .line = 3 }, .message = "apps/cava/root.lua:3: bars: the default does not fit an integer" },
        .{ .field = .{ .name = "apply", .type = .boolean, .line = 4 }, .message = "apps/cava/root.lua:4: a field may not be named 'apply', which the app's Zig module declares; rename it" },
        .{ .field = .{ .name = "cursor", .type = .{ .zig = "kosm_curser.App" }, .line = 5 }, .message = "apps/cava/root.lua:5: cursor: there is no package or module 'kosm_curser' for kosm_curser.App" },
        .{ .field = .{ .name = "cursor", .type = .{ .zig = "App" }, .line = 5 }, .message = "apps/cava/root.lua:5: cursor: 'App' is no Zig type's name; name it from its package, as kosm.Color or kosm_cursor.App" },
        .{ .field = .{ .name = "method", .type = .{ .optional = &inner_optional }, .line = 6 }, .message = "apps/cava/root.lua:6: method: an optional of an optional; one optional is enough" },
    };
    for (cases) |case| {
        var diagnostics: kosm.Diagnostics = .{};
        const declaration: Declaration = .{ .functions = &.{"apply"}, .fields = &.{case.field} };
        try testing.expectError(error.InvalidDeclaration, source(allocator, test_script, declaration, modules, &diagnostics));
        try testing.expectEqualStrings(case.message, diagnostics.message());
    }
    var diagnostics: kosm.Diagnostics = .{};
    try testing.expectError(error.InvalidDeclaration, source(allocator, test_script, .{ .functions = &.{"from"}, .fields = &.{} }, modules, &diagnostics));
    try testing.expectEqualStrings("apps/cava/root.lua: it gives no apply(self, output); an app's script returns a table with App, apply and usually from", diagnostics.message());
}

test "a module is written only when its contents change" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const folder = try tmp.dir.realPathFileAlloc(testing.io, ".", arena.allocator());
    const path = try std.Io.Dir.path.join(arena.allocator(), &.{ folder, "cava.zig" });
    var diagnostics: kosm.Diagnostics = .{};
    try writeIfChanged(testing.io, arena.allocator(), path, "one", &diagnostics);
    try tmp.dir.setTimestamps(testing.io, "cava.zig", .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 0 } } });
    try writeIfChanged(testing.io, arena.allocator(), path, "one", &diagnostics);
    try testing.expectEqual(0, (try tmp.dir.statFile(testing.io, "cava.zig", .{})).mtime.nanoseconds);
    try writeIfChanged(testing.io, arena.allocator(), path, "two", &diagnostics);
    try testing.expect((try tmp.dir.statFile(testing.io, "cava.zig", .{})).mtime.nanoseconds != 0);
    try testing.expectEqualStrings("two", try tmp.dir.readFileAlloc(testing.io, "cava.zig", arena.allocator(), .limited(16)));
}

test "a package's root script is what its frontend says; a config's is what its folder holds" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const Fake = struct {
        fn declaresAdapter(_: *kosm.Frontend.Context, _: []const u8) kosm.Frontend.Error!kosm.Frontend.Declared {
            return .adapter;
        }
        fn load(_: *kosm.Frontend.Context, _: []const u8) kosm.Frontend.Error!kosm.Frontend.Script {
            return error.InvalidScript;
        }
    };
    var with: kosm.Frontend = .{ .name = "fake", .extensions = &.{".fake"}, .load = Fake.load, .declares = Fake.declaresAdapter };
    var context: kosm.Frontend.Context = .{ .arena = arena.allocator(), .path = "" };
    var diagnostics: kosm.Diagnostics = .{};
    try testing.expectEqual(.adapter, try declaredBy(with, &context, "~~kosm_scratch/root.fake", "", &diagnostics));
    try testing.expectEqual(.app, try declaredBy(with, &context, "apps/cava/root.fake", "", &diagnostics));
    try testing.expectEqual(.frontend, try declaredBy(with, &context, "frontends/ini.fake", "", &diagnostics));
    with.declares = null;
    try testing.expectError(error.InvalidDeclaration, declaredBy(with, &context, "~~kosm_scratch/root.fake", "", &diagnostics));
    try testing.expectEqualStrings("~~kosm_scratch/root.fake: the fake frontend cannot tell what a package's root script gives, so it cannot be one", diagnostics.message());
}
