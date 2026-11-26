//! How `kosm doctor` finds an app's program: it is installed when any one of these is found.

const Program = @This();

/// A command on `PATH` (`kitty`). Null looks for none.
command: ?[]const u8 = null,
/// A Flatpak's app id (`org.equicord.equibop`), installed for the user or system-wide. Null
/// looks for none.
flatpak: ?[]const u8 = null,
