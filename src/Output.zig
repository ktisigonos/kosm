//! What an app's `apply` writes through (D5, D22). Every call only plans; nothing reaches the
//! disk until kosm commits the whole plan (D36). Kosm sets the fields; apps only call methods.

const Output = @This();

const std = @import("std");
const Adapter = @import("Adapter.zig");
const Format = @import("Format.zig");
const Diagnostics = @import("Diagnostics.zig");
const Plan = @import("Plan.zig");
const template_writer = @import("template.zig");
const block_writer = @import("block.zig");
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
/// Options for `block`.
pub const BlockOptions = @import("Output/BlockOptions.zig");

/// Errors from writing; `diagnostics` holds the message.
pub const Error = error{
    InvalidPath,
    UnknownLanguage,
    AmbiguousLanguage,
    MissingCapability,
    InvalidFormat,
    UnsupportedValue,
    MissingValue,
    InvalidBlock,
    EditsOverlap,
    ReadFailed,
    OutOfMemory,
};

/// Writes a whole file from `values`, a plain struct the adapter serializes (D64).
pub fn generate(output: *Output, options: GenerateOptions, values: anytype) Error!void {
    const path = try output.resolvePath(options.file);
    const adapter = try output.findAdapter(options.file, options.lang);
    if (adapter.serialize == null)
        return output.fail(error.MissingCapability, options.file, "adapter '{s}' cannot write whole files (it has no serialize)", .{adapter.name});
    const content = try output.serialize(options.file, adapter, options.format, values);
    try output.addFile(options.file, path, content);
}

/// Writes `values`, serialized like `generate`'s (D64), as block `options.id` of a file the user
/// otherwise writes by hand (D71, D72). The rest of the file is kept byte for byte; a missing
/// block is appended, a missing file created. Needs an adapter with `comment` and `serialize`.
pub fn block(output: *Output, options: BlockOptions, values: anytype) Error!void {
    const path = try output.resolvePath(options.file);
    const adapter = try output.findAdapter(options.file, options.lang);
    const comment = adapter.comment orelse
        return output.fail(error.MissingCapability, options.file, "adapter '{s}' cannot write blocks (it has no comment syntax)", .{adapter.name});
    if (adapter.serialize == null)
        return output.fail(error.MissingCapability, options.file, "adapter '{s}' cannot write data blocks (it has no serialize)", .{adapter.name});
    if (!block_writer.isValidId(options.id))
        return output.fail(error.InvalidBlock, options.file, "block id '{s}' may only hold letters, digits, _, - and .", .{options.id});

    const content = try output.serialize(options.file, adapter, options.format, values);
    var failure: block_writer.Failure = .{};
    block_writer.checkContent(content, comment, &failure) catch
        return output.fail(error.InvalidBlock, options.file, "block '{s}', line {d} of its content: {s}", .{ options.id, failure.line, failure.problem.describe() });
    const file = output.plan.load(path, options.file) catch |err| return output.failRead(options.file, err);
    const current = file.current();
    const found = block_writer.find(output.allocator, current, comment, options.id, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidBlock => return output.fail(error.InvalidBlock, options.file, "line {d}: {s}", .{ failure.line, failure.problem.describe() }),
    };
    if (found) |contents| {
        const new_content = if (content.len != 0 and content[content.len - 1] != '\n')
            try std.mem.concat(output.allocator, u8, &.{ content, "\n" })
        else
            content;
        return output.addEdit(file, .{ .target = .{ .block = options.id }, .start = contents.start, .end = contents.end, .content = new_content, .owner = output.app });
    }

    var appended: std.Io.Writer.Allocating = .init(output.allocator);
    defer appended.deinit();
    const needs_newline = current.len != 0 and current[current.len - 1] != '\n' and !file.insertsAt(current.len);
    if (needs_newline) appended.writer.writeByte('\n') catch return error.OutOfMemory;
    block_writer.write(&appended.writer, comment, options.id, content) catch return error.OutOfMemory;
    try output.addEdit(file, .{ .target = .{ .block = options.id }, .start = current.len, .end = current.len, .content = appended.written(), .owner = output.app });
}

