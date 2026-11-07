//! The interface number shared by the `kosm` command line and the runner it builds (D98). The
//! runner comes from the config's kosm, which may be another version than the command line.

const std = @import("std");

/// Bumped whenever the command line and the runner change how they talk to each other
/// (arguments, environment, output the command line reads).
pub const version: u32 = 1;

/// The environment variable the command line passes its `version` to the runner in.
pub const environment_variable = "KOSM_INTERFACE";

/// Prints an error naming both numbers to `stderr` and returns false when `environ` holds
/// another interface number than this build's. Without the variable (the runner started by
/// hand) there is nothing to check.
pub fn check(environ: *const std.process.Environ.Map, stderr: *std.Io.Writer) std.Io.Writer.Error!bool {
    const given = environ.get(environment_variable) orelse return true;
    const given_version = std.fmt.parseInt(u32, given, 10) catch null;
    if (given_version == version) return true;
    try stderr.print(
        "error: the kosm command speaks interface {s}, but the kosm this config builds with speaks interface {d}; " ++
            "run `kosm update kosm`, or install the kosm the config uses (D98)\n",
        .{ given, version },
    );
    return false;
}

const testing = std.testing;

test "only another interface number is an error, naming both" {
    var environ: std.process.Environ.Map = .init(testing.allocator);
    defer environ.deinit();
    var stderr: std.Io.Writer.Allocating = .init(testing.allocator);
    defer stderr.deinit();

    try testing.expect(try check(&environ, &stderr.writer));
    try environ.put(environment_variable, std.fmt.comptimePrint("{d}", .{version}));
    try testing.expect(try check(&environ, &stderr.writer));
    try testing.expectEqualStrings("", stderr.written());

    try environ.put(environment_variable, "999");
    try testing.expect(!try check(&environ, &stderr.writer));
    try testing.expect(std.mem.startsWith(u8, stderr.written(), "error: the kosm command speaks interface 999, but the kosm this config builds with speaks interface 1;"));
}
