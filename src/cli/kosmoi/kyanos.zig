//! Kyanos (dark blue): every official app through the base kosmos, from a look of a palette
//! and a font. kosm init wrote this file; it is yours to edit.

const kosm = @import("kosm");
const base = @import("kosm_base");

/// What makes Kyanos look nice: its palette and font. Assign a role to recolor every app
/// (`.roles = .{ .accent = palette.blue.? }`) and set values all apps share in `.values`
/// (`.{ .rounding = 10, .padding = 10 }`).
pub const look: base.Look = .{
    .theme = .from(.{ .palette = palette, .mode = .dark }),
    .fonts = .{ .families = &.{"monospace"}, .size = 13 },
};

pub const palette: kosm.Palette = .{
    .black = kosm.hex("041c26"),
    .white = kosm.hex("a3c5cc"),
    .red = kosm.hex("993d48"),
    .yellow = kosm.hex("7a993d"),
    .green = kosm.hex("3d9960"),
    .cyan = kosm.hex("2e9990"),
    .blue = kosm.hex("2e8799"),
    .purple = kosm.hex("4d7399"),
};

pub fn kosmos() base.Base {
    // The apps left out write into files or folders their programs create; take them out of
    // the list once you have the program.
    var apps = base.from(look, .{ .except = &.{
        .blender,
        .counter_strike,
        .counter_strike_2,
        .darkreader,
        .hyprmouse,
        .ohmyposh,
        .qtct,
        .tuios,
        .vicinae,
    } });
    // Override any single value with a plain assignment:
    apps.kitty.?.cursor.cursor_shape = .block;
    apps.ghostty.?.cursor_style = .block;
    return apps;
}
