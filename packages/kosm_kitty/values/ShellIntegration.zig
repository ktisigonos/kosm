//! Shell integration and the features to leave out of it.

const ShellIntegration = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Turn shell integration off completely; the fields below are then ignored.
disabled: bool = false,
/// Do not change the shell's startup files.
no_rc: bool = false,
/// Do not change the cursor shape at the prompt.
no_cursor: bool = false,
/// Do not set the window title.
no_title: bool = false,
/// Do not report the working directory.
no_cwd: bool = false,
/// Do not mark prompts.
no_prompt_mark: bool = false,
/// Do not add completion for the kitty command.
no_complete: bool = false,
/// Do not make kitty's terminfo work through sudo.
no_sudo: bool = false,

/// Writes the value the way kitty.conf spells it.
pub fn format(integration: ShellIntegration, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (integration.disabled) return writer.writeAll("disabled");
    var features = integration;
    features.disabled = false;
    if (!try values.writeFlags(writer, features, " ", false)) try writer.writeAll("enabled");
}
