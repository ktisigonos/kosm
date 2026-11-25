//! Template placeholders: `kosm.<path>` or `{kosm.<path>}`, resolved against an app's
//! fields. Templates are comptime text, so an unknown path is a compile error; a template known
//! only at run time (a script's) resolves against a `kosm.Value` table instead.

const std = @import("std");
const Color = @import("Color.zig");
const ColorFormat = @import("ColorFormat.zig");
const Format = @import("Format.zig");
const Raw = @import("Raw.zig");
const Value = @import("value.zig").Value;
const suggestion = @import("kosm_suggestion");

/// Where a placeholder pointed at a `null` optional, the one failure only runtime can see.
pub const Failure = struct {
    /// 1-based line of the placeholder in the template.
    line: usize = 0,
    /// The placeholder's path without the `kosm.` prefix.
    path: []const u8 = "",
};

/// Errors from `render`.
pub const Error = ColorFormat.WriteError || error{MissingValue};

/// Writes `text` with every placeholder replaced by the value at its path in `app`. Colors
/// print in `format`: a color without a component in its color format. `name` names the template in compile
/// errors. A `null` on the way is `error.MissingValue`, described in `failure`.
pub fn render(
    writer: *std.Io.Writer,
    comptime name: []const u8,
    comptime text: []const u8,
    app: anytype,
    format: Format.Resolved,
    failure: *Failure,
) Error!void {
    const parts = comptime parse(name, text);
    inline for (parts) |part| {
        try writer.writeAll(part.literal);
        if (part.path.len != 0) {
            const location: Location = .{ .name = name, .line = part.line, .path = part.path, .braced = part.braced };
            writeValue(writer, app, comptime splitPath(part.path), location, format) catch |err| {
                if (err == error.MissingValue) failure.* = .{ .line = part.line, .path = part.path };
                return err;
            };
        }
    }
}

/// Why a template known only at run time could not be written.
pub const ValueFailure = struct {
    /// 1-based line of the placeholder in the template.
    line: usize = 0,
    /// The placeholder's path without the `kosm.` prefix; empty for an unclosed brace.
    path: []const u8 = "",
    reason_buffer: [256]u8 = undefined,
    reason_length: usize = 0,

    /// Why the placeholder could not be written.
    pub fn reason(failure: *const ValueFailure) []const u8 {
        return failure.reason_buffer[0..failure.reason_length];
    }

    /// Records `format`, holding one `{s}` for `detail`, as the reason; returns the error.
    fn set(failure: *ValueFailure, comptime format: []const u8, detail: []const u8) error{InvalidTemplate} {
        const written = std.fmt.bufPrint(&failure.reason_buffer, format, .{detail}) catch failure.reason_buffer[0..];
        failure.reason_length = written.len;
        return error.InvalidTemplate;
    }
};

/// Errors from `renderValue`.
pub const ValueError = ColorFormat.WriteError || error{InvalidTemplate};

/// Writes `text` with every placeholder replaced by the value at its path in `values`, a table,
/// like `render` does with an app's fields. An unclosed brace, a path naming nothing and a path
/// ending on a table or list are `error.InvalidTemplate`, described in `failure`.
pub fn renderValue(writer: *std.Io.Writer, text: []const u8, values: Value, format: Format.Resolved, failure: *ValueFailure) ValueError!void {
    var position: usize = 0;
    while (true) switch (scan(text, position)) {
        .none => break,
        .unclosed => |at| {
            failure.* = .{ .line = lineOf(text, at) };
            return failure.set("'{{' before 'kosm.' is never closed with '}}'{s}", "");
        },
        .found => |placeholder| {
            try writer.writeAll(text[position..placeholder.start]);
            failure.* = .{ .line = lineOf(text, placeholder.start), .path = placeholder.path };
            try writeValueAt(writer, values, placeholder.path, format, failure);
            position = placeholder.end;
        },
    };
    try writer.writeAll(text[position..]);
}

