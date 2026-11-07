//! What an app's `apply` writes through (D5, D22). Every call only plans; nothing reaches the
//! disk until kosm commits the whole plan (D36). Kosm sets the fields; apps only call methods.

const Output = @This();

const std = @import("std");
const Adapter = @import("Adapter.zig");
const Format = @import("Format.zig");
const Diagnostics = @import("Diagnostics.zig");
const Warnings = @import("Warnings.zig");
const ClippedColors = @import("ClippedColors.zig");
const Plan = @import("Plan.zig");
const template_writer = @import("template.zig");
const block_writer = @import("block.zig");
const value = @import("value.zig");
const glob = @import("glob.zig");
const planning = @import("Output/planning.zig");

/// Scratch memory for one apply; kosm frees it all afterwards (an arena).
allocator: std.mem.Allocator,
/// Absolute home directory that `~` expands to.
home: []const u8,
/// Every adapter the applied kosmos can use: from packages, adapters/ and the locals it reaches (D87).
adapters: []const Adapter,
plan: *Plan,
diagnostics: *Diagnostics,
/// What the apply reports without failing (D88).
warnings: *Warnings,
/// The app being applied, as its path in the kosmos tree ("terminal.kitty").
app: []const u8,

/// Options for `generate`.
pub const GenerateOptions = @import("Output/GenerateOptions.zig");
/// Options for `block`.
pub const BlockOptions = @import("Output/BlockOptions.zig");
/// Options for `edit`.
pub const EditOptions = @import("Output/EditOptions.zig");
/// Options for `find`.
pub const FindOptions = @import("Output/FindOptions.zig");
/// The files `edit` picked, and the calls setting values in them by path (D31).
pub const Selection = @import("Output/Selection.zig");
/// One value a path matched, from the escape hatch (D34, D80).
pub const Match = @import("Output/Match.zig");
/// Which of a path's matches `Selection.setOptions` sets (D31).
pub const Cardinality = @import("Output/Cardinality.zig").Cardinality;

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
    NoFile,
    InvalidSyntax,
    InvalidKeyPath,
    NoMatch,
    TooManyMatches,
    IndexOutOfRange,
    InvalidIndices,
    NotAList,
    NoValue,
    /// An app called `fail`.
    AppFailed,
    OutOfMemory,
};

/// Reports something that doesn't fail the apply, printed with the kosmos, app and `file` like
/// an error (D88). `file` is the file it is about, as the app writes it, or empty.
pub fn warn(output: *Output, file: []const u8, comptime format: []const u8, arguments: anytype) Error!void {
    try output.warnings.add(output.app, try output.allocator.dupe(u8, file), format, arguments);
}

/// Fails the apply with a message, printed with the kosmos, app and `file` like kosm's own
/// errors (D93); nothing is written. `file` is the file it is about, as the app writes it, or
/// empty. Use it as `return output.fail(file, "message {s}", .{...});`.
pub fn fail(output: *Output, file: []const u8, comptime format: []const u8, arguments: anytype) Error {
    return planning.fail(output, error.AppFailed, file, format, arguments);
}

/// Writes a whole file from `values`, a plain struct the adapter serializes (D64).
pub fn generate(output: *Output, options: GenerateOptions, values: anytype) Error!void {
    const path = try output.resolvePath(options.file);
    const adapter = try output.findAdapter(options.file, options.lang);
    if (adapter.serialize == null)
        return planning.fail(output, error.MissingCapability, options.file, "adapter '{s}' cannot write whole files (it has no serialize)", .{adapter.name});
    const content = try output.serialize(options.file, adapter, options.format, values);
    try output.addFile(options.file, path, content);
}

/// Writes `values`, serialized like `generate`'s (D64), as block `options.id` of a file the user
/// otherwise writes by hand (D71, D72). The rest of the file is kept byte for byte; a missing
/// block is appended, a missing file created (or skipped, `options.missing`). Needs an adapter
/// with `comment` and `serialize`.
pub fn block(output: *Output, options: BlockOptions, values: anytype) Error!void {
    const path = try output.resolvePath(options.file);
    const adapter = try output.findAdapter(options.file, options.lang);
    const comment = try output.blockComment(options.file, adapter);
    if (adapter.serialize == null)
        return planning.fail(output, error.MissingCapability, options.file, "adapter '{s}' cannot write data blocks (it has no serialize)", .{adapter.name});
    try output.checkBlockId(options.file, options.id);
    const content = try output.serialize(options.file, adapter, options.format, values);
    try output.planBlock(options, path, comment, content);
}

