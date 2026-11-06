//! Turns `--name value` flags into a kosmos' `Params` struct by reflection (D19), with colors
//! in any common text form (D55) and an opt-in `host` field filled from the hostname (D56).

const std = @import("std");
const kosm = @import("kosm");

/// Errors from `parse`; `diagnostics` holds the message.
pub const Error = error{InvalidParams};

/// Flags kosm itself takes, which no `Params` field may shadow.
const reserved_names = [_][]const u8{ "diff", "config", "set" };

/// Fills a `Params` from `arguments` (`--blur false --accent sky`), starting from its defaults.
/// Flags may be spelled `--border-size` or `--border_size`. A `host` enum field not given as
/// a flag is set from `hostname`. Returned strings point into `arguments`.
pub fn parse(comptime Params: type, arguments: []const []const u8, hostname: []const u8, diagnostics: *kosm.Diagnostics) Error!Params {
    comptime checkParams(Params);
    const fields = @typeInfo(Params).@"struct";
    if (comptime fields.field_names.len == 0) {
        if (arguments.len != 0) return fail(diagnostics, "it takes no parameters, got '{s}'", .{arguments[0]});
        return .{};
    }
    var params: Params = .{};
    var given: [fields.field_names.len]bool = @splat(false);
    var index: usize = 0;
    while (index < arguments.len) : (index += 2) {
        const flag = arguments[index];
        if (!std.mem.startsWith(u8, flag, "--") or flag.len == 2)
            return fail(diagnostics, "expected --<parameter> <value>, got '{s}'", .{flag});
        const field_index = fieldIndex(Params, flag[2..]) orelse
            return fail(diagnostics, "'{s}' is not a parameter; parameters are {s}", .{ flag, comptime flagList(Params) });
        if (given[field_index]) return fail(diagnostics, "{s} is given twice", .{flag});
        given[field_index] = true;
        if (index + 1 >= arguments.len) return fail(diagnostics, "{s} needs a value", .{flag});
        const text = arguments[index + 1];
        inline for (fields.field_names, fields.field_types, 0..) |name, Field, field_position| {
            if (field_position == field_index) {
                @field(params, name) = parseValue(Field, text) catch
                    return fail(diagnostics, "{s} '{s}' is not {s}", .{ flag, text, comptime describe(Field) });
            }
        }
    }
    if (comptime hasHost(Params)) {
        if (!given[fieldIndex(Params, "host").?]) params.host = try hostFrom(@FieldType(Params, "host"), hostname, diagnostics);
    }
    return params;
}

/// Whether `Params` has a `host` field that kosm fills from the hostname (D56).
pub fn hasHost(comptime Params: type) bool {
    if (!@hasField(Params, "host")) return false;
    return @typeInfo(Unwrapped(@FieldType(Params, "host"))) == .@"enum";
}

fn checkParams(comptime Params: type) void {
    for (reserved_names) |reserved| {
        if (@hasField(Params, reserved))
            @compileError(@typeName(Params) ++ ": a parameter cannot be named '" ++ reserved ++ "'; kosm apply takes --" ++ reserved ++ " itself");
    }
}

fn fieldIndex(comptime Params: type, flag_name: []const u8) ?usize {
    inline for (@typeInfo(Params).@"struct".field_names, 0..) |name, index| {
        if (sameName(name, flag_name)) return index;
    }
    return null;
}

/// `border-size` names the field `border_size`.
fn sameName(field_name: []const u8, flag_name: []const u8) bool {
    if (field_name.len != flag_name.len) return false;
    for (field_name, flag_name) |field_character, flag_character| {
        const normalized = if (flag_character == '-') '_' else flag_character;
        if (field_character != normalized) return false;
    }
    return true;
}

fn hostFrom(comptime Host: type, hostname: []const u8, diagnostics: *kosm.Diagnostics) Error!Host {
    const Enum = Unwrapped(Host);
    return std.meta.stringToEnum(Enum, hostname) orelse
        fail(diagnostics, "the hostname '{s}' is not one of {s} ({s})", .{ hostname, @typeName(Enum), comptime enumList(Enum) });
}

