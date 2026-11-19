//! The Zig modules of adapters written through a frontend: kosm reads what each script declares
//! while it builds the config, and writes a module giving `adapter`, a `kosm.Adapter` whose
//! capabilities run the script's own functions. Like an app's, a module is written only when its
//! contents change, so editing a function compiles nothing.

const std = @import("std");
const kosm = @import("kosm");
const app_modules = @import("app_modules.zig");

const AdapterDeclaration = kosm.Frontend.AdapterDeclaration;
const Loose = kosm.Loose;

/// The capabilities a script may give as functions, by `kosm.Adapter`'s names.
const capabilities = [_][]const u8{ "format", "parser", "serialize", "insert" };

pub const Error = app_modules.Error;

/// The source of the module for `script`, which declares `declaration`, read by a frontend
/// counting positions from `counts_from`. Fails with `error.InvalidDeclaration` after setting
/// `diagnostics`, naming the script.
pub fn source(arena: std.mem.Allocator, script: app_modules.Script, declaration: AdapterDeclaration, counts_from: u1, diagnostics: *kosm.Diagnostics) Error![]const u8 {
    try check(script, declaration, diagnostics);
    var text: std.Io.Writer.Allocating = .init(arena);
    writeModule(&text.writer, script, declaration, counts_from, diagnostics) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.InvalidDeclaration => return error.InvalidDeclaration,
    };
    return text.written();
}

fn check(script: app_modules.Script, declaration: AdapterDeclaration, diagnostics: *kosm.Diagnostics) error{InvalidDeclaration}!void {
    if (declaration.name.len == 0) return fail(diagnostics, script.path, "it gives no name; an adapter's name is the language apps pass as .lang", .{});
    for (declaration.extensions) |extension| {
        if (extension.len < 2 or extension[0] != '.') return fail(diagnostics, script.path, "extension '{s}' does not start with a dot, as \".keys\"", .{extension});
    }
    if (declaration.comment) |comment| switch (comment) {
        .line => |start| if (start.len == 0) return fail(diagnostics, script.path, "an empty line comment; give what starts one, as \"#\"", .{}),
        .block => |block| if (block.open.len == 0 or block.close.len == 0) return fail(diagnostics, script.path, "a block comment needs both its open and close", .{}),
    };
    for (declaration.functions) |function| {
        for (capabilities) |capability| {
            if (std.mem.eql(u8, function, capability)) break;
        } else return fail(diagnostics, script.path, "'{s}' is no adapter capability; an adapter gives format, parser, serialize or insert", .{function});
    }
    if (declaration.functions.len == 0) return fail(diagnostics, script.path, "it gives none of format, parser, serialize and insert, so no app can write through it", .{});
}

const WriteError = std.Io.Writer.Error || error{InvalidDeclaration};

