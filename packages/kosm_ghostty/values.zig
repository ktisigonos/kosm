//! The types ghostty options take. A union writes its tag (`cell_foreground`) or its payload (a
//! color); a `boolean` payload writes `true` or `false`. A type with a `write` method builds a
//! joined value whose numbers, booleans and colors follow the file's format (D89), and a type
//! with a `format` method writes plain text. Enum tags are written with dashes
//! (`linear_corrected` -> `linear-corrected`) unless the enum declares `underscored`.

const std = @import("std");
const kosm = @import("kosm");
const Joined = @import("Joined.zig");

pub const Duration = @import("values/Duration.zig");
pub const FontVariation = @import("values/FontVariation.zig");
pub const CodepointRange = @import("values/CodepointRange.zig");
pub const CodepointMap = @import("values/CodepointMap.zig");
pub const ClipboardCodepointMap = @import("values/ClipboardCodepointMap.zig");
pub const LightDark = @import("values/LightDark.zig");
pub const Padding = @import("values/Padding.zig");
pub const MouseScrollMultiplier = @import("values/MouseScrollMultiplier.zig");
pub const QuickTerminalSize = @import("values/QuickTerminalSize.zig");
pub const Env = @import("values/Env.zig");
pub const KeyRemap = @import("values/KeyRemap.zig");
pub const Keybind = @import("values/Keybind.zig");
pub const Action = @import("values/action.zig").Action;
pub const ResizeSplit = @import("values/ResizeSplit.zig");
pub const WriteFile = @import("values/WriteFile.zig");
pub const CommandPaletteEntry = @import("values/CommandPaletteEntry.zig");
pub const SyntheticStyle = @import("values/SyntheticStyle.zig");
pub const FontShapingBreak = @import("values/FontShapingBreak.zig");
pub const FreetypeLoadFlags = @import("values/FreetypeLoadFlags.zig");
pub const ScrollToBottom = @import("values/ScrollToBottom.zig");
pub const SplitPreserveZoom = @import("values/SplitPreserveZoom.zig");
pub const NotifyOnCommandFinishAction = @import("values/NotifyOnCommandFinishAction.zig");
pub const ShellIntegrationFeatures = @import("values/ShellIntegrationFeatures.zig");
pub const ChecksumExtension = @import("values/ChecksumExtension.zig");
pub const BellFeatures = @import("values/BellFeatures.zig");
pub const AppNotifications = @import("values/AppNotifications.zig");

/// A color, or the color of the cell's own text or background.
pub const CellColor = union(enum) { color: kosm.Color, cell_foreground, cell_background };

/// A color for all bold text, or the bright palette color of the text's own color.
pub const BoldColor = union(enum) { color: kosm.Color, bright };

/// The amount to count before dropping more: a number (lines or bytes), or no limit.
pub const Limit = union(enum) { amount: u64, unlimited };

/// An absolute path (or one starting with `~/`), the home directory, or the launching process's.
pub const WorkingDirectory = union(enum) { path: []const u8, home, inherit };

/// A theme by name or absolute path, or one theme for light mode and one for dark.
pub const Theme = union(enum) { name: []const u8, light_dark: LightDark };

/// Whether to blur the background, a blur intensity (only on and off on Linux), or a macOS 26 glass effect.
pub const BackgroundBlur = union(enum) {
    boolean: bool,
    intensity: u32,
    macos_glass_regular,
    macos_glass_clear,
};

/// A font style name the font advertises (`Heavy`), or `disabled`, which writes `false` and
/// makes the regular style stand in for this one.
pub const FontStyle = union(enum) {
    name: []const u8,
    disabled,

    /// Writes the value the way ghostty spells it.
    pub fn format(style: FontStyle, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (style) {
            .name => |name| try writer.writeAll(name),
            .disabled => try writer.writeAll("false"),
        }
    }
};

/// Pixels to add (negative removes), or a percentage of the font's own value.
pub const Adjustment = union(enum) {
    pixels: i32,
    percent: f64,

    /// Writes the value the way ghostty spells it, numbers in the file's format.
    pub fn write(adjustment: Adjustment, joined: *Joined) Joined.Error!void {
        switch (adjustment) {
            .pixels => |pixels| try joined.writer().print("{d}", .{pixels}),
            .percent => |percent| {
                try joined.float(percent);
                try joined.writer().writeByte('%');
            },
        }
    }
};

/// Text ghostty reads as a Zig string literal sent to the terminal, or a file whose contents are sent.
pub const Input = union(enum) {
    raw: []const u8,
    path: []const u8,

    /// Writes the value the way ghostty spells it, escaping raw text.
    pub fn format(input: Input, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (input) {
            .raw => |text| try writer.print("raw:{f}", .{std.zig.fmtString(text)}),
            .path => |path| try writer.print("path:{s}", .{path}),
        }
    }
};

/// Writes a flag set (a struct of `?bool` fields) as ghostty's `name,no-other` list; null flags
/// are left out, so they keep ghostty's defaults.
pub fn writeFlags(flags: anytype, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var first = true;
    inline for (@typeInfo(@TypeOf(flags)).@"struct".field_names) |name| {
        if (@field(flags, name)) |enabled| {
            if (!first) try writer.writeByte(',');
            first = false;
            if (!enabled) try writer.writeAll("no-");
            try writeTag(writer, name, false);
        }
    }
}

/// Writes an enum tag, with dashes for underscores unless `underscored`.
pub fn writeTag(writer: *std.Io.Writer, name: []const u8, underscored: bool) std.Io.Writer.Error!void {
    for (name) |byte| try writer.writeByte(if (byte == '_' and !underscored) '-' else byte);
}

test {
    std.testing.refAllDecls(@This());
}
