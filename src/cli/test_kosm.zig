//! For tests: a stub kosm package and a stub `kosm_kitty` that `kosm init` fetches offline in
//! place of their git URLs, and kosm's installed sources that replace the stub kosm through
//! `--fork`.

const std = @import("std");
const init_command = @import("init.zig");
const manifest = @import("manifest.zig");
const Sources = @import("Sources.zig");
const kosm_package = @import("kosm_package");

/// Writes a stub kosm into `kosm_stub/` and a stub `kosm_kitty` into `kosm_kitty_stub/` of
/// `directory`, whose absolute path is `root`, and returns what `kosm init` takes to fetch
/// them. The stub kosm holds no code, so a build only works through `sources`; kosm's own
/// fingerprint makes the fork match it. The starting kosmos needs the real official packages,
/// so it does not build in such a config.
pub fn stub(arena: std.mem.Allocator, io: std.Io, directory: std.Io.Dir, root: []const u8) !init_command.Kosm {
    try directory.createDirPath(io, "kosm_stub");
    try directory.writeFile(io, .{ .sub_path = "kosm_stub/build.zig.zon", .data = try std.fmt.allocPrint(arena,
        \\.{{ .name = .kosm, .version = "0.0.0", .fingerprint = 0x{x}, .minimum_zig_version = "0.17.0", .paths = .{{""}} }}
        \\
    , .{kosm_package.fingerprint}) });

    try directory.createDirPath(io, "kosm_kitty_stub");
    try directory.writeFile(io, .{ .sub_path = "kosm_kitty_stub/build.zig.zon", .data = try std.fmt.allocPrint(arena,
        \\.{{ .name = .kosm_kitty, .version = "0.0.0", .fingerprint = 0x{x}, .minimum_zig_version = "0.17.0", .paths = .{{""}} }}
        \\
    , .{manifest.fingerprint(io, "kosm_kitty")}) });
    try directory.writeFile(io, .{ .sub_path = "kosm_kitty_stub/build.zig", .data = kitty_build });
    try directory.writeFile(io, .{ .sub_path = "kosm_kitty_stub/root.zig", .data = kitty_root });
    try directory.writeFile(io, .{ .sub_path = "kosm_kitty_stub/kosm_stub.zig", .data = "" });

    const packages = try arena.alloc(@import("Packages.zig").Package, 1);
    packages[0] = .{ .name = "kosm_kitty", .url = try std.Io.Dir.path.join(arena, &.{ root, "kosm_kitty_stub" }) };
    return .{
        .url = try std.Io.Dir.path.join(arena, &.{ root, "kosm_stub" }),
        .minimum_zig_version = kosm_package.minimum_zig_version,
        .packages = packages,
    };
}

/// The stub imports an empty kosm of its own, which the config replaces with its copy.
const kitty_build =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    _ = b.standardTargetOptions(.{});
    \\    _ = b.standardOptimizeOption(.{});
    \\    const module = b.addModule("kosm_kitty", .{ .root_source_file = b.path("root.zig") });
    \\    module.addImport("kosm", b.createModule(.{ .root_source_file = b.path("kosm_stub.zig") }));
    \\}
    \\
;

/// As much of kosm_kitty as the scaffolded kosmos uses: `from`, the font size, and an adapter
/// writing `key value` lines.
const kitty_root =
    \\const std = @import("std");
    \\const kosm = @import("kosm");
    \\
    \\pub const App = struct {
    \\    fonts: Fonts = .{},
    \\
    \\    pub const Fonts = struct { font_size: ?u32 = null };
    \\
    \\    pub fn apply(self: App, output: *kosm.Output) !void {
    \\        try output.generate(.{ .file = "~/.config/kitty/kosm.conf", .lang = "kitty" }, .{ .font_size = self.fonts.font_size });
    \\    }
    \\};
    \\
    \\pub fn from(theme: kosm.Theme) App {
    \\    _ = theme;
    \\    return .{};
    \\}
    \\
    \\pub const adapter: kosm.Adapter = .{ .name = "kitty", .serialize = serialize };
    \\
    \\fn serialize(writer: *std.Io.Writer, root: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    \\    _ = context;
    \\    for (root.table) |entry| try writer.print("{s} {d}\n", .{ entry.key, entry.value.integer });
    \\}
    \\
;

/// The sources `zig build test` installs first (`zig-out/share/kosm`), so a file left out of
/// kosm's `.paths` fails the config tests. Assumes the tests run from the repository root.
pub fn sources(arena: std.mem.Allocator, io: std.Io) !Sources {
    return .{ .directory = try std.Io.Dir.cwd().realPathFileAlloc(io, "zig-out/share/kosm", arena), .origin = .installed };
}
