//! Zen's about:config prefs kosm writes to a profile's `user.js` (D94, D96), nested by the pref's
//! own name: `zen.theme.accent-color` is `prefs.zen.theme.accent_color`. A null pref is not
//! written, so Zen's own value stays (D27).

/// `zen.*`: Zen's own prefs.
zen: Zen = .{},
/// `browser.*`: Firefox's browser prefs.
browser: Browser = .{},
/// `toolkit.*`: Firefox's toolkit prefs.
toolkit: Toolkit = .{},

pub const Zen = @import("prefs/Zen.zig");
pub const Browser = @import("prefs/Browser.zig");
pub const Toolkit = @import("prefs/Toolkit.zig");
