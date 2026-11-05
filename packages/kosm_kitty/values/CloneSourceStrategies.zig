//! What `clone-in-kitty` sources in the cloned window.

const CloneSourceStrategies = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Source `$VIRTUAL_ENV/bin/activate`.
venv: bool = false,
/// Run `conda activate $CONDA_DEFAULT_ENV`.
conda: bool = false,
/// Run the contents of `KITTY_CLONE_SOURCE_CODE`, or source `KITTY_CLONE_SOURCE_PATH`.
env_var: bool = false,
/// Source the file at `KITTY_CLONE_SOURCE_PATH`.
path: bool = false,

/// Writes the value the way kitty.conf spells it.
pub fn format(strategies: CloneSourceStrategies, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    _ = try values.writeFlags(writer, strategies, ",", true);
}