/// Writes a template, resolved against `app`'s fields like `template`'s (D60, D65), as block
/// `options.id` of a file the user otherwise writes by hand (D71, D72). `options` is
/// `.{ .file, .id, .text }` plus optional `.lang`, `.format` and `.missing`, as in `BlockOptions`;
/// `.text` must be comptime. Needs an adapter with `comment`.
pub fn templateBlock(output: *Output, app: anytype, options: anytype) Error!void {
    const Options = @TypeOf(options);
    comptime checkTemplateBlockOptions(Options);
    const resolved: BlockOptions = .{
        .file = options.file,
        .id = options.id,
        .lang = if (@hasField(Options, "lang")) options.lang else null,
        .format = if (@hasField(Options, "format")) options.format else .{},
        .missing = if (@hasField(Options, "missing")) options.missing else .create,
    };
    const path = try output.resolvePath(resolved.file);
    const adapter = try output.findAdapter(resolved.file, resolved.lang);
    const comment = try output.blockComment(resolved.file, adapter);
    try output.checkBlockId(resolved.file, resolved.id);
    const format = try output.checkFormat(resolved.file, resolved.format.orElse(adapter.default_format).resolve());

    var content: std.Io.Writer.Allocating = .init(output.allocator);
    defer content.deinit();
    var failure: template_writer.Failure = .{};
    var clipped: ClippedColors = .{};
    const name = comptime if (isComptimeField(Options, "file")) options.file else "template block";
    template_writer.render(&content.writer, name, options.text, app, format, &failure, &clipped) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.MissingValue => return planning.fail(output, error.MissingValue, resolved.file, "block '{s}', template line {d}: kosm.{s} is null", .{ resolved.id, failure.line, failure.path }),
        // checkFormat already wrote this color format once.
        error.InvalidColorFormat => unreachable,
    };
    try planning.warnClipped(output, resolved.file, "", &clipped);
    try output.planBlock(resolved, path, comment, content.written());
}

fn blockComment(output: *Output, file: []const u8, adapter: Adapter) Error!Adapter.Comment {
    return adapter.comment orelse
        planning.fail(output, error.MissingCapability, file, "adapter '{s}' cannot write blocks (it has no comment syntax)", .{adapter.name});
}

fn checkBlockId(output: *Output, file: []const u8, id: []const u8) Error!void {
    if (!block_writer.isValidId(id))
        return planning.fail(output, error.InvalidBlock, file, "block id '{s}' may only hold letters, digits, _, - and .", .{id});
}

