//! What a theme is built from: the palette, the mode, the roles, code and diff colors the
//! kosmos sets itself, and the traits of the colors' source. `Theme.from` works out everything
//! else from it.

const Palette = @import("../Palette.zig");
const Mode = @import("../Theme.zig").Mode;
const Roles = @import("Roles.zig");
const Code = @import("Code.zig");
const Diff = @import("Diff.zig");
const Traits = @import("../Traits.zig");

/// Black, white and any of the wheel's hues; missing hues are mixed from their neighbours.
palette: Palette,
/// Dark or light; the background and foreground roles follow it.
mode: Mode,
/// Roles set by the kosmos. Default: every role from the palette.
roles: Roles.Overrides = .{},
/// Code colors set by the kosmos. Default: every code color from the palette and roles.
code: Code.Overrides = .{},
/// Diff colors set by the kosmos. Default: every diff color from the roles.
diff: Diff.Overrides = .{},
/// What the source of the colors is like (an image's), for apps basing choices of their own on
/// it; `Image.themeInput` sets it. Default: null, a theme made by hand.
traits: ?Traits = null,
