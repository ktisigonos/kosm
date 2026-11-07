//! The types kitty options take. A union writes its tag (`none`) or its payload (a color);
//! a type with a `write` method builds a joined value whose numbers, booleans and colors follow
//! the file's format (D89), and a type with a `format` method writes plain text. Enum tags are written with dashes
//! (`thin_sparse` -> `thin-sparse`) unless the enum declares `underscored`.

const std = @import("std");
const kosm = @import("kosm");
const Joined = @import("Joined.zig");

pub const Font = @import("values/Font.zig");
pub const FontAxis = @import("values/FontAxis.zig");
pub const CodepointRange = @import("values/CodepointRange.zig");
pub const SymbolMap = @import("values/SymbolMap.zig");
pub const NarrowSymbols = @import("values/NarrowSymbols.zig");
pub const FontFeatures = @import("values/FontFeatures.zig");
pub const ModifyFont = @import("values/ModifyFont.zig");
pub const BoxDrawingScale = @import("values/BoxDrawingScale.zig");
pub const CompositionCurve = @import("values/CompositionCurve.zig");
pub const Timing = @import("values/Timing.zig");
pub const CubicBezier = @import("values/CubicBezier.zig");
pub const Steps = @import("values/Steps.zig");
pub const TrailDecay = @import("values/TrailDecay.zig");
pub const TrailThreshold = @import("values/TrailThreshold.zig");
pub const MouseHideWait = @import("values/MouseHideWait.zig");
pub const PasteActions = @import("values/PasteActions.zig");
pub const DraggingPointer = @import("values/DraggingPointer.zig");
pub const Edges = @import("values/Edges.zig");
pub const LogoScale = @import("values/LogoScale.zig");
pub const ResizeDebounce = @import("values/ResizeDebounce.zig");
pub const ConfirmClose = @import("values/ConfirmClose.zig");
pub const TabBarMarginHeight = @import("values/TabBarMarginHeight.zig");
pub const TransparentColor = @import("values/TransparentColor.zig");
pub const RemoteControlPassword = @import("values/RemoteControlPassword.zig");
pub const Env = @import("values/Env.zig");
pub const ClipboardControl = @import("values/ClipboardControl.zig");
pub const ShellIntegration = @import("values/ShellIntegration.zig");
pub const CloneSourceStrategies = @import("values/CloneSourceStrategies.zig");
pub const NotifyOnCmdFinish = @import("values/NotifyOnCmdFinish.zig");
pub const MenuMap = @import("values/MenuMap.zig");
pub const Modifiers = @import("values/Modifiers.zig");
pub const ModifierRemap = @import("values/ModifierRemap.zig");
pub const Alias = @import("values/Alias.zig");

/// A color, or `none`, whose meaning each option explains.
pub const ColorOrNone = union(enum) { color: kosm.Color, none };

/// A color, or the color of the cell's background.
pub const ColorOrBackground = union(enum) { color: kosm.Color, background };

/// A color, or one of the terminal's own colors.
pub const ScrollbarColor = union(enum) {
    color: kosm.Color,
    foreground,
    selection_background,

    pub const underscored = true;
};

/// The system's titlebar colors, the active window's background, or a color.
pub const TitlebarColor = union(enum) { system, background, color: kosm.Color };

/// Like `TitlebarColor`, plus macOS's explicit light and dark titlebars.
pub const MacosTitlebarColor = union(enum) { system, light, dark, background, color: kosm.Color };

/// A face picked automatically from `font_family`, or a font of its own.
pub const FontOrAuto = union(enum) { auto, font: Font };

/// How glyphs are composited onto the background.
pub const TextComposition = union(enum) { platform, legacy, curve: CompositionCurve };

/// Not copying, copying to the clipboard, or copying to a named private buffer.
pub const CopyOnSelect = union(enum) { no, clipboard, buffer: []const u8 };

/// Truncate tab titles (`no`), wrap them at the tab bar's width (`yes`) or at a number of cells.
pub const TitleWrap = union(enum) { no, yes, cells: u32 };

/// A length in points, kitty's default unit, or in pixels.
pub const Length = union(enum) {
    points: f64,
    pixels: f64,

    /// Writes the value the way kitty.conf spells it, numbers in the file's format.
    pub fn write(length: Length, joined: *Joined) Joined.Error!void {
        switch (length) {
            .points => |points| {
                try joined.float(points);
                try joined.writer().writeAll("pt");
            },
            .pixels => |pixels| {
                try joined.float(pixels);
                try joined.writer().writeAll("px");
            },
        }
    }
};

/// The underline gap: a fraction of the underline's thickness, or a length.
pub const UnderlineExclusion = union(enum) {
    fraction: f64,
    points: f64,
    pixels: f64,

    /// Writes the value the way kitty.conf spells it, numbers in the file's format.
    pub fn write(exclusion: UnderlineExclusion, joined: *Joined) Joined.Error!void {
        switch (exclusion) {
            .fraction => |fraction| try joined.float(fraction),
            .points => |points| {
                try joined.float(points);
                try joined.writer().writeAll("pt");
            },
            .pixels => |pixels| {
                try joined.float(pixels);
                try joined.writer().writeAll("px");
            },
        }
    }
};

