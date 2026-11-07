//! Zen's `zen.theme.*` prefs.

/// `accent-color`: links, focus rings and the selected tab. Default: cyan.
accent_color: ?@import("kosm").Color = null,
/// `gradient`: the window background gradient; `gradient.value` is the pref itself (D102).
gradient: Gradient = .{},
/// `content-element-separation`: the gap around web content, in pixels. null: Zen's, 8.
content_element_separation: ?u16 = null,
/// `border-radius`: corner radius of the content, in pixels; -1 is the platform's. null: Zen's, -1.
border_radius: ?i32 = null,
/// `hide-tab-throbber`: hide the loading spinner on tabs. null: Zen's, true.
hide_tab_throbber: ?bool = null,
/// `use-system-colors`: take the toolkit's colors instead of Zen's. null: Zen's, false.
use_system_colors: ?bool = null,

pub const Gradient = @import("theme/Gradient.zig");