fn writeValueAt(writer: *std.Io.Writer, values: Value, path: []const u8, format: Format.Resolved, failure: *ValueFailure) ValueError!void {
    var current = values;
    var segments = std.mem.splitScalar(u8, path, '.');
    while (segments.next()) |segment| {
        switch (current) {
            .table => |entries| current = for (entries) |entry| {
                if (std.mem.eql(u8, entry.key, segment)) break entry.value;
            } else return failure.set("it names nothing; there is no field '{s}'", segment),
            .color => |color| {
                const component = std.meta.stringToEnum(Color.Component, segment) orelse
                    return failure.set("a color has no '{s}'", segment);
                if (segments.next() != null) return failure.set("color component '{s}' has no fields", segment);
                return format.writeComponent(writer, color, component);
            },
            else => return failure.set("'{s}' follows a value, which has no fields", segment),
        }
    }
    try writeValueLeaf(writer, current, format, failure);
}

fn writeValueLeaf(writer: *std.Io.Writer, value: Value, format: Format.Resolved, failure: *ValueFailure) ValueError!void {
    switch (value) {
        .string, .raw => |text| try writer.writeAll(text),
        .integer => |integer| try writer.print("{d}", .{integer}),
        .float => |float| try format.writeFloat(writer, float),
        .boolean => |boolean| try format.writeBoolean(writer, boolean),
        .color => |color| try format.writeColor(writer, color),
        .joined => |parts| for (parts) |part| try writeValueLeaf(writer, part, format, failure),
        .table, .list => return failure.set("it is a {s}; name one of its values", @tagName(value)),
    }
}

/// Literal text followed by at most one placeholder.
const Part = struct {
    literal: []const u8,
    /// Path after `kosm.`; empty for the trailing literal.
    path: []const u8 = "",
    line: usize = 0,
    braced: bool = false,
};

const Location = struct {
    name: []const u8,
    line: usize,
    path: []const u8,
    braced: bool,
};

const prefix = "kosm.";

/// A placeholder found in the text: bytes `start..end` hold it, `path` is what follows `kosm.`.
const Placeholder = struct {
    start: usize,
    end: usize,
    path: []const u8,
    braced: bool,
};

const Scan = union(enum) {
    found: Placeholder,
    none,
    /// A `{ kosm.` with no closing `}` at this byte.
    unclosed: usize,
};

fn parse(comptime name: []const u8, comptime text: []const u8) []const Part {
    comptime {
        @setEvalBranchQuota(100 * text.len + 10_000);
        var count: usize = 1;
        var position: usize = 0;
        while (true) switch (scan(text, position)) {
            .found => |placeholder| {
                count += 1;
                position = placeholder.end;
            },
            .none => break,
            .unclosed => |at| @compileError(std.fmt.comptimePrint(
                "template {s}, line {d}: '{{' before 'kosm.' is never closed with '}}'",
                .{ name, lineOf(text, at) },
            )),
        };

        var parts: [count]Part = undefined;
        var index: usize = 0;
        position = 0;
        while (scan(text, position) == .found) : (index += 1) {
            const placeholder = scan(text, position).found;
            parts[index] = .{
                .literal = text[position..placeholder.start],
                .path = placeholder.path,
                .line = lineOf(text, placeholder.start),
                .braced = placeholder.braced,
            };
            position = placeholder.end;
        }
        parts[index] = .{ .literal = text[position..] };
        const final = parts;
        return &final;
    }
}

/// Finds the first placeholder at or after `from`.
fn scan(text: []const u8, from: usize) Scan {
    var index = from;
    while (index < text.len) : (index += 1) {
        if (text[index] == '{') {
            switch (scanBraced(text, index)) {
                .none => {},
                else => |result| return result,
            }
        } else if (startsBare(text, index)) {
            const path_start = index + prefix.len;
            var end = path_start;
            while (end < text.len) : (end += 1) {
                const continues_with_letter = text[end] == '.' and end + 1 < text.len and std.ascii.isAlphabetic(text[end + 1]);
                if (!isPathCharacter(text[end]) and !continues_with_letter) break;
            }
            return .{ .found = .{ .start = index, .end = end, .path = text[path_start..end], .braced = false } };
        }
    }
    return .none;
}