/// `values` as text through `adapter`'s serialize, in `own` format layered over the adapter's.
fn serialize(output: *Output, file: []const u8, adapter: Adapter, own: Format, values: anytype) Error![]const u8 {
    const format = try output.checkFormat(file, own.orElse(adapter.default_format).resolve());
    const root = value.from(output.allocator, values) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.IntegerTooLarge => return output.fail(error.UnsupportedValue, file, "an integer is too large for a file value", .{}),
        error.NullInList => return output.fail(error.UnsupportedValue, file, "a list contains null", .{}),
    };
    var content: std.Io.Writer.Allocating = .init(output.allocator);
    errdefer content.deinit();
    var context: Adapter.Context = .{ .format = format };
    adapter.serialize.?(&content.writer, root, &context) catch |err| switch (err) {
        // An allocating writer fails only when it runs out of memory.
        error.WriteFailed => return error.OutOfMemory,
        error.UnsupportedValue => return output.fail(error.UnsupportedValue, file, "adapter '{s}': {s}", .{ adapter.name, context.message() }),
    };
    return content.toOwnedSlice();
}

/// Writes a whole file from a template whose placeholders resolve against `app`'s fields (D60, D65).
/// `options` is `.{ .file = "~/...", .text = @embedFile("templates/x"), .format = self.format }`;
/// `.text` must be comptime, so unknown paths are compile errors. `.format` (a `kosm.Format`)
/// is optional; fields left null take those of the adapter claiming the file's extension.
pub fn template(output: *Output, app: anytype, options: anytype) Error!void {
    const Options = @TypeOf(options);
    comptime checkTemplateOptions(Options);
    const path = try output.resolvePath(options.file);
    const format = try output.checkFormat(options.file, try output.templateFormat(options));

    var content: std.Io.Writer.Allocating = .init(output.allocator);
    defer content.deinit();
    var failure: template_writer.Failure = .{};
    const name = comptime if (isComptimeField(Options, "file")) options.file else "template";
    template_writer.render(&content.writer, name, options.text, app, format, &failure) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.MissingValue => return output.fail(error.MissingValue, options.file, "template line {d}: kosm.{s} is null", .{ failure.line, failure.path }),
        // checkFormat already wrote this color format once.
        error.InvalidColorFormat => unreachable,
    };
    try output.addFile(options.file, path, content.written());
}

