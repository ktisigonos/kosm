//! What shell integration does (`shell-integration-features`). Null flags keep ghostty's defaults.

const ShellIntegrationFeatures = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Use a bar cursor at the prompt. ghostty's default: on.
cursor: ?bool = null,
/// Wrap sudo to keep the terminfo. ghostty's default: off.
sudo: ?bool = null,
/// Set the window title. ghostty's default: on.
title: ?bool = null,
/// Pass a compatible TERM and terminal variables over SSH. ghostty's default: off.
ssh_env: ?bool = null,
/// Install ghostty's terminfo on SSH hosts. ghostty's default: off.
ssh_terminfo: ?bool = null,
/// Add ghostty's binary directory to PATH. ghostty's default: on.
path: ?bool = null,

/// Writes the set flags the way ghostty spells them (`cursor,no-path`).
pub fn format(flags: ShellIntegrationFeatures, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
