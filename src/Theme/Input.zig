//! What a theme is built from: the palette, the mode, and the roles and code colors the
//! kosmos sets itself. `Theme.from` works out everything else from it.

const Palette = @import("../Palette.zig");
const Mode = @import("../Theme.zig").Mode;
const Roles = @import("Roles.zig");
const Code = @import("Code.zig");

/// Black, white and any of the wheel's hues; missing hues are mixed from their neighbours.
palette: Palette,
/// Dark or light; the background and foreground roles follow it.
mode: Mode,
/// Roles set by the kosmos. Default: every role from the palette.
roles: Roles.Overrides = .{},
/// Code colors set by the kosmos. Default: every code color from the palette and foreground.
code: Code.Overrides = .{},