/// Plans `content` as block `options.id` of the file at absolute `path` (D72).
fn planBlock(output: *Output, options: BlockOptions, path: []const u8, comment: Adapter.Comment, content: []const u8) Error!void {
    var failure: block_writer.Failure = .{};
    block_writer.checkContent(content, comment, &failure) catch
        return planning.fail(output, error.InvalidBlock, options.file, "block '{s}', line {d} of its content: {s}", .{ options.id, failure.line, failure.problem.describe() });
    const file = switch (options.missing) {
        .create => output.plan.load(path, options.file) catch |err| return output.failRead(options.file, err),
        .skip => output.plan.loadExisting(path, options.file) catch |err| return output.failRead(options.file, err),
    } orelse return output.warn(
        options.file,
        "does not exist, so block '{s}' is not written; apply again once it exists, or add the block's lines yourself:\n{s}",
        .{ options.id, std.mem.trimEnd(u8, content, "\n") },
    );
    const current = file.current();
    const found = block_writer.find(output.allocator, current, comment, options.id, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidBlock => return planning.fail(output, error.InvalidBlock, options.file, "line {d}: {s}", .{ failure.line, failure.problem.describe() }),
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

/// Picks the existing files matching `options.files` (D79) to set values in by path (D31).
/// Each file is parsed once, now; a file that does not parse is an error naming its line.
/// Needs an adapter with `parser` and `format`.
pub fn edit(output: *Output, options: EditOptions) Error!Selection {
    const adapter = try output.findAdapter(options.files, options.lang);
    if (adapter.parser == null)
        return planning.fail(output, error.MissingCapability, options.files, "adapter '{s}' cannot edit files (it has no parser)", .{adapter.name});
    if (adapter.format == null)
        return planning.fail(output, error.MissingCapability, options.files, "adapter '{s}' cannot edit files (it has no format)", .{adapter.name});
    const format = try output.checkFormat(options.files, options.format.orElse(adapter.default_format).resolve());

    const found = try output.expand(options.files, options.exclude);
    if (found.len == 0) return planning.fail(output, error.NoFile, options.files, "matches no file; edit only changes files that exist (D28)", .{});

    const files = try output.allocator.alloc(Selection.File, found.len);
    for (found, files) |file, *selected| {
        const display_path = try output.displayPath(file.path);
        const planned = output.plan.load(file.path, display_path) catch |err| return output.failRead(display_path, err);
        const source = planned.current();
        var context: Adapter.Context = .{ .format = format };
        const root = adapter.parser.?(output.allocator, source, &context) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSyntax => return planning.fail(output, error.InvalidSyntax, display_path, "adapter '{s}': {s}", .{ adapter.name, context.message() }),
        };
        selected.* = .{ .path = file.path, .display_path = display_path, .source = source, .root = root };
    }
    return .{ .output = output, .selector = options.files, .adapter = adapter, .format = format, .files = files };
}

/// The existing files matching `options.files` and none of `options.exclude` (D79), sorted by
/// path, written as an app writes them (`~/...` under the home directory), so they can be passed
/// to any other call. Nothing is read. Matching no file is an error naming the glob (D95).
pub fn find(output: *Output, options: FindOptions) Error![]const []const u8 {
    const found = try output.expand(options.files, options.exclude);
    if (found.len == 0) return planning.fail(output, error.NoFile, options.files, "matches no file (D28)", .{});
    const paths = try output.allocator.alloc([]const u8, found.len);
    for (found, paths) |file, *path| path.* = try output.displayPath(file.path);
    return paths;
}

/// The files `files` picks, leaving out `exclude` (D79).
fn expand(output: *Output, files: []const u8, exclude: []const []const u8) Error![]const glob.Found {
    const pattern = try output.resolvePath(files);
    const resolved_exclude = try output.allocator.alloc([]const u8, exclude.len);
    for (exclude, resolved_exclude) |written, *resolved| resolved.* = try output.resolvePath(written);
    var failure: glob.Failure = .{};
    return glob.expand(output.allocator, output.plan.io, pattern, resolved_exclude, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unreadable => return planning.fail(output, error.ReadFailed, files, "cannot read {s}: {s}", .{ failure.path, failure.reason }),
    };
}

/// `path` with the home directory written as `~`, as messages and diffs show files.
fn displayPath(output: *Output, path: []const u8) Error![]const u8 {
    const inside_home = std.mem.startsWith(u8, path, output.home) and path.len > output.home.len and path[output.home.len] == '/';
    if (!inside_home) return path;
    return std.mem.concat(output.allocator, u8, &.{ "~", path[output.home.len..] });
}

/// `values` as text through `adapter`'s serialize, in `own` format layered over the adapter's.
fn serialize(output: *Output, file: []const u8, adapter: Adapter, own: Format, values: anytype) Error![]const u8 {
    const format = try output.checkFormat(file, own.orElse(adapter.default_format).resolve());
    var context: Adapter.Context = .{ .format = format };
    const root = value.from(output.allocator, &context.clipped, values) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.IntegerTooLarge => return planning.fail(output, error.UnsupportedValue, file, "an integer is too large for a file value", .{}),
        error.NullInList => return planning.fail(output, error.UnsupportedValue, file, "a list contains null", .{}),
    };
    var content: std.Io.Writer.Allocating = .init(output.allocator);
    errdefer content.deinit();
    adapter.serialize.?(&content.writer, root, &context) catch |err| switch (err) {
        // An allocating writer fails only when it runs out of memory.
        error.WriteFailed => return error.OutOfMemory,
        error.UnsupportedValue => return planning.fail(output, error.UnsupportedValue, file, "adapter '{s}': {s}", .{ adapter.name, context.message() }),
    };
    try planning.warnClipped(output, file, "", &context.clipped);
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
    var clipped: ClippedColors = .{};
    const name = comptime if (isComptimeField(Options, "file")) options.file else "template";
    template_writer.render(&content.writer, name, options.text, app, format, &failure, &clipped) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.MissingValue => return planning.fail(output, error.MissingValue, options.file, "template line {d}: kosm.{s} is null", .{ failure.line, failure.path }),
        // checkFormat already wrote this color format once.
        error.InvalidColorFormat => unreachable,
    };
    try planning.warnClipped(output, options.file, "", &clipped);
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

