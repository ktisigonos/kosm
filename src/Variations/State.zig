//! Mode-aware: interaction and window focus. CSS pseudo-classes, GTK states, Material state
//! layers, Fluent, JetBrains, Qt Inactive group / GTK :backdrop. No `active` (D14).

const State = @This();

const Modifier = @import("../Modifier.zig");

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

const std = @import("std");
const testing = std.testing;
const Color = @import("../Color.zig");
const Variations = @import("../Variations.zig");

const test_color: Color = .{ .lightness = 0.5, .chroma = 0.1, .hue = 200 };

test "selectedInactive follows tweaks to selected and inactive" {
    var variations = Variations.from(.dark);
    const before = variations.state.selectedInactive().apply(test_color);
    variations.state.selected.lightness += 0.1;
    const after = variations.state.selectedInactive().apply(test_color);
    try testing.expectApproxEqAbs(before.lightness + 0.1, after.lightness, 1e-12);

    const expected = variations.state.inactive.apply(variations.state.selected.apply(test_color));
    try testing.expectEqual(expected, variations.state.selectedInactive().apply(test_color));
}

test "an explicit selected_inactive wins over the composition" {
    var variations = Variations.from(.dark);
    variations.state.selected_inactive = .{ .lightness = 0.3 };
    try testing.expectApproxEqAbs(0.8, variations.state.selectedInactive().apply(test_color).lightness, 1e-12);
}
