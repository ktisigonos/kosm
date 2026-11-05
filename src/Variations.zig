//! The shared color transforms every module builds from, grouped in families (D12-D16).

const Variations = @This();

const std = @import("std");
const Color = @import("Color.zig");
const Modifier = @import("Modifier.zig");
const Mode = @import("Theme.zig").Mode;

/// Absolute lightness steps.
lightness: Lightness,
/// More or less contrast against the background.
emphasis: Emphasis,
/// Interaction and window focus.
state: State,
/// Elevation.
surface: Surface,
/// Borders and separators.
line: Line,
/// A readable color on top of this one.
contrast: Contrast,
/// Low-alpha washes.
alpha: Alpha,

/// Absolute: ignores mode. Qt Light/Midlight/Dark/Shadow, Tailwind/Radix scales, ANSI bright.
pub const Lightness = struct {
    /// Default: lightness +0.3.
    lightest: Modifier,
    /// Default: lightness +0.2.
    lighter: Modifier,
    /// Default: lightness +0.1.
    light: Modifier,
    /// Default: lightness -0.1.
    dark: Modifier,
    /// Default: lightness -0.2.
    darker: Modifier,
    /// Default: lightness -0.3.
    darkest: Modifier,
    /// Terminal "bright" colors. Default: lightness +0.08, chroma +0.02.
    bright: Modifier,
};

/// Mode-aware: more or less contrast against the background.
/// Apple label hierarchy, Radix steps 11-12, GTK dim-label.
pub const Emphasis = struct {
    /// Default: 0.08 lightness away from the background.
    strong: Modifier,
    /// Default: 0.2 lightness toward the background, chroma -0.02.
    muted: Modifier,
    /// Default: 0.3 lightness toward the background, chroma -0.03.
    subtle: Modifier,
    /// Default: 0.4 lightness toward the background, chroma -0.04.
    faint: Modifier,
};

/// Mode-aware: interaction and window focus. CSS pseudo-classes, GTK states, Material state
/// layers, Fluent, JetBrains, Qt Inactive group / GTK :backdrop. No `active` (D14).
pub const State = struct {
    /// Default: 0.05 lightness away from the background.
    hovered: Modifier,
    /// Default: 0.09 lightness away from the background.
    pressed: Modifier,
    /// Default: 0.07 lightness away from the background.
    focused: Modifier,
    /// Default: 0.12 lightness away from the background.
    selected: Modifier,
    /// Default: 0.12 lightness away from the background.
    checked: Modifier,
    /// Default: 0.11 lightness away from the background.
    dragged: Modifier,
    /// Default: 0.08 lightness toward the background, chroma -0.03.
    visited: Modifier,
    /// Default: 0.25 lightness toward the background, chroma -0.1.
    disabled: Modifier,
    /// Default: 0.3 lightness toward the background, chroma -0.05.
    placeholder: Modifier,
    /// Unfocused window or widget. Default: 0.1 lightness toward the background, chroma -0.06.
    inactive: Modifier,
    /// Selected in an unfocused window. Null: `selected`, then `inactive`. Read it with
    /// `selectedInactive()` so changes to `selected` or `inactive` flow into it (D16).
    selected_inactive: ?Modifier = null,

    /// `selected_inactive` if set, otherwise `selected` then `inactive` as they are now.
    pub fn selectedInactive(state: State) Modifier {
        return state.selected_inactive orelse state.selected.then(state.inactive);
    }
};

/// Mode-aware elevation. GTK shade/card/popover, Material surface containers, Qt Shadow.
pub const Surface = struct {
    /// Default: 0.04 lightness toward the background.
    sunken: Modifier,
    /// Default: 0.04 lightness away from the background.
    raised: Modifier,
    /// Default: 0.08 lightness away from the background.
    overlay: Modifier,
    /// Dark in both modes. Default: 80% toward the palette's black, alpha 0.5.
    shadow: Modifier,
};

/// Mode-aware: libadwaita borders, Material outline / outlineVariant.
pub const Line = struct {
    /// Default: 0.12 lightness away from the background.
    border: Modifier,
    /// Default: 0.22 lightness away from the background.
    border_strong: Modifier,
    /// Default: 0.07 lightness away from the background.
    separator: Modifier,
};

/// Readable foreground on top of this color. Material onPrimary, libadwaita accent_fg_color.
pub const Contrast = struct {
    /// Default: the palette's black or white, whichever has the higher contrast ratio.
    on: Modifier,
    /// Default: `on`, mixed 30% back toward the color.
    on_muted: Modifier,
};

/// Low-alpha washes. Material state layers, editor selection / search highlights.
pub const Alpha = struct {
    /// Default: alpha 0.5.
    translucent: Modifier,
    /// Default: alpha 0.25.
    highlight: Modifier,
};

/// How far `contrast.on_muted` mixes back toward the color it sits on.
const on_muted_toward_original = 0.3;
/// Pure black, the shadow target until `Theme.from` swaps in the palette's black.
const default_shadow_color: Color = .{ .lightness = 0, .chroma = 0, .hue = 0 };

