//! What `Output` and `Selection` share for planning edits and reporting failures.
//! Kosm's own; apps never call these.

const std = @import("std");
const Output = @import("../Output.zig");
const Plan = @import("../Plan.zig");

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

/// The 1-based line holding byte `offset` of `text`.
pub fn lineOf(text: []const u8, offset: usize) usize {
    return std.mem.countScalar(u8, text[0..@min(offset, text.len)], '\n') + 1;
}
