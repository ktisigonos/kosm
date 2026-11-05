//! What an app's `apply` writes through (D5, D22). Every call only plans; nothing reaches the
//! disk until kosm commits the whole plan (D36). Kosm sets the fields; apps only call methods.

const Output = @This();

const std = @import("std");
const Adapter = @import("Adapter.zig");
const ColorFormat = @import("ColorFormat.zig");
const Diagnostics = @import("Diagnostics.zig");
const Plan = @import("Plan.zig");
const template_writer = @import("template.zig");
const value = @import("value.zig");

/// Scratch memory for one apply; kosm frees it all afterwards (an arena).
allocator: std.mem.Allocator,
/// Absolute home directory that `~` expands to.
home: []const u8,
/// Every installed adapter.
adapters: []const Adapter,
plan: *Plan,
diagnostics: *Diagnostics,
/// The app being applied, as its path in the kosmos tree ("terminal.kitty").
app: []const u8,

/// Options for `generate`.
pub const GenerateOptions = @import("Output/GenerateOptions.zig");

/// Errors from writing; `diagnostics` holds the message.
pub const Error = error{
    InvalidPath,
    UnknownLanguage,
    AmbiguousLanguage,
    MissingCapability,
    InvalidColorFormat,
    UnsupportedValue,
    MissingValue,
    FileWrittenTwice,
    ReadFailed,
    OutOfMemory,
};

/// Writes a whole file from `values`, a plain struct the adapter serializes (D64).
pub fn generate(output: *Output, options: GenerateOptions, values: anytype) Error!void {
    const path = try output.resolvePath(options.file);
    const adapter = try output.findAdapter(options.file, options.lang);
    const serialize = adapter.serialize orelse
        return output.fail(error.MissingCapability, options.file, "adapter '{s}' cannot write whole files (it has no serialize)", .{adapter.name});
    const color_format = try output.checkColorFormat(options.file, options.color_format orelse adapter.color_format orelse .hex);
    const root = value.from(output.allocator, values) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.IntegerTooLarge => return output.fail(error.UnsupportedValue, options.file, "an integer is too large for a file value", .{}),
        error.NullInList => return output.fail(error.UnsupportedValue, options.file, "a list contains null", .{}),
    };

    var content: std.Io.Writer.Allocating = .init(output.allocator);
    defer content.deinit();
    var context: Adapter.Context = .{ .color_format = color_format };
    serialize(&content.writer, root, &context) catch |err| switch (err) {
        // An allocating writer fails only when it runs out of memory.
        error.WriteFailed => return error.OutOfMemory,
        error.UnsupportedValue => return output.fail(error.UnsupportedValue, options.file, "adapter '{s}': {s}", .{ adapter.name, context.message() }),
    };
    try output.addFile(options.file, path, content.written());
}

/// Writes a whole file from a template whose placeholders resolve against `app`'s fields (D60, D65).
/// `options` is `.{ .file = "~/...", .text = @embedFile("templates/x"), .color_format = ... }`;
/// `.text` must be comptime, so unknown paths are compile errors. `.color_format` is optional.
pub fn template(output: *Output, app: anytype, options: anytype) Error!void {
    const Options = @TypeOf(options);
    comptime checkTemplateOptions(Options);
    const path = try output.resolvePath(options.file);
    const color_format = try output.checkColorFormat(options.file, try output.templateColorFormat(options));

    var content: std.Io.Writer.Allocating = .init(output.allocator);
    defer content.deinit();
    var failure: template_writer.Failure = .{};
    const name = comptime if (isComptimeField(Options, "file")) options.file else "template";
    template_writer.render(&content.writer, name, options.text, app, color_format, &failure) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.MissingValue => return output.fail(error.MissingValue, options.file, "template line {d}: kosm.{s} is null", .{ failure.line, failure.path }),
        // checkColorFormat already wrote this format once.
        error.InvalidColorFormat => unreachable,
    };
    try output.addFile(options.file, path, content.written());
}

fn checkTemplateOptions(comptime Options: type) void {
    if (@typeInfo(Options) != .@"struct") @compileError("output.template: options must be a struct literal: .{ .file = ..., .text = ... }");
    for (std.meta.fieldNames(Options)) |field_name| {
        const known = std.mem.eql(u8, field_name, "file") or std.mem.eql(u8, field_name, "text") or std.mem.eql(u8, field_name, "color_format");
        if (!known) @compileError("output.template: unknown option '" ++ field_name ++ "'; options are file, text, color_format");
    }
    if (!@hasField(Options, "file")) @compileError("output.template: missing option .file");
    if (!@hasField(Options, "text")) @compileError("output.template: missing option .text");
    if (!isComptimeField(Options, "text")) @compileError("output.template: .text must be comptime, e.g. @embedFile(\"templates/theme.lua\")");
}