fn writeModule(writer: *std.Io.Writer, script: app_modules.Script, declaration: AdapterDeclaration, counts_from: u1, diagnostics: *kosm.Diagnostics) WriteError!void {
    try writer.print(
        \\//! The adapter {s} declares, written by kosm from it: edit the script, never this file.
        \\
        \\const kosm = @import("kosm");
        \\
        \\/// Where the adapter's script is; it runs the adapter's capabilities.
        \\pub const script: kosm.Frontend.ScriptAdapter = .{{ .frontend = "{f}", .path = "{f}", .counts_from = {d} }};
        \\
        \\const capabilities = kosm.Frontend.ScriptAdapter.Capabilities(script);
        \\
        \\/// The {f} adapter, written in {f}.
        \\pub const adapter: kosm.Adapter = .{{
        \\    .name = "{f}",
        \\    .extensions = &.{{
    , .{
        script.path,
        std.zig.fmtString(script.frontend),
        std.zig.fmtString(script.path),
        counts_from,
        std.zig.fmtString(declaration.name),
        std.zig.fmtString(script.frontend),
        std.zig.fmtString(declaration.name),
    });
    for (declaration.extensions, 0..) |extension, index| try writer.print("{s}\"{f}\"", .{ if (index == 0) " " else ", ", std.zig.fmtString(extension) });
    try writer.writeAll(if (declaration.extensions.len == 0) "},\n" else " },\n");
    if (declaration.default_format) |format| {
        try writer.writeAll("    .default_format = ");
        try writeFormat(writer, script, format, diagnostics);
        try writer.writeAll(",\n");
    }
    if (declaration.comment) |comment| switch (comment) {
        .line => |start| try writer.print("    .comment = .{{ .line = \"{f}\" }},\n", .{std.zig.fmtString(start)}),
        .block => |block| try writer.print("    .comment = .{{ .block = .{{ .open = \"{f}\", .close = \"{f}\" }} }},\n", .{ std.zig.fmtString(block.open), std.zig.fmtString(block.close) }),
    };
    for (capabilities) |capability| {
        if (declaration.gives(capability)) try writer.print("    .{s} = capabilities.{s},\n", .{ capability, capability });
    }
    try writer.writeAll("};\n");
}

/// `format`, a table of `kosm.Format`'s fields, as a Zig literal.
fn writeFormat(writer: *std.Io.Writer, script: app_modules.Script, format: Loose, diagnostics: *kosm.Diagnostics) WriteError!void {
    const where = format.origin orelse script.path;
    const entries = switch (format.value) {
        .table => |entries| entries,
        .list => |items| if (items.len == 0) &.{} else return fail(diagnostics, where, "default_format is a list; it is a table of color, boolean and float_precision", .{}),
        else => return fail(diagnostics, where, "default_format is no table; it is a table of color, boolean and float_precision", .{}),
    };
    try writer.writeAll(".{");
    for (entries, 0..) |entry, index| {
        const at = entry.value.origin orelse where;
        try writer.writeAll(if (index == 0) " ." else ", .");
        if (std.mem.eql(u8, entry.key, "color")) {
            try writer.writeAll("color = ");
            try writeColorFormat(writer, at, entry.value, diagnostics);
        } else if (std.mem.eql(u8, entry.key, "boolean")) {
            const name = textOf(entry.value) orelse return fail(diagnostics, at, "default_format.boolean is no name; it is one of {s}", .{comptime tagList(kosm.Format.Boolean)});
            if (std.meta.stringToEnum(kosm.Format.Boolean, name) == null) return fail(diagnostics, at, "default_format.boolean: '{s}' is none of {s}", .{ name, comptime tagList(kosm.Format.Boolean) });
            try writer.print("boolean = .{s}", .{name});
        } else if (std.mem.eql(u8, entry.key, "float_precision")) {
            const precision = if (entry.value.value == .integer) entry.value.value.integer else -1;
            if (precision < 0 or precision > kosm.Format.max_float_precision) return fail(diagnostics, at, "default_format.float_precision is a whole number of decimals, 0..{d}", .{kosm.Format.max_float_precision});
            try writer.print("float_precision = {d}", .{precision});
        } else return fail(diagnostics, at, "default_format sets '{s}'; it holds color, boolean and float_precision", .{entry.key});
    }
    try writer.writeAll(if (entries.len == 0) "}" else " }");
}

/// A color format, by the name of one of `kosm.ColorFormat`'s (`hex8`) or as a table of its
/// `template` and `components`.
fn writeColorFormat(writer: *std.Io.Writer, at: []const u8, given: Loose, diagnostics: *kosm.Diagnostics) WriteError!void {
    if (textOf(given)) |name| {
        inline for (comptime namedColorFormats()) |known| {
            if (std.mem.eql(u8, name, known)) return writer.print(".{s}", .{known});
        }
        return fail(diagnostics, at, "default_format.color: '{s}' names no color format; name one of {s}, or give {{ template, components }}", .{ name, comptime namedList() });
    }
    const entries = if (given.value == .table) given.value.table else return fail(diagnostics, at, "default_format.color is a format's name or a table of template and components", .{});
    var template: ?[]const u8 = null;
    var components: []const Loose = &.{};
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.key, "template")) {
            template = textOf(entry.value) orelse return fail(diagnostics, at, "default_format.color.template is no text", .{});
        } else if (std.mem.eql(u8, entry.key, "components")) {
            components = if (entry.value.value == .list) entry.value.value.list else return fail(diagnostics, at, "default_format.color.components is a list of component names", .{});
        } else return fail(diagnostics, at, "default_format.color sets '{s}'; it holds template and components", .{entry.key});
    }
    const text = template orelse return fail(diagnostics, at, "default_format.color has no template", .{});
    const placeholders = countPlaceholders(text);
    if (placeholders != components.len) return fail(diagnostics, at, "default_format.color: the template has {d} {{}} but {d} components are given", .{ placeholders, components.len });
    try writer.print(".init(\"{f}\", &.{{", .{std.zig.fmtString(text)});
    for (components, 0..) |component, index| {
        const name = textOf(component) orelse return fail(diagnostics, at, "default_format.color.components holds something other than a name", .{});
        if (std.meta.stringToEnum(kosm.Color.Component, name) == null) return fail(diagnostics, at, "default_format.color.components: '{s}' is no color component", .{name});
        try writer.print("{s}.{s}", .{ if (index == 0) " " else ", ", name });
    }
    try writer.writeAll(if (components.len == 0) "})" else " })");
}

/// The `{}` in `template`, leaving out the literal braces `{{` and `}}`.
fn countPlaceholders(template: []const u8) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (index < template.len) : (index += 1) {
        if (template[index] != '{' or index + 1 >= template.len) continue;
        if (template[index + 1] == '{') {
            index += 1;
        } else if (template[index + 1] == '}') {
            count += 1;
            index += 1;
        }
    }
    return count;
}

