//! The interface number shared by the `kosm` command line and the runner it builds. The
//! runner comes from the config's kosm, which may be another version than the command line.

const std = @import("std");

/// Bumped whenever the command line and the runner change how they talk to each other
/// (arguments, environment, output the command line reads).
pub const version: u32 = 9;

/// The environment variable the command line passes its `version` to the runner in.
pub const environment_variable = "KOSM_INTERFACE";

/// Set by the command line to make a program it built print what completes a command line
/// instead of doing its work: a runner prints its kosmos' parameters and `--set` paths and
/// applies nothing, and the lister prints every kosmos' name.
pub const completions_variable = "KOSM_COMPLETIONS";

/// Set by the command line to make a runner print the themes of the tree its kosmos builds,
/// for `kosm colors`, instead of planning and applying it.
pub const colors_variable = "KOSM_COLORS";

/// Set by the command line to make a runner check each app of the tree its kosmos builds, for
/// `kosm doctor`, printing one line per app instead of applying it. It plans the tree as an
/// apply would, writes nothing, and exits 1 when an app has a problem.
pub const doctor_variable = "KOSM_DOCTOR";

/// Set by the command line to the token it announced in the state directory's latest-apply
/// file when `kosm apply` started, so the apply typed last wins, not the one built last. A
/// runner without it announces one itself.
pub const apply_token_variable = "KOSM_APPLY_TOKEN";

/// Set by the command line to ask a kosmos' runner which runner applies it: the runner prints
/// `script_runner` when the kosmos builds on another kosmos, which only the runner of scripts
/// can build, and nothing otherwise, and applies nothing. The lister prints the name of every
/// such kosmos instead, one per line.
pub const runner_variable = "KOSM_RUNNER";

/// What a runner asked through `runner_variable` prints for a kosmos the runner of scripts
/// applies.
pub const script_runner = "scripts";

/// Given to the runner of scripts in place of a kosmos name, it prints every script kosmos in
/// the config and each variant it gives, `name<TAB>file` per line, and applies nothing.
pub const list_scripts_flag = "--list-scripts";

/// Given to the runner of scripts in place of a kosmos name, it prints every frontend it holds,
/// `name<TAB>module` per line ("lua<TAB>kosm_lua"), and applies nothing.
pub const list_frontends_flag = "--list-frontends";

/// Given to the runner of scripts in place of a kosmos name, before a frontend's name and a
/// kind (`--scaffold lua app`), it prints the extension the frontend's scripts get on the first
/// line, the package giving the frontend on the second, then the frontend's scaffold for that
/// kind, and applies nothing.
pub const scaffold_flag = "--scaffold";

/// Given to the lister before a frontend's name and the module giving it (`--frontend lua
/// kosm_lua`), it lists that frontend. The command line passes what `list_frontends_flag`
/// printed, since the lister holds no frontend.
pub const frontend_flag = "--frontend";

/// Given to the lister before a name and a file (`--script-kosmos minimal.light
/// kosmoi/minimal.lua`), it lists that kosmos too, after the other kosmoi of its file, unless
/// it lists it already. The command line passes what `list_scripts_flag` printed, since the
/// lister holds no frontend to ask a script for its variants.
pub const script_kosmos_flag = "--script-kosmos";

/// Prints an error naming both numbers to `stderr` and returns false when `environ` holds
/// another interface number than this build's. Without the variable (the runner started by
/// hand) there is nothing to check.
pub fn check(environ: *const std.process.Environ.Map, stderr: *std.Io.Writer) std.Io.Writer.Error!bool {
    const given = environ.get(environment_variable) orelse return true;
    const given_version = std.fmt.parseInt(u32, given, 10) catch null;
    if (given_version == version) return true;
    try stderr.print(
        "error: the kosm command speaks interface {s}, but the kosm this config builds with speaks interface {d}; " ++
            "run `kosm update kosm`, or install the kosm the config uses\n",
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
    try testing.expect(std.mem.startsWith(u8, stderr.written(), "error: the kosm command speaks interface 999, but the kosm this config builds with speaks interface " ++ std.fmt.comptimePrint("{d}", .{version}) ++ ";"));
}