/// Reads one value of `T` from text: what a flag or `--set` value may be (D19, D55).
pub fn parseValue(comptime T: type, text: []const u8) !T {
    if (T == kosm.Color) return kosm.Color.parse(text);
    if (T == kosm.ColorChoice) return kosm.ColorChoice.parse(text);
    if (T == []const u8) return text;
    return switch (@typeInfo(T)) {
        .optional => |optional| try parseValue(optional.child, text),
        .bool => if (std.mem.eql(u8, text, "true")) true else if (std.mem.eql(u8, text, "false")) false else error.InvalidBool,
        .int => try std.fmt.parseInt(T, text, 10),
        .float => blk: {
            const number = try std.fmt.parseFloat(T, text);
            if (!std.math.isFinite(number)) return error.InvalidFloat;
            break :blk number;
        },
        .@"enum" => std.meta.stringToEnum(T, text) orelse error.InvalidEnum,
        else => @compileError("kosmos parameter type " ++ @typeName(T) ++ " cannot be read from the command line; use a bool, number, enum, string or color"),
    };
}

/// What a value of `T` looks like, for "--x 'y' is not ...".
pub fn describe(comptime T: type) []const u8 {
    if (T == kosm.Color) return "a color (#rrggbb, rgb(...), hsl(...) or oklch(...))";
    if (T == kosm.ColorChoice) return "a color (#rrggbb, rgb(...), hsl(...) or oklch(...)) or a hue (" ++ enumList(kosm.Palette.Hue) ++ ")";
    if (T == []const u8) return "text";
    return switch (@typeInfo(T)) {
        .optional => |optional| describe(optional.child),
        .bool => "true or false",
        .int => "an integer that fits " ++ @typeName(T),
        .float => "a number",
        .@"enum" => "one of " ++ enumList(T),
        else => @typeName(T),
    };
}

/// Whether `parseValue` reads a `T` (not counting optionals): a color, text, bool, number or enum.
pub fn isParseable(comptime T: type) bool {
    if (T == kosm.Color or T == kosm.ColorChoice or T == []const u8) return true;
    return switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum" => true,
        else => false,
    };
}

fn Unwrapped(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |optional| optional.child,
        else => T,
    };
}

fn flagList(comptime Params: type) []const u8 {
    comptime var list: []const u8 = "";
    inline for (@typeInfo(Params).@"struct".field_names, 0..) |name, index| {
        list = list ++ (if (index == 0) "" else ", ") ++ "--" ++ dashed(name);
    }
    return list;
}

fn dashed(comptime name: []const u8) []const u8 {
    comptime var result: [name.len]u8 = name[0..name.len].*;
    for (&result) |*character| {
        if (character.* == '_') character.* = '-';
    }
    const final = result;
    return &final;
}

fn enumList(comptime Enum: type) []const u8 {
    comptime var list: []const u8 = "";
    inline for (@typeInfo(Enum).@"enum".field_names, 0..) |name, index| {
        list = list ++ (if (index == 0) "" else ", ") ++ name;
    }
    return list;
}

fn fail(diagnostics: *kosm.Diagnostics, comptime format: []const u8, arguments: anytype) Error {
    diagnostics.set("", "", format, arguments);
    return error.InvalidParams;
}

const testing = std.testing;

const TestHost = enum { nous, egregoros };

const TestParams = struct {
    blur: ?bool = null,
    border_size: u16 = 2,
    opacity: f32 = 1,
    mode: kosm.Mode = .dark,
    font: []const u8 = "Iosevka",
    background: ?kosm.Color = null,
    accent: kosm.ColorChoice = .{ .hue = .cyan },
};

const HostParams = struct {
    host: TestHost = .nous,
    blur: bool = true,
};

fn expectFailure(comptime Params: type, arguments: []const []const u8, expected_message: []const u8) !void {
    var diagnostics: kosm.Diagnostics = .{};
    try testing.expectError(error.InvalidParams, parse(Params, arguments, "nous", &diagnostics));
    try testing.expectEqualStrings(expected_message, diagnostics.message());
}