fn checkTemplateBlockOptions(comptime Options: type) void {
    if (@typeInfo(Options) != .@"struct") @compileError("output.templateBlock: options must be a struct literal: .{ .file = ..., .id = ..., .text = ... }");
    for (std.meta.fieldNames(Options)) |field_name| {
        const known = for ([_][]const u8{ "file", "id", "text", "lang", "format", "missing" }) |option| {
            if (std.mem.eql(u8, field_name, option)) break true;
        } else false;
        if (!known) @compileError("output.templateBlock: unknown option '" ++ field_name ++ "'; options are file, id, text, lang, format, missing");
    }
    if (@hasField(Options, "format") and @FieldType(Options, "format") != Format)
        @compileError("output.templateBlock: .format must be a kosm.Format, e.g. self.format");
    inline for (.{ "file", "id", "text" }) |required| {
        if (!@hasField(Options, required)) @compileError("output.templateBlock: missing option ." ++ required);
    }
    if (!isComptimeField(Options, "text")) @compileError("output.templateBlock: .text must be comptime, e.g. @embedFile(\"templates/block.lua\")");
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
        if (found) |first| return planning.fail(output, error.AmbiguousLanguage, options.file, "adapters '{s}' and '{s}' both handle '{s}' files; set every field of .format", .{ first.name, adapter.name, extension });
        found = adapter;
    }
    if (found) |adapter| return own.orElse(adapter.default_format).resolve();
    return own.resolve();
}

fn resolvePath(output: *Output, file: []const u8) Error![]const u8 {
    if (std.mem.startsWith(u8, file, "~/")) return std.Io.Dir.path.join(output.allocator, &.{ output.home, file[2..] });
    if (std.Io.Dir.path.isAbsolute(file)) return file;
    return planning.fail(output, error.InvalidPath, file, "file paths start with ~/ or /", .{});
}

/// The adapter named `lang`, or the one claiming the file's extension (D26).
fn findAdapter(output: *Output, file: []const u8, lang: ?[]const u8) Error!Adapter {
    if (lang) |name| {
        for (output.adapters) |adapter| {
            if (std.mem.eql(u8, adapter.name, name)) return adapter;
        }
        return planning.fail(output, error.UnknownLanguage, file, "no adapter is named '{s}'", .{name});
    }
    const extension = std.Io.Dir.path.extension(file);
    var found: ?Adapter = null;
    for (output.adapters) |adapter| {
        if (!adapter.claims(extension)) continue;
        if (found) |first| return planning.fail(output, error.AmbiguousLanguage, file, "adapters '{s}' and '{s}' both handle '{s}' files; pass .lang", .{ first.name, adapter.name, extension });
        found = adapter;
    }
    return found orelse planning.fail(output, error.UnknownLanguage, file, "no adapter handles '{s}' files; pass .lang", .{extension});
}

/// A hand-built color format whose template does not match its components, or a float
/// precision past `Format.max_float_precision`, is caught here, once.
fn checkFormat(output: *Output, file: []const u8, format: Format.Resolved) Error!Format.Resolved {
    if (format.float_precision > Format.max_float_precision)
        return planning.fail(output, error.InvalidFormat, file, "float_precision {d} is more than the {d} decimals kosm can print", .{ format.float_precision, Format.max_float_precision });
    var discarding: std.Io.Writer.Discarding = .init(&.{});
    format.writeColor(&discarding.writer, .{ .lightness = 0, .chroma = 0, .hue = 0 }) catch
        return planning.fail(output, error.InvalidFormat, file, "color format \"{s}\" does not match its {d} components", .{ format.color.template, format.color.components.len });
    return format;
}

/// Plans `content` as the whole file.
fn addFile(output: *Output, file: []const u8, path: []const u8, content: []const u8) Error!void {
    const planned = output.plan.load(path, file) catch |err| return output.failRead(file, err);
    try output.addEdit(planned, .{ .target = .whole_file, .start = 0, .end = planned.current().len, .content = content, .owner = output.app });
}