fn textOf(given: Loose) ?[]const u8 {
    return switch (given.value) {
        .string, .text => |text| text,
        else => null,
    };
}

/// The names of `kosm.ColorFormat`'s ready formats.
fn namedColorFormats() []const []const u8 {
    comptime var found: []const []const u8 = &.{};
    inline for (@typeInfo(kosm.ColorFormat).@"struct".decl_names) |name| {
        if (@TypeOf(@field(kosm.ColorFormat, name)) == kosm.ColorFormat) found = found ++ .{name};
    }
    return found;
}

fn namedList() []const u8 {
    comptime var text: []const u8 = "";
    inline for (comptime namedColorFormats(), 0..) |name, index| text = text ++ (if (index == 0) "" else ", ") ++ name;
    return text;
}

fn tagList(comptime T: type) []const u8 {
    comptime var text: []const u8 = "";
    inline for (@typeInfo(T).@"enum".field_names, 0..) |name, index| text = text ++ (if (index == 0) "" else ", ") ++ name;
    return text;
}

/// Records why `where` (a script, or a script's line) cannot become a module.
fn fail(diagnostics: *kosm.Diagnostics, where: []const u8, comptime format: []const u8, arguments: anytype) error{InvalidDeclaration} {
    var buffer: [512]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, format, arguments) catch buffer[0..];
    diagnostics.set("", "", "{s}: {s}", .{ where, message });
    return error.InvalidDeclaration;
}

const testing = std.testing;

const test_script: app_modules.Script = .{ .name = "keys", .path = "adapters/keys.lua", .frontend = "lua" };

