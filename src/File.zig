//! A file a kosmos reads, like a script it is written in: name it in the kosmos' `Params` and
//! kosm reads its bytes before calling the kosmos, which then computes from them in plain code.

const File = @This();

const std = @import("std");

/// Where the file is: `~/` for the home directory, `~~/` for the config, `~~kosmos/` for the
/// applied kosmos' folder, `~~<name>/` for a package's or local module's folder
/// (`~~kosm_krystallos/`), an absolute path, or a relative one. A relative default is relative
/// to the applied kosmos' folder, a path given on the command line to the working directory.
/// Once read, kosm sets this to the absolute path, which any program can open.
path: []const u8,
/// The file's bytes. Kosm reads them for every file in a kosmos' `Params` before calling it;
/// a file built anywhere else holds none (null; an empty file is `""`), and reading it fails.
bytes: ?[]const u8 = null,

pub const Error = error{
    /// The file holds no bytes: kosm reads only the files a kosmos names in its `Params`.
    FileNotLoaded,
};

/// The file's bytes, valid for the whole run.
pub fn contents(file: File) Error![]const u8 {
    return file.bytes orelse error.FileNotLoaded;
}

test "a file kosm did not read cannot be read, an empty one can" {
    const unread: File = .{ .path = "~/kosmos.lua" };
    try std.testing.expectError(error.FileNotLoaded, unread.contents());
    const empty: File = .{ .path = "~/kosmos.lua", .bytes = "" };
    try std.testing.expectEqualStrings("", try empty.contents());
}
