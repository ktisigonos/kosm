//! Where `verbatim` writes and how.

/// The file to own whole: `~/...` or an absolute path.
file: []const u8,
/// The exact bytes to write.
content: []const u8,
/// Whether the file can be run, as a script; its other permission bits are kept. Default: false.
executable: bool = false,