fn scanBraced(text: []const u8, open: usize) Scan {
    var index = skipSpaces(text, open + 1);
    if (!std.mem.startsWith(u8, text[index..], prefix) or !startsPath(text, index + prefix.len)) return .none;
    index += prefix.len;
    const path_start = index;
    while (index < text.len and (isPathCharacter(text[index]) or text[index] == '.')) index += 1;
    const path_end = index;
    index = skipSpaces(text, index);
    if (index >= text.len or text[index] != '}') return .{ .unclosed = open };
    return .{ .found = .{ .start = open, .end = index + 1, .path = text[path_start..path_end], .braced = true } };
}

/// `kosm.` followed by a letter, not glued to a longer word (`mykosm.x` is plain text).
fn startsBare(text: []const u8, index: usize) bool {
    if (!std.mem.startsWith(u8, text[index..], prefix)) return false;
    if (index > 0 and (isPathCharacter(text[index - 1]) or text[index - 1] == '.')) return false;
    return startsPath(text, index + prefix.len);
}

fn startsPath(text: []const u8, index: usize) bool {
    return index < text.len and std.ascii.isAlphabetic(text[index]);
}

fn isPathCharacter(character: u8) bool {
    return std.ascii.isAlphanumeric(character) or character == '_';
}

fn skipSpaces(text: []const u8, from: usize) usize {
    var index = from;
    while (index < text.len and text[index] == ' ') index += 1;
    return index;
}

fn lineOf(text: []const u8, index: usize) usize {
    return std.mem.count(u8, text[0..index], "\n") + 1;
}

fn splitPath(comptime path: []const u8) []const []const u8 {
    comptime {
        var segments: [std.mem.count(u8, path, ".") + 1][]const u8 = undefined;
        var iterator = std.mem.splitScalar(u8, path, '.');
        for (&segments) |*segment| {
            segment.* = iterator.next().?;
            if (segment.len == 0) @compileError("template: empty segment in kosm." ++ path);
        }
        const final = segments;
        return &final;
    }
}

fn writeValue(
    writer: *std.Io.Writer,
    value: anytype,
    comptime rest: []const []const u8,
    comptime location: Location,
    format: Format.Resolved,
) Error!void {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .optional) {
        const present = value orelse return error.MissingValue;
        return writeValue(writer, present, rest, location, format);
    }
    if (rest.len == 0) return writeLeaf(writer, value, location, format);
    if (T == Color) {
        if (comptime std.meta.stringToEnum(Color.Component, rest[0])) |component| {
            if (rest.len > 1) fail(location, "color component '" ++ rest[0] ++ "' has no '" ++ rest[1] ++ "'");
            return format.writeComponent(writer, value, component);
        }
        fail(location, "a color has no '" ++ rest[0] ++ "'; its components are " ++ joinNames(std.meta.fieldNames(Color.Component)));
    }
    if (@typeInfo(T) != .@"struct")
        fail(location, "'" ++ rest[0] ++ "' follows a " ++ @typeName(T) ++ ", which has no fields");
    if (!@hasField(T, rest[0])) fail(location, unknownField(T, location, rest));
    return writeValue(writer, @field(value, rest[0]), rest[1..], location, format);
}

fn writeLeaf(writer: *std.Io.Writer, value: anytype, comptime location: Location, format: Format.Resolved) Error!void {
    const T = @TypeOf(value);
    if (T == Color) return format.writeColor(writer, value);
    if (T == Raw) return writer.writeAll(value.text);
    if (T == []const u8 or T == []u8) return writer.writeAll(value);
    switch (@typeInfo(T)) {
        .pointer => |pointer| if (pointer.size == .one and @typeInfo(pointer.child) == .array and
            @typeInfo(pointer.child).array.child == u8) return writer.writeAll(value),
        .int, .comptime_int => return writer.print("{d}", .{value}),
        .float, .comptime_float => return format.writeFloat(writer, value),
        .bool => return format.writeBoolean(writer, value),
        .@"enum" => return writer.writeAll(@tagName(value)),
        .@"struct" => fail(location, "this is a struct; name one of its fields: " ++ joinNames(std.meta.fieldNames(T))),
        else => {},
    }
    fail(location, "a " ++ @typeName(T) ++ " cannot be printed into a template");
}

fn fail(comptime location: Location, comptime message: []const u8) noreturn {
    @compileError(std.fmt.comptimePrint("template {s}, line {d}: kosm.{s}: {s}", .{ location.name, location.line, location.path, message }));
}