fn addEdit(output: *Output, file: *Plan.File, planned: Plan.Edit) Error!void {
    return planning.addEdit(output, file, planned);
}

fn failRead(output: *Output, file: []const u8, err: Plan.LoadError) Error {
    return planning.failRead(output, file, err);
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
    warnings: Warnings,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,

    fn init(fixture: *Fixture) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io), .warnings = undefined };
        fixture.warnings = .init(fixture.arena.allocator());
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
            .warnings = &fixture.warnings,
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

test "an app's own failure names the app and its file (D93)" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("hyprland", &.{lines_adapter});
    try testing.expectEqual(error.AppFailed, output.fail("~/hypr/kosm.lua", "option '{s}': a gradient needs at least one color", .{"general.col.active_border"}));
    try testing.expectEqualStrings("option 'general.col.active_border': a gradient needs at least one color", fixture.diagnostics.message());
    try testing.expectEqualStrings("~/hypr/kosm.lua", fixture.diagnostics.file);
    try testing.expectEqualStrings("hyprland", fixture.diagnostics.app);
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

const vivid_green: Color = .{ .lightness = 0.9, .chroma = 0.4, .hue = 140 };

test "a clipped color warns naming the app and file, once per color, and is still written" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("terminal", &.{lines_adapter});
    try output.generate(.{ .file = "~/a.lines" }, .{ .accent = vivid_green, .border = vivid_green, .glow = vivid_green.format("rgba({})", &.{.hex8}) });

    try testing.expectEqualStrings("accent = #00ff00ff\nborder = #00ff00ff\nglow = \"rgba(00ff00ff)\"\n", readPlanned(&fixture, 0));
    const warnings = fixture.warnings.items.items;
    try testing.expectEqual(1, warnings.len);
    try testing.expectEqualStrings("terminal", warnings[0].app);
    try testing.expectEqualStrings("~/a.lines", warnings[0].file);
    try testing.expectEqualStrings("color oklch(0.9 0.4 140) is outside sRGB and is clipped to #00ff00 (3 times) (D48)", warnings[0].message);
}

test "in-gamut colors and unclipped float components do not warn" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("terminal", &.{lines_adapter});
    const accent = try Color.parseHex("#5e81ac");
    try output.generate(.{ .file = "~/a.lines" }, .{ .accent = accent, .white = try Color.parseHex("#ffffff"), .glow = vivid_green.format("{}", &.{.red_01}) });
    const app: TemplateApp = .{ .accent = accent };
    try output.template(app, .{ .file = "~/theme.lua", .text = "kosm.accent kosm.accent.red_255", .format = app.format });
    try testing.expectEqual(0, fixture.warnings.items.items.len);
}

test "a template warns with the line of a clipped placeholder" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("editor", &.{});
    const app: TemplateApp = .{ .accent = vivid_green };
    try output.template(app, .{ .file = "~/theme.lua", .text = "a\nkosm.accent.lightness\nkosm.accent.green_255\n" });
    try testing.expectEqualStrings("a\n0.9\n255\n", readPlanned(&fixture, 0));
    const warnings = fixture.warnings.items.items;
    try testing.expectEqual(1, warnings.len);
    try testing.expectEqualStrings("~/theme.lua", warnings[0].file);
    try testing.expectEqualStrings("template line 3: color oklch(0.9 0.4 140) is outside sRGB and is clipped to #00ff00 (D48)", warnings[0].message);
}

test "an app's own warning names it and its file" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("bar.waybar", &.{});
    try output.warn("~/.config/waybar/style.css", "font '{s}' is not installed", .{"Iosevka"});
    const warning = fixture.warnings.items.items[0];
    try testing.expectEqualStrings("bar.waybar", warning.app);
    try testing.expectEqualStrings("~/.config/waybar/style.css", warning.file);
    try testing.expectEqualStrings("font 'Iosevka' is not installed", warning.message);
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

