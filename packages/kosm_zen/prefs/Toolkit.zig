//! Firefox's `toolkit.*` prefs.

/// `legacyUserProfileCustomizations.*`: the profile's own stylesheets.
legacy_user_profile_customizations: LegacyUserProfileCustomizations = .{},

pub const LegacyUserProfileCustomizations = @import("toolkit/LegacyUserProfileCustomizations.zig");

/// Pref names that differ from the field names' `_` -> `-` spelling.
pub const pref_names = .{ .legacy_user_profile_customizations = "legacyUserProfileCustomizations" };
