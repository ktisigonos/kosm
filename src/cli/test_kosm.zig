//! For tests: a stub kosm package that `kosm init` fetches offline in place of kosm's git URL,
//! and kosm's installed sources that replace it through `--fork`.

const std = @import("std");
const init_command = @import("init.zig");
const Sources = @import("Sources.zig");
const kosm_package = @import("kosm_package");

/// Writes a stub kosm into `kosm_stub/` of `directory`, whose absolute path is `root`, and
/// returns what `kosm init` takes to fetch it. It holds no code, so a build only works through
/// `sources`; kosm's own fingerprint makes the fork match it.
pub fn stub(arena: std.mem.Allocator, io: std.Io, directory: std.Io.Dir, root: []const u8) !init_command.Kosm {
    try directory.createDirPath(io, "kosm_stub");
    try directory.writeFile(io, .{ .sub_path = "kosm_stub/build.zig.zon", .data = try std.fmt.allocPrint(arena,
        \\.{{ .name = .kosm, .version = "0.0.0", .fingerprint = 0x{x}, .minimum_zig_version = "0.17.0", .paths = .{{""}} }}
        \\
    , .{kosm_package.fingerprint}) });
    return .{ .url = try std.Io.Dir.path.join(arena, &.{ root, "kosm_stub" }), .minimum_zig_version = kosm_package.minimum_zig_version };
}

/// The sources `zig build test` installs first (`zig-out/share/kosm`), so a file left out of a
/// manifest's `.paths` fails the config tests. Assumes the tests run from the repository root.
pub fn sources(arena: std.mem.Allocator, io: std.Io) !Sources {
    return .{ .directory = try std.Io.Dir.cwd().realPathFileAlloc(io, "zig-out/share/kosm", arena), .origin = .installed };
}
