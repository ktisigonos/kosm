//! What kitty does with pasted or dropped text; none set writes `no-op`.

const PasteActions = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Quote a pasted URL at a shell prompt.
quote_urls_at_prompt: bool = false,
/// Replace dangerous control codes without asking.
replace_dangerous_control_codes: bool = false,
/// Replace newlines without asking.
replace_newline: bool = false,
/// Ask before pasting text with control codes.
confirm: bool = false,
/// Ask before pasting more than 16KB.
confirm_if_large: bool = false,
/// Run `filter_paste()` from `paste-actions.py` on the text.
filter: bool = false,

/// Writes the value the way kitty.conf spells it.
pub fn format(actions: PasteActions, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (!try values.writeFlags(writer, actions, ",", false)) try writer.writeAll("no-op");
}