fn isComptimeField(comptime Options: type, comptime name: []const u8) bool {
    const info = @typeInfo(Options).@"struct";
    for (info.field_names, info.field_attrs) |field_name, attributes| {
        if (std.mem.eql(u8, field_name, name)) return attributes.@"comptime";
    }
    return false;
}

/// The template's own format, else that of the one adapter claiming its extension, else hex (D61).
fn templateColorFormat(output: *Output, options: anytype) Error!ColorFormat {
    if (@hasField(@TypeOf(options), "color_format")) {
        const ColorFormatField = @TypeOf(options.color_format);
        if (ColorFormatField == ColorFormat) return options.color_format;
        if (ColorFormatField == ?ColorFormat) {
            if (options.color_format) |format| return format;
        } else @compileError("output.template: .color_format must be a kosm.ColorFormat");
    }
    const extension = std.Io.Dir.path.extension(options.file);
    var found: ?Adapter = null;
    for (output.adapters) |adapter| {
        if (!adapter.claims(extension)) continue;
        if (found) |first| return output.fail(error.AmbiguousLanguage, options.file, "adapters '{s}' and '{s}' both handle '{s}' files; set .color_format", .{ first.name, adapter.name, extension });
        found = adapter;
    }
    if (found) |adapter| return adapter.color_format orelse .hex;
    return .hex;
}

fn resolvePath(output: *Output, file: []const u8) Error![]const u8 {
    if (std.mem.startsWith(u8, file, "~/")) return std.Io.Dir.path.join(output.allocator, &.{ output.home, file[2..] });
    if (std.Io.Dir.path.isAbsolute(file)) return file;
    return output.fail(error.InvalidPath, file, "file paths start with ~/ or /", .{});
}

/// The adapter named `lang`, or the one claiming the file's extension (D26).
fn findAdapter(output: *Output, file: []const u8, lang: ?[]const u8) Error!Adapter {
    if (lang) |name| {
        for (output.adapters) |adapter| {
            if (std.mem.eql(u8, adapter.name, name)) return adapter;
        }
        return output.fail(error.UnknownLanguage, file, "no installed adapter is named '{s}'", .{name});
    }
    const extension = std.Io.Dir.path.extension(file);
    var found: ?Adapter = null;
    for (output.adapters) |adapter| {
        if (!adapter.claims(extension)) continue;
        if (found) |first| return output.fail(error.AmbiguousLanguage, file, "adapters '{s}' and '{s}' both handle '{s}' files; pass .lang", .{ first.name, adapter.name, extension });
        found = adapter;
    }
    return found orelse output.fail(error.UnknownLanguage, file, "no installed adapter handles '{s}' files; pass .lang", .{extension});
}

/// A hand-built format whose template does not match its components is caught here, once.
fn checkColorFormat(output: *Output, file: []const u8, format: ColorFormat) Error!ColorFormat {
    var discarding: std.Io.Writer.Discarding = .init(&.{});
    format.write(.{ .lightness = 0, .chroma = 0, .hue = 0 }, &discarding.writer) catch
        return output.fail(error.InvalidColorFormat, file, "color format \"{s}\" does not match its {d} components", .{ format.template, format.components.len });
    return format;
}

fn addFile(output: *Output, file: []const u8, path: []const u8, content: []const u8) Error!void {
    output.plan.add(path, file, output.app, content) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileWrittenTwice => return output.fail(error.FileWrittenTwice, file, "app '{s}' writes this file too; two apps cannot write the same bytes (D38)", .{output.plan.find(path).?.owner}),
        else => return output.fail(error.ReadFailed, file, "cannot read it: {s}", .{@errorName(err)}),
    };
}

fn fail(output: *Output, err: Error, file: []const u8, comptime format: []const u8, arguments: anytype) Error {
    output.diagnostics.set(output.app, file, format, arguments);
    return err;
}

const testing = std.testing;
const Color = @import("Color.zig");

/// `key = value` lines, a stand-in for a real adapter.
fn serializeLines(writer: *std.Io.Writer, root: value.Value, context: *Adapter.Context) Adapter.Error!void {
    for (root.table) |entry| {
        try writer.print("{s} = ", .{entry.key});
        switch (entry.value) {
            .string => |text| try writer.print("\"{s}\"", .{text}),
            .integer => |number| try writer.print("{d}", .{number}),
            .color => |color| try context.writeColor(writer, color),
            else => return context.unsupported("'{s}' must be a string, integer or color", .{entry.key}),
        }
        try writer.writeByte('\n');
    }
}

const lines_adapter: Adapter = .{ .name = "lines", .extensions = &.{".lines"}, .color_format = .hex8, .serialize = serializeLines };
const other_lines_adapter: Adapter = .{ .name = "other", .extensions = &.{".lines"} };

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    plan: Plan,
    diagnostics: Diagnostics = .{},
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,

    fn init(fixture: *Fixture) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    fn output(fixture: *Fixture, app: []const u8, adapters: []const Adapter) !Output {
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        return .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = adapters,
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .app = app,
        };
    }
};