test "find lists matching files under ~ in path order, and errors naming a glob matching none" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    for ([_][]const u8{ "zen/b.work/prefs.js", "zen/a.default/prefs.js", "zen/Crash Reports/x", "zen/c.old/prefs.js" }) |path| {
        try fixture.tmp.dir.createDirPath(testing.io, std.Io.Dir.path.dirname(path).?);
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = "" });
    }
    var output = try fixture.output("zen", &.{});

    const found = try output.find(.{ .files = "~/zen/*/prefs.js", .exclude = &.{"~/zen/c.old/**"} });
    try testing.expectEqual(2, found.len);
    try testing.expectEqualStrings("~/zen/a.default/prefs.js", found[0]);
    try testing.expectEqualStrings("~/zen/b.work/prefs.js", found[1]);

    try testing.expectError(error.NoFile, output.find(.{ .files = "~/firefox/*/prefs.js" }));
    try testing.expectEqualStrings("~/firefox/*/prefs.js", fixture.diagnostics.file);
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

test "templateBlock appends a template's lines to an existing file, and leaves them alone afterwards" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "main.lines", .data = "font = 12" });
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "done.lines", .data = "a\n# kosm:begin include\nload #5e81acff\n# kosm:end\nb\n" });
    var output = try fixture.output("terminal", &.{lines_adapter});
    const app: TemplateApp = .{ .accent = try Color.parseHex("#5e81ac") };

    try output.templateBlock(app, .{ .file = "~/main.lines", .id = "include", .text = "load kosm.accent\n", .missing = .skip });
    try testing.expectEqualStrings("font = 12\n# kosm:begin include\nload #5e81acff\n# kosm:end\n", readPlanned(&fixture, 0));
    try output.templateBlock(app, .{ .file = "~/done.lines", .id = "include", .text = "load kosm.accent", .missing = .skip });
    try testing.expect(!fixture.plan.files.items[1].changed());
    try output.templateBlock(app, .{ .file = "~/new.txt", .id = "include", .text = "load kosm.accent", .lang = "lines", .format = Format{ .color = .hex } });
    try testing.expectEqualStrings("# kosm:begin include\nload #5e81ac\n# kosm:end\n", readPlanned(&fixture, 2));
    try testing.expectEqual(0, fixture.warnings.items.items.len);
}

test "a block skipping a missing file plans nothing and warns with its lines" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("hyprland", &.{lines_adapter});
    const app: TemplateApp = .{ .accent = try Color.parseHex("#5e81ac") };

    try output.templateBlock(app, .{ .file = "~/hypr/main.lines", .id = "include", .text = "load kosm\n", .missing = .skip });
    try output.block(.{ .file = "~/other.lines", .id = "colors", .missing = .skip }, .{ .size = 1 });
    try testing.expectEqual(0, fixture.plan.files.items.len);
    const warnings = fixture.warnings.items.items;
    try testing.expectEqual(2, warnings.len);
    try testing.expectEqualStrings("~/hypr/main.lines", warnings[0].file);
    try testing.expectEqualStrings("does not exist, so block 'include' is not written; apply again once it exists, or add the block's lines yourself:\nload kosm", warnings[0].message);

    var terminal = try fixture.output("terminal", &.{lines_adapter});
    try terminal.generate(.{ .file = "~/created.lines" }, .{ .size = 1 });
    try testing.expectError(error.EditsOverlap, output.block(.{ .file = "~/created.lines", .id = "colors", .missing = .skip }, .{ .size = 2 }));
}

test "templateBlock errors name the block" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var output = try fixture.output("editor", &.{ lines_adapter, .{ .name = "plain", .extensions = &.{".plain"} } });
    const app: TemplateApp = .{ .accent = try Color.parseHex("#5e81ac") };
    try testing.expectError(error.MissingValue, output.templateBlock(app, .{ .file = "~/a.lines", .id = "theme", .text = "a\nkosm.border_inactive\n" }));
    try testing.expectEqualStrings("block 'theme', template line 2: kosm.border_inactive is null", fixture.diagnostics.message());
    try testing.expectError(error.MissingCapability, output.templateBlock(app, .{ .file = "~/a.plain", .id = "theme", .text = "a" }));
    try testing.expectError(error.InvalidBlock, output.templateBlock(app, .{ .file = "~/a.lines", .id = "two words", .text = "a" }));
    try testing.expectError(error.InvalidBlock, output.templateBlock(app, .{ .file = "~/a.lines", .id = "theme", .text = "# kosm:end\n" }));
    try testing.expectEqual(0, fixture.plan.files.items.len);
}
