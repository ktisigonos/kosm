//! Firefox's `toolkit.legacyUserProfileCustomizations.*` prefs.

/// `stylesheets`: read the profile's `userChrome.css` and `userContent.css`, which kosm's CSS
/// needs. Default: true.
stylesheets: ?bool = null,