test "a declaration becomes an adapter with its data and the capabilities the script gives" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const format: Loose = .{ .value = .{ .table = &.{
        .{ .key = "color", .value = .{ .value = .{ .table = &.{
            .{ .key = "template", .value = .{ .value = .{ .string = "rgb({}, {})" } } },
            .{ .key = "components", .value = .{ .value = .{ .list = &.{ .{ .value = .{ .string = "red_255" } }, .{ .value = .{ .string = "green_255" } } } } } },
        } } } },
        .{ .key = "boolean", .value = .{ .value = .{ .string = "yes_no" } } },
        .{ .key = "float_precision", .value = .{ .value = .{ .integer = 2 } } },
    } } };
    const declaration: AdapterDeclaration = .{
        .name = "keys",
        .extensions = &.{ ".keys", ".kv" },
        .comment = .{ .block = .{ .open = "/*", .close = "*/" } },
        .default_format = format,
        .functions = &.{ "parser", "format" },
    };
    var diagnostics: kosm.Diagnostics = .{};
    try testing.expectEqualStrings(
        \\//! The adapter adapters/keys.lua declares, written by kosm from it: edit the script, never this file.
        \\
        \\const kosm = @import("kosm");
        \\
        \\/// Where the adapter's script is; it runs the adapter's capabilities.
        \\pub const script: kosm.Frontend.ScriptAdapter = .{ .frontend = "lua", .path = "adapters/keys.lua", .counts_from = 1 };
        \\
        \\const capabilities = kosm.Frontend.ScriptAdapter.Capabilities(script);
        \\
        \\/// The keys adapter, written in lua.
        \\pub const adapter: kosm.Adapter = .{
        \\    .name = "keys",
        \\    .extensions = &.{ ".keys", ".kv" },
        \\    .default_format = .{ .color = .init("rgb({}, {})", &.{ .red_255, .green_255 }), .boolean = .yes_no, .float_precision = 2 },
        \\    .comment = .{ .block = .{ .open = "/*", .close = "*/" } },
        \\    .format = capabilities.format,
        \\    .parser = capabilities.parser,
        \\};
        \\
    , try source(arena.allocator(), test_script, declaration, 1, &diagnostics));
    const named: AdapterDeclaration = .{ .name = "keys", .comment = .{ .line = "#" }, .default_format = .{ .value = .{ .table = &.{.{ .key = "color", .value = .{ .value = .{ .string = "hex8" } } }} } }, .functions = &.{"serialize"} };
    const written = try source(arena.allocator(), test_script, named, 0, &diagnostics);
    try testing.expect(std.mem.find(u8, written, "    .extensions = &.{},\n    .default_format = .{ .color = .hex8 },\n    .comment = .{ .line = \"#\" },\n    .serialize = capabilities.serialize,\n") != null);
}

test "a declaration kosm cannot write fails naming the script" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const Case = struct { declaration: AdapterDeclaration, message: []const u8 };
    const cases = [_]Case{
        .{ .declaration = .{ .name = "", .functions = &.{"format"} }, .message = "adapters/keys.lua: it gives no name; an adapter's name is the language apps pass as .lang" },
        .{ .declaration = .{ .name = "keys", .extensions = &.{"keys"}, .functions = &.{"format"} }, .message = "adapters/keys.lua: extension 'keys' does not start with a dot, as \".keys\"" },
        .{ .declaration = .{ .name = "keys" }, .message = "adapters/keys.lua: it gives none of format, parser, serialize and insert, so no app can write through it" },
        .{ .declaration = .{ .name = "keys", .functions = &.{"parse"} }, .message = "adapters/keys.lua: 'parse' is no adapter capability; an adapter gives format, parser, serialize or insert" },
        .{
            .declaration = .{ .name = "keys", .functions = &.{"format"}, .default_format = .{ .value = .{ .table = &.{.{ .key = "boolean", .value = .{ .value = .{ .string = "maybe" }, .origin = "adapters/keys.lua:3" } }} } } },
            .message = "adapters/keys.lua:3: default_format.boolean: 'maybe' is none of true_false, yes_no, one_zero, on_off",
        },
        .{
            .declaration = .{ .name = "keys", .functions = &.{"format"}, .default_format = .{ .value = .{ .table = &.{.{ .key = "color", .value = .{ .value = .{ .string = "rgb" } } }} } } },
            .message = "adapters/keys.lua: default_format.color: 'rgb' names no color format; name one of hex, hex8, hex_upper, hex8_upper, hex8_argb, or give { template, components }",
        },
        .{
            .declaration = .{ .name = "keys", .functions = &.{"format"}, .default_format = .{ .value = .{ .table = &.{.{ .key = "color", .value = .{ .value = .{ .table = &.{.{ .key = "template", .value = .{ .value = .{ .string = "{} {{}}" } } }} } } }} } } },
            .message = "adapters/keys.lua: default_format.color: the template has 1 {} but 0 components are given",
        },
    };
    for (cases) |case| {
        var diagnostics: kosm.Diagnostics = .{};
        try testing.expectError(error.InvalidDeclaration, source(arena.allocator(), test_script, case.declaration, 1, &diagnostics));
        try testing.expectEqualStrings(case.message, diagnostics.message());
    }
}
