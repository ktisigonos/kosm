//! What completes a kosmos' own arguments on the command line: its parameters as flags, and
//! every path `--set` takes. The command line asks a runner for them through
//! `interface.completions_variable` instead of applying.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const params = @import("params.zig");

/// One thing the shell may offer: its text and what it is.
pub const Candidate = struct {
    text: []const u8,
    description: []const u8,
};

/// What `write` puts before a parameter's flag and a `--set` path, so the command line can
/// tell them apart.
pub const parameter_kind = "param";
pub const set_kind = "set";

/// One line per candidate of `kosmos`, a kosmos function: `param<TAB>--blur<TAB>true or false`
/// for each parameter, then `set<TAB>kitty.fonts.font_size<TAB>a number` for each value
/// `--set` can reach.
pub fn write(writer: *std.Io.Writer, comptime kosmos: anytype) std.Io.Writer.Error!void {
    const function = @typeInfo(@TypeOf(kosmos)).@"fn";
    if (function.param_types.len == 1) {
        for (comptime parameters(function.param_types[0].?)) |candidate| try writer.print("{s}\t{s}\t{s}\n", .{ parameter_kind, candidate.text, candidate.description });
    }
    const Tree = discovery.Payload(function.return_type.?);
    for (comptime setPaths(Tree, "")) |candidate| try writer.print("{s}\t{s}\t{s}\n", .{ set_kind, candidate.text, candidate.description });
}

/// Every field of `Params` as the flag that sets it, spelled with dashes (`--border-size`).
pub fn parameters(comptime Params: type) []const Candidate {
    comptime var found: []const Candidate = &.{};
    const fields = @typeInfo(Params).@"struct";
    inline for (fields.field_names, fields.field_types) |name, Field| {
        comptime var flag: [name.len]u8 = name[0..name.len].*;
        std.mem.replaceScalar(u8, &flag, '_', '-');
        const spelled = flag;
        found = found ++ .{Candidate{ .text = "--" ++ &spelled, .description = params.describe(Field) }};
    }
    const final = found[0..found.len].*;
    return &final;
}

/// Every value below a `T` that `--set` can assign, as its path from `prefix`, walking structs
/// and optionals the way `--set` does.
pub fn setPaths(comptime T: type, comptime prefix: []const u8) []const Candidate {
    @setEvalBranchQuota(discovery.branch_quota);
    const Unwrapped = switch (@typeInfo(T)) {
        .optional => |optional| optional.child,
        else => T,
    };
    if (params.isParseable(Unwrapped)) return &.{.{ .text = prefix, .description = params.describe(Unwrapped) }};
    if (@typeInfo(Unwrapped) != .@"struct") return &.{};
    comptime var found: []const Candidate = &.{};
    const fields = @typeInfo(Unwrapped).@"struct";
    inline for (fields.field_names, fields.field_types, fields.field_attrs) |name, Field, attributes| {
        if (attributes.@"comptime") continue;
        found = found ++ setPaths(Field, if (prefix.len == 0) name else prefix ++ "." ++ name);
    }
    const final = found[0..found.len].*;
    return &final;
}

const testing = std.testing;

const TestApp = struct {
    opacity: f32 = 1,
    border: ?kosm.Color = null,
    fonts: struct { font_size: ?u16 = null, family: []const u8 = "" } = .{},
    cursor: ?struct { blink: bool = false } = null,
    pointer: *const u8 = &test_byte,

    pub fn apply(self: TestApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }
};

const test_byte: u8 = 0;

const TestKosmos = struct {
    const Params = struct { blur: bool = true, border_size: u8 = 2, accent: kosm.ColorChoice = .{ .hue = .cyan } };
    const Tree = struct { kitty: TestApp, bar: ?TestApp };

    fn kosmos(given: Params) !Tree {
        _ = given;
        return .{ .kitty = .{}, .bar = null };
    }

    fn plain() Tree {
        return .{ .kitty = .{}, .bar = null };
    }
};

test "parameters become dashed flags and every settable value a path, each saying what it takes" {
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try write(&text.writer, TestKosmos.kosmos);
    const written = text.written();
    try testing.expectStringStartsWith(written, "param\t--blur\ttrue or false\nparam\t--border-size\tan integer that fits u8\nparam\t--accent\ta color (");
    for ([_][]const u8{
        "set\tkitty.opacity\ta number\n",
        "set\tkitty.border\ta color (#rrggbb, rgb(...), hsl(...) or oklch(...))\n",
        "set\tkitty.fonts.font_size\tan integer that fits u16\n",
        "set\tkitty.fonts.family\ttext\n",
        "set\tkitty.cursor.blink\ttrue or false\n",
        "set\tbar.opacity\ta number\n",
    }) |expected| try testing.expect(std.mem.find(u8, written, expected) != null);
    // A pointer can't be set from the command line, so it is no path.
    try testing.expect(std.mem.find(u8, written, "pointer") == null);
}

test "a kosmos without parameters completes only paths" {
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try write(&text.writer, TestKosmos.plain);
    try testing.expect(std.mem.find(u8, text.written(), "param\t") == null);
    try testing.expectStringStartsWith(text.written(), "set\tkitty.opacity\ta number\n");
}