test "generate serializes through the adapter claiming the extension, under ~" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("terminal", &.{lines_adapter});
    const red = try Color.parseHex("#bf616a");
    try output.generate(.{ .file = "~/kitty/kosm.lines" }, .{ .name = "frost", .size = 12, .accent = red });
    try output.generate(.{ .file = "~/hex.lines", .color_format = .hex }, .{ .accent = red });

    const file = fixture.plan.files.items[0];
    try testing.expect(std.mem.endsWith(u8, file.path, "/kitty/kosm.lines"));
    try testing.expectEqualStrings("~/kitty/kosm.lines", file.display_path);
    try testing.expectEqualStrings("terminal", file.owner);
    try testing.expectEqual(null, file.old);
    try testing.expectEqualStrings("name = \"frost\"\nsize = 12\naccent = #bf616aff\n", file.new);
    try testing.expectEqualStrings("accent = #bf616a\n", fixture.plan.files.items[1].new);
}

test "generate errors name the problem and the file" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("terminal", &.{ lines_adapter, other_lines_adapter });

    try testing.expectError(error.AmbiguousLanguage, output.generate(.{ .file = "~/a.lines" }, .{ .size = 1 }));
    try testing.expectEqualStrings("adapters 'lines' and 'other' both handle '.lines' files; pass .lang", fixture.diagnostics.message());
    try testing.expectEqualStrings("~/a.lines", fixture.diagnostics.file);
    try testing.expectEqualStrings("terminal", fixture.diagnostics.app);

    try testing.expectError(error.MissingCapability, output.generate(.{ .file = "~/a.lines", .lang = "other" }, .{ .size = 1 }));
    try testing.expectError(error.UnknownLanguage, output.generate(.{ .file = "~/a.toml" }, .{ .size = 1 }));
    try testing.expectError(error.InvalidPath, output.generate(.{ .file = "relative.lines", .lang = "lines" }, .{ .size = 1 }));

    try testing.expectError(error.UnsupportedValue, output.generate(.{ .file = "~/a.lines", .lang = "lines" }, .{ .blur = true }));
    try testing.expectEqualStrings("adapter 'lines': 'blur' must be a string, integer or color", fixture.diagnostics.message());

    const broken: ColorFormat = .{ .template = "{} {}", .components = &.{.hex} };
    try testing.expectError(error.InvalidColorFormat, output.generate(.{ .file = "~/a.lines", .lang = "lines", .color_format = broken }, .{ .size = 1 }));
    try testing.expectEqual(0, fixture.plan.files.items.len);
}

test "two apps writing one file is an error naming the first" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var first = try fixture.output("terminal", &.{lines_adapter});
    try first.generate(.{ .file = "~/shared.lines" }, .{ .size = 1 });
    var second = try fixture.output("browser", &.{lines_adapter});
    try testing.expectError(error.FileWrittenTwice, second.generate(.{ .file = "~/shared.lines" }, .{ .size = 2 }));
    try testing.expectEqualStrings("browser", fixture.diagnostics.app);
    try testing.expectEqualStrings("app 'terminal' writes this file too; two apps cannot write the same bytes (D38)", fixture.diagnostics.message());
}

test "generate reads the current contents so unchanged files are left alone" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "same.lines", .data = "size = 1\n" });
    var output = try fixture.output("terminal", &.{lines_adapter});
    try output.generate(.{ .file = "~/same.lines" }, .{ .size = 1 });
    try testing.expectEqualStrings("size = 1\n", fixture.plan.files.items[0].old.?);
    try testing.expect(!fixture.plan.hasChanges());
}

const TemplateApp = struct {
    rounding: u8 = 10,
    accent: Color,
    border_inactive: ?Color = null,
    color_format: ColorFormat = .hex8,
};

test "template renders the app's fields with the file's color format" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("editor", &.{lines_adapter});
    const app: TemplateApp = .{ .accent = try Color.parseHex("#5e81ac") };

    try output.template(app, .{ .file = "~/theme.lua", .text = "accent = 'kosm.accent' -- {kosm.rounding}px\n", .color_format = app.color_format });
    try testing.expectEqualStrings("accent = '#5e81acff' -- 10px\n", fixture.plan.files.items[0].new);

    try output.template(app, .{ .file = "~/theme.txt", .text = "kosm.accent" });
    try testing.expectEqualStrings("#5e81ac", fixture.plan.files.items[1].new);

    try output.template(app, .{ .file = "~/theme.lines", .text = "kosm.accent" });
    try testing.expectEqualStrings("#5e81acff", fixture.plan.files.items[2].new);
}

test "template reports a null placeholder with its line" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("editor", &.{});
    const app: TemplateApp = .{ .accent = try Color.parseHex("#5e81ac") };
    try testing.expectError(error.MissingValue, output.template(app, .{ .file = "~/theme.lua", .text = "a\nkosm.border_inactive\n" }));
    try testing.expectEqualStrings("template line 2: kosm.border_inactive is null", fixture.diagnostics.message());
}