/// "unknown field", with the nearest field as a suggestion: a field glued to text
/// (`kosm.roundingpx`) suggests the braced form. `rest` starts with the unknown segment.
fn unknownField(comptime T: type, comptime location: Location, comptime rest: []const []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        const segment = rest[0];
        const segments = splitPath(location.path);
        var before: []const u8 = "";
        for (segments[0 .. segments.len - rest.len]) |known| before = before ++ known ++ ".";
        const names = std.meta.fieldNames(T);
        for (names) |field_name| {
            if (!location.braced and rest.len == 1 and std.mem.startsWith(u8, segment, field_name)) {
                return "unknown field '" ++ segment ++ "'; did you mean {kosm." ++ before ++ field_name ++ "}" ++
                    segment[field_name.len..] ++ "?";
            }
        }
        var best: []const u8 = "";
        var best_distance: usize = std.math.maxInt(usize);
        for (names) |field_name| {
            const distance = suggestion.closeness(segment, field_name);
            if (distance < best_distance) {
                best = field_name;
                best_distance = distance;
            }
        }
        if (best.len != 0 and best_distance <= suggestion.allowedEdits(segment.len))
            return "unknown field '" ++ segment ++ "'; did you mean kosm." ++ before ++ best ++ "?";
        return "unknown field '" ++ segment ++ "'; fields are " ++ joinNames(names);
    }
}

fn joinNames(comptime names: []const []const u8) []const u8 {
    comptime {
        var joined: []const u8 = "";
        for (names, 0..) |field_name, index| joined = joined ++ (if (index == 0) "" else ", ") ++ field_name;
        return joined;
    }
}

const testing = std.testing;

const TestApp = struct {
    rounding: u8 = 10,
    opacity: f64 = 0.85,
    blur: bool = true,
    terminal: []const u8 = "kitty",
    mode: enum { dark, light } = .dark,
    border_inactive: ?Color = null,
    literal: Raw = .{ .text = "rgba(0, 0, 0, 0)" },
    palette: struct { red: Color, blue: Color },
};

fn testApp() !TestApp {
    return .{ .palette = .{ .red = try Color.parseHex("#bf616a"), .blue = try Color.parseHex("#5e81ac") } };
}

const test_format = Format.kosm_default;

fn expectRendered(expected: []const u8, comptime text: []const u8) !void {
    try expectRenderedWith(expected, text, test_format);
}

fn expectRenderedWith(expected: []const u8, comptime text: []const u8, format: Format.Resolved) !void {
    var buffer: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var failure: Failure = .{};
    try render(&writer, "test", text, try testApp(), format, &failure);
    try testing.expectEqualStrings(expected, writer.buffered());
}

test "bare and braced placeholders resolve against the app's fields" {
    try expectRendered("radius 10;", "radius kosm.rounding;");
    try expectRendered("radius: 10px", "radius: {kosm.rounding}px");
    try expectRendered("radius: 10px", "radius: { kosm.rounding }px");
    try expectRendered("red = '#bf616a'", "red = 'kosm.palette.red'");
    try expectRendered("0.85 true kitty dark rgba(0, 0, 0, 0)", "kosm.opacity kosm.blur kosm.terminal kosm.mode kosm.literal");
}

test "color components name the printed form" {
    try expectRendered("bf616aff 94", "kosm.palette.red.hex8 {kosm.palette.blue.red_255}");
}

test "booleans, floats and float components follow the file's format" {
    const format: Format.Resolved = .{ .color = .hex_upper, .boolean = .on_off, .float_precision = 2 };
    try expectRenderedWith("on 0.85 #BF616A 0.59", "kosm.blur kosm.opacity kosm.palette.red {kosm.palette.blue.lightness}", format);
}

test "a sentence-ending dot and plain braces are left alone" {
    try expectRendered("Corners are 10.", "Corners are kosm.rounding.");
    try expectRendered("{ \"a\": {} } mykosm.rounding {x}", "{ \"a\": {} } mykosm.rounding {x}");
    try expectRendered("kosm. and kosm.5", "kosm. and kosm.5");
}

test "a placeholder at the very end and on later lines" {
    try expectRendered("a\nb 10", "a\nb kosm.rounding");
}