fn checkTemplateOptions(comptime Options: type) void {
    if (@typeInfo(Options) != .@"struct") @compileError("output.template: options must be a struct literal: .{ .file = ..., .text = ... }");
    for (std.meta.fieldNames(Options)) |field_name| {
        const known = std.mem.eql(u8, field_name, "file") or std.mem.eql(u8, field_name, "text") or std.mem.eql(u8, field_name, "format");
        if (!known) @compileError("output.template: unknown option '" ++ field_name ++ "'; options are file, text, format");
    }
    if (@hasField(Options, "format") and @FieldType(Options, "format") != Format)
        @compileError("output.template: .format must be a kosm.Format, e.g. self.format");
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

/// The template's own format, its null fields from the one adapter claiming its extension,
/// then kosm's (D70).
fn templateFormat(output: *Output, options: anytype) Error!Format.Resolved {
    const own: Format = if (@hasField(@TypeOf(options), "format")) options.format else .{};
    if (own.isComplete()) return own.resolve();
    const extension = std.Io.Dir.path.extension(options.file);
    var found: ?Adapter = null;
    for (output.adapters) |adapter| {
        if (!adapter.claims(extension)) continue;
        if (found) |first| return output.fail(error.AmbiguousLanguage, options.file, "adapters '{s}' and '{s}' both handle '{s}' files; set every field of .format", .{ first.name, adapter.name, extension });
        found = adapter;
    }
    if (found) |adapter| return own.orElse(adapter.default_format).resolve();
    return own.resolve();
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

/// A hand-built color format whose template does not match its components, or a float
/// precision past `Format.max_float_precision`, is caught here, once.
fn checkFormat(output: *Output, file: []const u8, format: Format.Resolved) Error!Format.Resolved {
    if (format.float_precision > Format.max_float_precision)
        return output.fail(error.InvalidFormat, file, "float_precision {d} is more than the {d} decimals kosm can print", .{ format.float_precision, Format.max_float_precision });
    var discarding: std.Io.Writer.Discarding = .init(&.{});
    format.writeColor(&discarding.writer, .{ .lightness = 0, .chroma = 0, .hue = 0 }) catch
        return output.fail(error.InvalidFormat, file, "color format \"{s}\" does not match its {d} components", .{ format.color.template, format.color.components.len });
    return format;
}

/// Plans `content` as the whole file.
fn addFile(output: *Output, file: []const u8, path: []const u8, content: []const u8) Error!void {
    const planned = output.plan.load(path, file) catch |err| return output.failRead(file, err);
    try output.addEdit(planned, .{ .target = .whole_file, .start = 0, .end = planned.current().len, .content = content, .owner = output.app });
}

fn addEdit(output: *Output, file: *Plan.File, edit: Plan.Edit) Error!void {
    output.plan.addEdit(file, edit) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.EditsOverlap => {
            const other = file.clash(edit).?;
            return switch (other.target) {
                .whole_file => output.fail(error.EditsOverlap, file.display_path, "app '{s}' writes this whole file; two apps cannot write the same bytes (D38)", .{other.owner}),
                .block => |id| output.fail(error.EditsOverlap, file.display_path, "app '{s}' writes block '{s}' of this file; two apps cannot write the same bytes (D38)", .{ other.owner, id }),
            };
        },
    };
}

fn failRead(output: *Output, file: []const u8, err: Plan.LoadError) Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return output.fail(error.ReadFailed, file, "cannot read it: {s}", .{@errorName(err)});
}

fn fail(output: *Output, err: Error, file: []const u8, comptime format: []const u8, arguments: anytype) Error {
    output.diagnostics.set(output.app, file, format, arguments);
    return err;
}

const testing = std.testing;
const Color = @import("Color.zig");
const ColorFormat = @import("ColorFormat.zig");

/// `key = value` lines, a stand-in for a real adapter.
fn serializeLines(writer: *std.Io.Writer, root: value.Value, context: *Adapter.Context) Adapter.Error!void {
    for (root.table) |entry| {
        try writer.print("{s} = ", .{entry.key});
        switch (entry.value) {
            .string => |text| try writer.print("\"{s}\"", .{text}),
            .integer => |number| try writer.print("{d}", .{number}),
            .float => |number| try context.writeFloat(writer, number),
            .boolean => |boolean| try context.writeBoolean(writer, boolean),
            .color => |color| try context.writeColor(writer, color),
            else => return context.unsupported("'{s}' must be a plain value", .{entry.key}),
        }
        try writer.writeByte('\n');
    }
}

const lines_adapter: Adapter = .{
    .name = "lines",
    .extensions = &.{".lines"},
    .default_format = .{ .color = .hex8, .boolean = .yes_no },
    .serialize = serializeLines,
    .comment = .{ .line = "#" },
};
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
    try output.generate(.{ .file = "~/hex.lines", .format = .{ .color = .hex, .float_precision = 1 } }, .{ .accent = red, .blur = true, .opacity = 0.25 });

    const file = fixture.plan.files.items[0];
    try testing.expect(std.mem.endsWith(u8, file.path, "/kitty/kosm.lines"));
    try testing.expectEqualStrings("~/kitty/kosm.lines", file.display_path);
    try testing.expectEqualStrings("terminal", file.owner());
    try testing.expectEqual(null, file.old);
    try testing.expectEqualStrings("name = \"frost\"\nsize = 12\naccent = #bf616aff\n", file.new);
    try testing.expectEqualStrings("accent = #bf616a\nblur = yes\nopacity = 0.3\n", fixture.plan.files.items[1].new);
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

    try testing.expectError(error.UnsupportedValue, output.generate(.{ .file = "~/a.lines", .lang = "lines" }, .{ .sizes = .{ 1, 2 } }));
    try testing.expectEqualStrings("adapter 'lines': 'sizes' must be a plain value", fixture.diagnostics.message());

    const broken: ColorFormat = .{ .template = "{} {}", .components = &.{.hex} };
    try testing.expectError(error.InvalidFormat, output.generate(.{ .file = "~/a.lines", .lang = "lines", .format = .{ .color = broken } }, .{ .size = 1 }));
    try testing.expectError(error.InvalidFormat, output.generate(.{ .file = "~/a.lines", .lang = "lines", .format = .{ .float_precision = 13 } }, .{ .size = 1 }));
    try testing.expectEqualStrings("float_precision 13 is more than the 12 decimals kosm can print", fixture.diagnostics.message());
    try testing.expectEqual(0, fixture.plan.files.items.len);
}

