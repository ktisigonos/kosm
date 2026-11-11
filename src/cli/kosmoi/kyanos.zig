//! Kyanos (dark blue): every official app through the base kosmos, from a palette and
//! a font. kosm init wrote this file; it is yours to edit.

const kosm = @import("kosm");
const base = @import("kosm_base");

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
    var apps = base.from(.from(palette, .dark), .{ .families = &.{"monospace"}, .size = 13 });
    // Override any single value with a plain assignment:
    apps.kitty.?.cursor.cursor_shape = .block;
    apps.ghostty.?.cursor_style = .block;
    // These write into files or folders their programs create; set them back once you have
    // the program.
    apps.cs16 = null;
    apps.cs2 = null;
    apps.darkreader = null;
    apps.hyprmouse = null;
    apps.ohmyposh = null;
    apps.qtct = null;
    apps.tuios = null;
    apps.vicinae = null;
    return apps;
}