test "a null optional is a runtime error naming the line" {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var failure: Failure = .{};
    try testing.expectError(error.MissingValue, render(&writer, "test", "one\nkosm.border_inactive", try testApp(), test_format, &failure));
    try testing.expectEqual(2, failure.line);
    try testing.expectEqualStrings("border_inactive", failure.path);
}

test "suggestions for unknown fields" {
    const glued: Location = .{ .name = "t", .line = 1, .path = "roundingpx", .braced = false };
    try testing.expectEqualStrings(
        "unknown field 'roundingpx'; did you mean {kosm.rounding}px?",
        comptime unknownField(TestApp, glued, &.{"roundingpx"}),
    );
    const typo: Location = .{ .name = "t", .line = 1, .path = "palette.rde", .braced = false };
    try testing.expectEqualStrings(
        "unknown field 'rde'; did you mean kosm.palette.red?",
        comptime unknownField(@FieldType(TestApp, "palette"), typo, &.{"rde"}),
    );
    const unrelated: Location = .{ .name = "t", .line = 1, .path = "palette.zzzzzz", .braced = true };
    try testing.expectEqualStrings(
        "unknown field 'zzzzzz'; fields are red, blue",
        comptime unknownField(@FieldType(TestApp, "palette"), unrelated, &.{"zzzzzz"}),
    );
}

test "parse finds unclosed braces" {
    try testing.expectEqual(Scan{ .unclosed = 2 }, scan("a {kosm.x", 0));
}

fn testValues() !Value {
    const palette = try testing.allocator.dupe(Value.Entry, &.{.{ .key = "red", .value = .{ .color = try Color.parseHex("#bf616a") } }});
    return .{ .table = try testing.allocator.dupe(Value.Entry, &.{
        .{ .key = "rounding", .value = .{ .integer = 10 } },
        .{ .key = "opacity", .value = .{ .float = 0.85 } },
        .{ .key = "blur", .value = .{ .boolean = true } },
        .{ .key = "terminal", .value = .{ .string = "kitty" } },
        .{ .key = "gap", .value = .{ .joined = &.{ .{ .integer = 2 }, .{ .raw = "pt" } } } },
        .{ .key = "palette", .value = .{ .table = palette } },
    }) };
}

fn freeTestValues(values: Value) void {
    testing.allocator.free(values.table[5].value.table);
    testing.allocator.free(values.table);
}

fn renderTestValues(writer: *std.Io.Writer, text: []const u8, failure: *ValueFailure) !void {
    const values = try testValues();
    defer freeTestValues(values);
    return renderValue(writer, text, values, test_format, failure);
}

test "a run-time template resolves placeholders against a value table" {
    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var failure: ValueFailure = .{};
    try renderTestValues(&writer, "radius kosm.rounding; {kosm.opacity} kosm.blur kosm.terminal\ngap {kosm.gap} red 'kosm.palette.red' kosm.palette.red.hex8.", &failure);
    try testing.expectEqualStrings("radius 10; 0.85 true kitty\ngap 2pt red '#bf616a' bf616aff.", writer.buffered());
}

test "a run-time template naming nothing, a table or an unclosed brace fails naming its line" {
    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var failure: ValueFailure = .{};
    try testing.expectError(error.InvalidTemplate, renderTestValues(&writer, "a\nkosm.roundin", &failure));
    try testing.expectEqual(2, failure.line);
    try testing.expectEqualStrings("roundin", failure.path);
    try testing.expectEqualStrings("it names nothing; there is no field 'roundin'", failure.reason());
    try testing.expectError(error.InvalidTemplate, renderTestValues(&writer, "kosm.palette", &failure));
    try testing.expectEqualStrings("it is a table; name one of its values", failure.reason());
    try testing.expectError(error.InvalidTemplate, renderTestValues(&writer, "kosm.palette.red.shine", &failure));
    try testing.expectEqualStrings("a color has no 'shine'", failure.reason());
    try testing.expectError(error.InvalidTemplate, renderTestValues(&writer, "x\n\n{ kosm.rounding", &failure));
    try testing.expectEqual(3, failure.line);
    try testing.expectEqualStrings("'{' before 'kosm.' is never closed with '}'", failure.reason());
}
