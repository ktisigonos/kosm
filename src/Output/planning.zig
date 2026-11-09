//! What `Output` and `Selection` share for planning edits and reporting failures.
//! Kosm's own; apps never call these.

const std = @import("std");
const Output = @import("../Output.zig");
const Plan = @import("../Plan.zig");
const Color = @import("../Color.zig");
const ClippedColors = @import("../ClippedColors.zig");

/// Plans `edit` in `file`, naming the app already writing those bytes when it clashes.
pub fn addEdit(output: *Output, file: *Plan.File, edit: Plan.Edit) Output.Error!void {
    output.plan.addEdit(file, edit) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.EditsOverlap => {
            const other = file.clash(edit).?;
            return switch (other.target) {
                .whole_file => fail(output, error.EditsOverlap, file.display_path, "app '{s}' writes this whole file; two apps cannot write the same bytes", .{other.owner}),
                .block => |id| fail(output, error.EditsOverlap, file.display_path, "app '{s}' writes block '{s}' of this file; two apps cannot write the same bytes", .{ other.owner, id }),
                .value => fail(output, error.EditsOverlap, file.display_path, "app '{s}' already writes the value on line {d} of this file; the same bytes cannot be written twice", .{ other.owner, lineOf(file.current(), other.start) }),
            };
        },
    };
}

/// Reports a file that could not be read.
pub fn failRead(output: *Output, file: []const u8, err: Plan.LoadError) Output.Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return fail(output, error.ReadFailed, file, "cannot read it: {s}", .{@errorName(err)});
}

/// Records the failure for the app being applied and returns `err`.
pub fn fail(output: *Output, err: Output.Error, file: []const u8, comptime format: []const u8, arguments: anytype) Output.Error {
    output.diagnostics.set(output.app, file, format, arguments);
    return err;
}

/// Warns once per color that printing `file` clipped to the gamut. `about` names
/// what was written (`path 'general.border'`) or is empty; a template line takes its place.
pub fn warnClipped(output: *Output, file: []const u8, about: []const u8, clipped: *const ClippedColors) Output.Error!void {
    for (clipped.list()) |entry| {
        const where = if (entry.line != 0)
            try output.allocator.print("template line {d}: ", .{entry.line})
        else if (about.len != 0)
            try output.allocator.print("{s}: ", .{about})
        else
            "";
        const times = if (entry.count > 1) try output.allocator.print(" ({d} times)", .{entry.count}) else "";
        const printed = if (entry.color.alpha == 1) entry.color.hex() else entry.color.hex8();
        try output.warnings.add(output.app, file, "{s}color {f} is outside sRGB and is clipped to {s}{s}", .{ where, Oklch{ .color = entry.color }, printed.slice(), times });
    }
    if (clipped.uncounted != 0)
        try output.warnings.add(output.app, file, "{d} more colors outside sRGB are clipped", .{clipped.uncounted});
}

/// A color as `oklch(0.9 0.4 140)`, rounded for reading, with `/ alpha` when not opaque.
const Oklch = struct {
    color: Color,

    const decimals = 3;

    pub fn format(oklch: Oklch, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const color = oklch.color;
        try writer.print("oklch({d} {d} {d}", .{ Color.roundDecimals(color.lightness, decimals), Color.roundDecimals(color.chroma, decimals), Color.roundDecimals(color.hue, decimals) });
        if (color.alpha != 1) try writer.print(" / {d}", .{Color.roundDecimals(color.alpha, decimals)});
        try writer.writeByte(')');
    }
};

/// The 1-based line holding byte `offset` of `text`.
pub fn lineOf(text: []const u8, offset: usize) usize {
    return std.mem.countScalar(u8, text[0..@min(offset, text.len)], '\n') + 1;
}