test "two apps writing one file is an error naming the first" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var first = try fixture.output("terminal", &.{lines_adapter});
    try first.generate(.{ .file = "~/shared.lines" }, .{ .size = 1 });
    var second = try fixture.output("browser", &.{lines_adapter});
    try testing.expectError(error.EditsOverlap, second.generate(.{ .file = "~/shared.lines" }, .{ .size = 2 }));
    try testing.expectEqualStrings("browser", fixture.diagnostics.app);
    try testing.expectEqualStrings("app 'terminal' writes this whole file; two apps cannot write the same bytes (D38)", fixture.diagnostics.message());
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
    blur: bool = true,
    format: Format = .{ .color = .hex8 },
};

test "template renders the app's fields with the file's format" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("editor", &.{lines_adapter});
    const app: TemplateApp = .{ .accent = try Color.parseHex("#5e81ac") };

    try output.template(app, .{ .file = "~/theme.lua", .text = "accent = 'kosm.accent' -- {kosm.rounding}px\n", .format = app.format });
    try testing.expectEqualStrings("accent = '#5e81acff' -- 10px\n", fixture.plan.files.items[0].new);

    try output.template(app, .{ .file = "~/theme.txt", .text = "kosm.accent kosm.blur" });
    try testing.expectEqualStrings("#5e81ac true", fixture.plan.files.items[1].new);

    try output.template(app, .{ .file = "~/theme.lines", .text = "kosm.accent kosm.blur" });
    try testing.expectEqualStrings("#5e81acff yes", fixture.plan.files.items[2].new);

    try output.template(app, .{ .file = "~/more.lines", .text = "kosm.accent kosm.blur", .format = Format{ .boolean = .one_zero } });
    try testing.expectEqualStrings("#5e81acff 1", fixture.plan.files.items[3].new);
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

fn readPlanned(fixture: *Fixture, index: usize) []const u8 {
    return fixture.plan.files.items[index].new;
}

test "block creates a missing file, or appends to one lacking the block" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "kitty.lines", .data = "font = 12" });
    var output = try fixture.output("terminal", &.{lines_adapter});

    try output.block(.{ .file = "~/new.lines", .id = "colors" }, .{ .size = 1 });
    try testing.expectEqualStrings("# kosm:begin colors\nsize = 1\n# kosm:end\n", readPlanned(&fixture, 0));
    try testing.expectEqual(null, fixture.plan.files.items[0].old);

    try output.block(.{ .file = "~/kitty.lines", .id = "colors" }, .{ .size = 1 });
    try output.block(.{ .file = "~/kitty.lines", .id = "tabs" }, .{ .size = 2 });
    try testing.expectEqualStrings("font = 12\n# kosm:begin colors\nsize = 1\n# kosm:end\n# kosm:begin tabs\nsize = 2\n# kosm:end\n", readPlanned(&fixture, 1));
}