/// A minimum contrast ratio (0..21) or a minimum luminance difference in percent (0..100).
pub const ContrastThreshold = union(enum) {
    ratio: f64,
    percent: f64,

    /// Writes the value the way kitty.conf spells it, numbers in the file's format.
    pub fn write(threshold: ContrastThreshold, joined: *Joined) Joined.Error!void {
        switch (threshold) {
            .ratio => |ratio| {
                try joined.float(ratio);
                try joined.writer().writeAll(" ratio");
            },
            .percent => |percent| {
                try joined.float(percent);
                try joined.writer().writeAll("%");
            },
        }
    }
};

/// A window size in pixels or in cells.
pub const WindowSize = union(enum) {
    pixels: u32,
    cells: u32,

    /// Writes the value the way kitty.conf spells it.
    pub fn format(size: WindowSize, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (size) {
            .pixels => |pixels| try writer.print("{d}", .{pixels}),
            .cells => |cells| try writer.print("{d}c", .{cells}),
        }
    }
};

/// A change in points, pixels or percent of the original value.
pub const FontAmount = union(enum) {
    points: f64,
    pixels: f64,
    percent: f64,

    /// Writes the value the way kitty.conf spells it, numbers in the file's format.
    pub fn write(amount: FontAmount, joined: *Joined) Joined.Error!void {
        switch (amount) {
            .points => |points| try joined.float(points),
            .pixels => |pixels| {
                try joined.float(pixels);
                try joined.writer().writeAll("px");
            },
            .percent => |percent| {
                try joined.float(percent);
                try joined.writer().writeAll("%");
            },
        }
    }
};

/// A CSS easing function, as kitty's animations take them.
pub const Easing = union(enum) {
    linear,
    ease,
    ease_in,
    ease_out,
    ease_in_out,
    step_start,
    step_end,
    cubic_bezier: CubicBezier,
    steps: Steps,

    /// Writes the value the way kitty.conf spells it, numbers in the file's format.
    pub fn write(easing: Easing, joined: *Joined) Joined.Error!void {
        switch (easing) {
            .cubic_bezier => |curve| try curve.write(joined),
            .steps => |steps| try steps.format(joined.writer()),
            else => try writeTag(joined.writer(), @tagName(easing), false),
        }
    }
};

/// Where something sits in a window.
pub const Position = enum { top_left, top, top_right, left, center, right, bottom_left, bottom, bottom_right };

/// A window layout; `all` enables every layout.
pub const Layout = enum { all, stack, tall, fat, vertical, horizontal, grid, splits };

/// A tab title's font style.
pub const FontStyle = enum { normal, bold, italic, bold_italic };

/// One modifier key.
pub const Modifier = enum { shift, alt, ctrl, super, hyper, meta };

/// A mouse pointer shape.
pub const PointerShape = enum {
    arrow,
    beam,
    text,
    pointer,
    hand,
    help,
    wait,
    progress,
    crosshair,
    cell,
    vertical_text,
    move,
    e_resize,
    ne_resize,
    nw_resize,
    n_resize,
    se_resize,
    sw_resize,
    s_resize,
    w_resize,
    ew_resize,
    ns_resize,
    nesw_resize,
    nwse_resize,
    zoom_in,
    zoom_out,
    alias,
    copy,
    not_allowed,
    no_drop,
    grab,
    grabbing,
};

/// Writes an enum or union tag the way kitty spells it: dashes, unless `underscored`.
pub fn writeTag(writer: *std.Io.Writer, name: []const u8, underscored: bool) std.Io.Writer.Error!void {
    if (underscored) return writer.writeAll(name);
    for (name) |character| try writer.writeByte(if (character == '_') '-' else character);
}

/// Writes the names of the `true` fields of a struct of bools, joined by `separator`;
/// returns whether any was written.
pub fn writeFlags(writer: *std.Io.Writer, flags: anytype, separator: []const u8, underscored: bool) std.Io.Writer.Error!bool {
    var written = false;
    inline for (@typeInfo(@TypeOf(flags)).@"struct".field_names) |name| {
        if (@field(flags, name)) {
            if (written) try writer.writeAll(separator);
            try writeTag(writer, name, underscored);
            written = true;
        }
    }
    return written;
}

/// Writes `text` in double quotes, escaping what kitty's shell-like splitting would eat.
pub fn writeQuoted(writer: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    try writer.writeByte('"');
    try writeEscaped(writer, text);
    try writer.writeByte('"');
}

/// Writes `text` with `"` and `\\` escaped, for use inside double quotes.
pub fn writeEscaped(writer: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    for (text) |character| {
        if (character == '"' or character == '\\') try writer.writeByte('\\');
        try writer.writeByte(character);
    }
}
