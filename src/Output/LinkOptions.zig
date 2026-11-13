//! Where `link` makes a symbolic link, and what it points to.

/// The link: `~/...` or an absolute path.
file: []const u8,
/// What the link points to, written into it as is: relative to the link's folder, or absolute.
target: []const u8,
/// The folder diffs and reports show the link under, one line for every file and link there
/// (an icon theme of thousands of files). Default: null, the link is shown itself.
group: ?[]const u8 = null,