test "block replaces only the bytes between its markers" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const before = "font = 12\n  # kosm:begin colors \nsize = 9\nold = 1\n# kosm:end\n# user notes\n";
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "kitty.lines", .data = before });
    var output = try fixture.output("terminal", &.{lines_adapter});
    try output.block(.{ .file = "~/kitty.lines", .id = "colors", .format = .{ .boolean = .true_false } }, .{ .blur = true });
    try testing.expectEqualStrings("font = 12\n  # kosm:begin colors \nblur = true\n# kosm:end\n# user notes\n", readPlanned(&fixture, 0));
}

test "an unchanged block leaves its file unchanged" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "same.lines", .data = "a\n# kosm:begin colors\nsize = 1\n# kosm:end\nb\n" });
    var output = try fixture.output("terminal", &.{lines_adapter});
    try output.block(.{ .file = "~/same.lines", .id = "colors" }, .{ .size = 1 });
    try testing.expect(!fixture.plan.hasChanges());
}

test "two apps may write different blocks of one file, never the same bytes" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var terminal = try fixture.output("terminal", &.{lines_adapter});
    var browser = try fixture.output("browser", &.{lines_adapter});
    try terminal.block(.{ .file = "~/shared.lines", .id = "colors" }, .{ .size = 1 });
    try browser.block(.{ .file = "~/shared.lines", .id = "tabs" }, .{ .size = 2 });
    try testing.expectEqual(1, fixture.plan.files.items.len);

    try testing.expectError(error.EditsOverlap, browser.block(.{ .file = "~/shared.lines", .id = "colors" }, .{ .size = 3 }));
    try testing.expectEqualStrings("app 'terminal' writes block 'colors' of this file; two apps cannot write the same bytes (D38)", fixture.diagnostics.message());
    try testing.expectError(error.EditsOverlap, browser.generate(.{ .file = "~/shared.lines" }, .{ .size = 3 }));

    try terminal.generate(.{ .file = "~/whole.lines" }, .{ .size = 1 });
    try testing.expectError(error.EditsOverlap, browser.block(.{ .file = "~/whole.lines", .id = "colors" }, .{ .size = 3 }));
    try testing.expectEqualStrings("app 'terminal' writes this whole file; two apps cannot write the same bytes (D38)", fixture.diagnostics.message());
}

test "block errors name the line, the id or the missing capability" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "broken.lines", .data = "a\n# kosm:begin colors\nb\n" });
    var output = try fixture.output("terminal", &.{lines_adapter});

    try testing.expectError(error.InvalidBlock, output.block(.{ .file = "~/broken.lines", .id = "tabs" }, .{ .size = 1 }));
    try testing.expectEqualStrings("line 2: kosm:begin has no kosm:end after it", fixture.diagnostics.message());
    try testing.expectEqualStrings("~/broken.lines", fixture.diagnostics.file);

    try testing.expectError(error.InvalidBlock, output.block(.{ .file = "~/a.lines", .id = "two words" }, .{ .size = 1 }));
    try testing.expectError(error.InvalidBlock, output.block(.{ .file = "~/a.lines", .id = "colors" }, .{ .note = "x\n# kosm:end" }));
    try testing.expectEqualStrings("block 'colors', line 2 of its content: the block's own content contains a kosm: marker line", fixture.diagnostics.message());

    var css_like = try fixture.output("terminal", &.{.{ .name = "plain", .extensions = &.{".plain"}, .serialize = serializeLines }});
    try testing.expectError(error.MissingCapability, css_like.block(.{ .file = "~/a.plain", .id = "colors" }, .{ .size = 1 }));
    try testing.expectEqualStrings("adapter 'plain' cannot write blocks (it has no comment syntax)", fixture.diagnostics.message());
    var no_serialize = try fixture.output("terminal", &.{.{ .name = "plain", .extensions = &.{".plain"}, .comment = .{ .line = "#" } }});
    try testing.expectError(error.MissingCapability, no_serialize.block(.{ .file = "~/a.plain", .id = "colors" }, .{ .size = 1 }));
    try testing.expectEqual(1, fixture.plan.files.items.len);
    try testing.expect(!fixture.plan.hasChanges());
}