test "flags of every type fill Params, and the rest keep their defaults" {
    var diagnostics: kosm.Diagnostics = .{};
    const params = try parse(TestParams, &.{
        "--blur",        "false",
        "--border-size", "4",
        "--mode",        "light",
        "--background",  "rgb(16, 40, 64)",
        "--accent",      "sky",
    }, "nous", &diagnostics);
    try testing.expectEqual(false, params.blur.?);
    try testing.expectEqual(4, params.border_size);
    try testing.expectEqual(1, params.opacity);
    try testing.expectEqual(.light, params.mode);
    try testing.expectEqualStrings("Iosevka", params.font);
    try testing.expectEqualStrings("#102840", params.background.?.hex().slice());
    try testing.expectEqual(kosm.Palette.Hue.sky, params.accent.hue);
}

test "the field spelling of a flag works too, and colors take hex" {
    var diagnostics: kosm.Diagnostics = .{};
    const params = try parse(TestParams, &.{ "--border_size", "3", "--accent", "#ff0000", "--opacity", "0.5", "--font", "Fira Code" }, "nous", &diagnostics);
    try testing.expectEqual(3, params.border_size);
    try testing.expectEqualStrings("#ff0000", params.accent.color.hex().slice());
    try testing.expectEqual(0.5, params.opacity);
    try testing.expectEqualStrings("Fira Code", params.font);
}

test "bad flags name the flag and what it expects" {
    try expectFailure(TestParams, &.{ "--blur", "yes" }, "--blur 'yes' is not true or false");
    try expectFailure(TestParams, &.{ "--border-size", "-1" }, "--border-size '-1' is not an integer that fits u16");
    try expectFailure(TestParams, &.{ "--opacity", "inf" }, "--opacity 'inf' is not a number");
    try expectFailure(TestParams, &.{ "--mode", "dim" }, "--mode 'dim' is not one of dark, light");
    try expectFailure(TestParams, &.{ "--background", "sky" }, "--background 'sky' is not a color (#rrggbb, rgb(...), hsl(...) or oklch(...))");
    try expectFailure(TestParams, &.{ "--accent", "skyy" }, "--accent 'skyy' is not a color (#rrggbb, rgb(...), hsl(...) or oklch(...)) or a hue (red, orange, yellow, lime, green, teal, cyan, sky, blue, purple, magenta, pink)");
}

test "unknown, repeated, valueless and stray arguments are errors" {
    try expectFailure(TestParams, &.{ "--glow", "1" }, "'--glow' is not a parameter; parameters are --blur, --border-size, --opacity, --mode, --font, --background, --accent");
    try expectFailure(TestParams, &.{ "--blur", "true", "--blur", "false" }, "--blur is given twice");
    try expectFailure(TestParams, &.{"--blur"}, "--blur needs a value");
    try expectFailure(TestParams, &.{"blur"}, "expected --<parameter> <value>, got 'blur'");
    try expectFailure(struct {}, &.{ "--blur", "true" }, "it takes no parameters, got '--blur'");
}

test "host comes from the hostname unless given as a flag" {
    var diagnostics: kosm.Diagnostics = .{};
    const from_hostname = try parse(HostParams, &.{}, "egregoros", &diagnostics);
    try testing.expectEqual(.egregoros, from_hostname.host);
    const from_flag = try parse(HostParams, &.{ "--host", "nous" }, "unknown-machine", &diagnostics);
    try testing.expectEqual(.nous, from_flag.host);
    try testing.expectError(error.InvalidParams, parse(HostParams, &.{}, "laptop", &diagnostics));
    try testing.expect(std.mem.startsWith(u8, diagnostics.message(), "the hostname 'laptop' is not one of "));
    try testing.expect(std.mem.endsWith(u8, diagnostics.message(), "TestHost (nous, egregoros)"));
}

test "a host field that is not an enum is an ordinary parameter" {
    var diagnostics: kosm.Diagnostics = .{};
    const params = try parse(struct { host: []const u8 = "" }, &.{}, "nous", &diagnostics);
    try testing.expectEqualStrings("", params.host);
}
