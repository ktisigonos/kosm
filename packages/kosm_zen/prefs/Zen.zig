//! Zen's `zen.*` prefs.

/// `zen.theme.*`: colors and shapes.
theme: Theme = .{},
/// `zen.view.*`: the window's layout.
view: View = .{},
/// `zen.widget.*`: platform widgets.
widget: Widget = .{},

pub const Theme = @import("zen/Theme.zig");
pub const View = @import("zen/View.zig");
pub const Widget = @import("zen/Widget.zig");