/// Every default (D12). In light mode the mode-aware families (emphasis, state, surface,
/// line) move the other way: "away from the background" darkens instead of lightening.
pub fn from(mode: Mode) Variations {
    const away: f64 = switch (mode) {
        .dark => 1,
        .light => -1,
    };
    return .{
        .lightness = .{
            .lightest = .{ .lightness = 0.3 },
            .lighter = .{ .lightness = 0.2 },
            .light = .{ .lightness = 0.1 },
            .dark = .{ .lightness = -0.1 },
            .darker = .{ .lightness = -0.2 },
            .darkest = .{ .lightness = -0.3 },
            .bright = .{ .lightness = 0.08, .chroma = 0.02 },
        },
        .emphasis = .{
            .strong = .{ .lightness = 0.08 * away },
            .muted = .{ .lightness = -0.2 * away, .chroma = -0.02 },
            .subtle = .{ .lightness = -0.3 * away, .chroma = -0.03 },
            .faint = .{ .lightness = -0.4 * away, .chroma = -0.04 },
        },
        .state = .{
            .hovered = .{ .lightness = 0.05 * away },
            .pressed = .{ .lightness = 0.09 * away },
            .focused = .{ .lightness = 0.07 * away },
            .selected = .{ .lightness = 0.12 * away },
            .checked = .{ .lightness = 0.12 * away },
            .dragged = .{ .lightness = 0.11 * away },
            .visited = .{ .lightness = -0.08 * away, .chroma = -0.03 },
            .disabled = .{ .lightness = -0.25 * away, .chroma = -0.1 },
            .placeholder = .{ .lightness = -0.3 * away, .chroma = -0.05 },
            .inactive = .{ .lightness = -0.1 * away, .chroma = -0.06 },
        },
        .surface = .{
            .sunken = .{ .lightness = -0.04 * away },
            .raised = .{ .lightness = 0.04 * away },
            .overlay = .{ .lightness = 0.08 * away },
            .shadow = .{ .alpha = 0.5, .mix = .{ .toward = default_shadow_color, .amount = 0.8 } },
        },
        .line = .{
            .border = .{ .lightness = 0.12 * away },
            .border_strong = .{ .lightness = 0.22 * away },
            .separator = .{ .lightness = 0.07 * away },
        },
        .contrast = .{
            .on = .{ .contrast = .{} },
            .on_muted = .{ .contrast = .{ .toward_original = on_muted_toward_original } },
        },
        .alpha = .{
            .translucent = .{ .alpha = 0.5 },
            .highlight = .{ .alpha = 0.25 },
        },
    };
}

const testing = std.testing;

const test_color: Color = .{ .lightness = 0.5, .chroma = 0.1, .hue = 200 };

test "there are 33 variations in 7 families" {
    var count: usize = 0;
    const families = @typeInfo(Variations).@"struct".field_types;
    inline for (families) |Family| count += @typeInfo(Family).@"struct".field_names.len;
    try testing.expectEqual(7, families.len);
    try testing.expectEqual(33, count);
}

test "mode-aware families invert in light mode" {
    const dark = from(.dark);
    const light = from(.light);
    try testing.expect(dark.state.hovered.apply(test_color).lightness > test_color.lightness);
    try testing.expect(light.state.hovered.apply(test_color).lightness < test_color.lightness);
    try testing.expect(dark.emphasis.muted.apply(test_color).lightness < test_color.lightness);
    try testing.expect(light.emphasis.muted.apply(test_color).lightness > test_color.lightness);
    try testing.expect(light.surface.raised.apply(test_color).lightness < test_color.lightness);
    try testing.expect(light.line.border.apply(test_color).lightness < test_color.lightness);
}

test "absolute families ignore mode" {
    const dark = from(.dark);
    const light = from(.light);
    try testing.expectEqual(dark.lightness.lighter.apply(test_color), light.lightness.lighter.apply(test_color));
    try testing.expectEqual(dark.alpha.highlight.apply(test_color), light.alpha.highlight.apply(test_color));
    try testing.expect(light.surface.shadow.apply(test_color).lightness < test_color.lightness);
}

test "selectedInactive follows tweaks to selected and inactive" {
    var variations = from(.dark);
    const before = variations.state.selectedInactive().apply(test_color);
    variations.state.selected.lightness += 0.1;
    const after = variations.state.selectedInactive().apply(test_color);
    try testing.expectApproxEqAbs(before.lightness + 0.1, after.lightness, 1e-12);

    const expected = variations.state.inactive.apply(variations.state.selected.apply(test_color));
    try testing.expectEqual(expected, variations.state.selectedInactive().apply(test_color));
}

test "an explicit selected_inactive wins over the composition" {
    var variations = from(.dark);
    variations.state.selected_inactive = .{ .lightness = 0.3 };
    try testing.expectApproxEqAbs(0.8, variations.state.selectedInactive().apply(test_color).lightness, 1e-12);
}
