//! Zen's about:config prefs for a set of profiles, written to each one's `user.js`, which
//! Zen reads at startup. An app of its own: put a second one in the tree to give some
//! profiles other prefs, and narrow the first one with `exclude`.

const Profile = @This();

const std = @import("std");
const kosm = @import("kosm");
const user_js = @import("user_js.zig");

/// The profile directories to write, a glob. Only directories holding a `prefs.js` count,
/// so `Crash Reports` and the like are skipped. Default: every Zen profile, `~/.zen/*`.
profiles: []const u8 = "~/.zen/*",
/// Profile directories to leave out, globs written like `profiles` (`~/.zen/*.work`).
exclude: []const []const u8 = &.{},
/// Who owns each `user.js`. Default: `default_target`.
target: Target = default_target,
/// How values are spelled. Null fields take the `userjs` adapter's: `#rrggbb`.
format: kosm.Format = .{},
/// The prefs to write, named like about:config (`prefs.zen.theme.accent_color`). Null prefs are
/// not written; with none set, no profile is looked for or written.
prefs: Prefs = .{},
/// Prefs the app doesn't cover, written after its own, each named by its whole
/// about:config name: `.{ .path = "zen.urlbar.behavior", .value = .{ .string = "float" } }`. A
/// name a set pref or another extra already has fails the apply. Default: none.
extra: []const kosm.Setting = &.{},

/// Zen's about:config prefs.
pub const Prefs = @import("Prefs.zig");

/// Who owns a profile's `user.js`.
pub const Target = enum {
    /// A `// kosm:begin zen` block; the user's own prefs around it are kept. A missing or empty
    /// `user.js` is created holding only the block.
    block,
    /// The whole file, so kosm is its source of truth.
    generate,
};

/// The target every profile starts with. Change it here to make owning the whole file the default.
pub const default_target: Target = .block;

/// The id of the block kosm owns in `user.js`.
const block_id = "zen";

/// Prefs from the theme: the accent from cyan, the window scheme from the mode, page
/// colors from black and white (swapped in light mode), and the profile stylesheets kosm's CSS
/// needs turned on. Every other pref is left to Zen.
pub fn from(theme: kosm.Theme) Profile {
    const palette = theme.palette;
    var prefs: Prefs = .{};
    prefs.zen.theme.accent_color = palette.cyan;
    prefs.zen.view.window.scheme = if (theme.mode == .dark) .dark else .light;
    prefs.browser.display.background_color = if (theme.mode == .dark) palette.black else palette.white;
    prefs.browser.display.foreground_color = if (theme.mode == .dark) palette.white else palette.black;
    prefs.toolkit.legacy_user_profile_customizations.stylesheets = true;
    return .{ .prefs = prefs };
}

/// Writes the set prefs, then the extras, to the `user.js` of every picked profile.
pub fn apply(self: Profile, output: *kosm.Output) !void {
    const prefs = try self.withExtras(output);
    if (prefs.table.len == 0) return;
    const exclude = try output.allocator.alloc([]const u8, self.exclude.len);
    for (self.exclude, exclude) |directory, *file| file.* = try prefsFile(output.allocator, directory);
    const found = try output.find(.{ .files = try prefsFile(output.allocator, self.profiles), .exclude = exclude });
    for (found) |prefs_js| {
        const file = try std.mem.concat(output.allocator, u8, &.{ std.Io.Dir.path.dirname(prefs_js).?, "/user.js" });
        switch (self.target) {
            .block => try output.block(.{ .file = file, .id = block_id, .lang = "userjs", .format = self.format }, prefs),
            .generate => try output.generate(.{ .file = file, .lang = "userjs", .format = self.format }, prefs),
        }
    }
}

/// The set prefs followed by the extras, checked so no name is written twice.
fn withExtras(self: Profile, output: *kosm.Output) !kosm.Value {
    const own = (try user_js.table(output.allocator, self.prefs)).table;
    const prefs = try output.allocator.alloc(kosm.Setting.Keyed, own.len);
    for (own, prefs) |pref, *slot| slot.* = .{ .path = pref.key, .keys = try output.allocator.dupe(?[]const u8, &.{pref.key}), .value = pref.value };
    const files = try std.mem.concat(output.allocator, u8, &.{ std.mem.trimEnd(u8, self.profiles, "/"), "/user.js" });
    const all = try kosm.Setting.withExtras(output, files, prefs, self.extra, .{ .paths = .whole_name });
    return kosm.Setting.tree(output.allocator, all);
}

/// The `prefs.js` Firefox keeps in every profile directory `directories` picks.
fn prefsFile(allocator: std.mem.Allocator, directories: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.mem.concat(allocator, u8, &.{ std.mem.trimEnd(u8, directories, "/"), "/prefs.js" });
}

const testing = std.testing;
const userjs = @import("kosm_userjs");

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},
    warnings: kosm.Warnings = undefined,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    output: kosm.Output = undefined,

    fn init(fixture: *Fixture, files: []const [2][]const u8) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
        for (files) |file| {
            try fixture.tmp.dir.createDirPath(testing.io, std.Io.Dir.path.dirname(file[0]).?);
            try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
        }
        fixture.warnings = .init(fixture.arena.allocator());
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = &.{userjs.adapter},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "zen.profile",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    /// The planned contents of the file at `path` under the home directory.
    fn planned(fixture: *Fixture, path: []const u8) ![]const u8 {
        const absolute = try std.Io.Dir.path.join(fixture.arena.allocator(), &.{ fixture.output.home, path });
        for (fixture.plan.files.items) |file| {
            if (std.mem.eql(u8, file.path, absolute)) return file.new;
        }
        return error.NotPlanned;
    }
};

const test_profiles = [_][2][]const u8{
    .{ ".zen/a.default/prefs.js", "" },
    .{ ".zen/a.default/user.js", "user_pref(\"browser.startup.page\", 3);\n" },
    .{ ".zen/b.work/prefs.js", "" },
    .{ ".zen/c.empty/prefs.js", "" },
    .{ ".zen/c.empty/user.js", "" },
    .{ ".zen/Crash Reports/events/x", "" },
};

const test_theme = kosm.Theme.from(.{ .black = kosm.hex("041c26"), .white = kosm.hex("a3c5cc"), .cyan = kosm.hex("268078") }, .dark);

const expected_block =
    \\// kosm:begin zen
    \\user_pref("zen.theme.accent-color", "#268078");
    \\user_pref("zen.view.window.scheme", 0);
    \\user_pref("browser.display.background_color", "#041c26");
    \\user_pref("browser.display.foreground_color", "#a3c5cc");
    \\user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
    \\// kosm:end
    \\
;

test "every profile gets a block of prefs, keeping the user's own, and a missing or empty user.js holds only the block" {
    var fixture: Fixture = undefined;
    try fixture.init(&test_profiles);
    defer fixture.deinit();
    try from(test_theme).apply(&fixture.output);

    try testing.expectEqual(3, fixture.plan.files.items.len);
    try testing.expectEqualStrings("user_pref(\"browser.startup.page\", 3);\n" ++ expected_block, try fixture.planned(".zen/a.default/user.js"));
    try testing.expectEqualStrings(expected_block, try fixture.planned(".zen/b.work/user.js"));
    try testing.expectEqualStrings(expected_block, try fixture.planned(".zen/c.empty/user.js"));
}

test "a second profile set gives other prefs to the profiles the first excludes" {
    var fixture: Fixture = undefined;
    try fixture.init(&test_profiles);
    defer fixture.deinit();
    var everyday = from(test_theme);
    everyday.exclude = &.{"~/.zen/*.work"};
    var work = from(test_theme);
    work.profiles = "~/.zen/*.work/";
    work.prefs.zen.view.window.scheme = .light;
    work.prefs.zen.view.compact.enable_at_startup = true;
    try everyday.apply(&fixture.output);
    try work.apply(&fixture.output);

    try testing.expectEqual(3, fixture.plan.files.items.len);
    try testing.expectEqualStrings(expected_block, try fixture.planned(".zen/c.empty/user.js"));
    const work_file = try fixture.planned(".zen/b.work/user.js");
    try testing.expect(std.mem.indexOf(u8, work_file, "user_pref(\"zen.view.window.scheme\", 1);\nuser_pref(\"zen.view.compact.enable-at-startup\", true);\n") != null);
}

test "two profile sets reaching one profile fail the apply" {
    var fixture: Fixture = undefined;
    try fixture.init(&test_profiles);
    defer fixture.deinit();
    var work = from(test_theme);
    work.profiles = "~/.zen/*.work";
    try from(test_theme).apply(&fixture.output);
    try testing.expectError(error.EditsOverlap, work.apply(&fixture.output));
    try testing.expectEqualStrings("~/.zen/b.work/user.js", fixture.diagnostics.file);
}

test "the generate target owns the whole user.js" {
    var fixture: Fixture = undefined;
    try fixture.init(&test_profiles);
    defer fixture.deinit();
    var profile = from(test_theme);
    profile.profiles = "~/.zen/a.default";
    profile.target = .generate;
    profile.prefs = .{};
    profile.prefs.zen.theme.content_element_separation = 0;
    try profile.apply(&fixture.output);
    try testing.expectEqualStrings("user_pref(\"zen.theme.content-element-separation\", 0);\n", try fixture.planned(".zen/a.default/user.js"));
}

test "no profile to write is an error naming the glob" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{.{ ".zen/Crash Reports/events/x", "" }});
    defer fixture.deinit();
    try testing.expectError(error.NoFile, from(test_theme).apply(&fixture.output));
    try testing.expectEqualStrings("~/.zen/*/prefs.js", fixture.diagnostics.file);
}

test "Profile{} sets no prefs, so it looks for no profile and plans nothing" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{});
    defer fixture.deinit();
    const empty: Profile = .{};
    try empty.apply(&fixture.output);
    try testing.expectEqual(0, fixture.plan.files.items.len);
}

test "extras follow the prefs under their whole names, and a name set twice fails naming both" {
    var fixture: Fixture = undefined;
    try fixture.init(&test_profiles);
    defer fixture.deinit();
    var profile: Profile = .{ .profiles = "~/.zen/b.work", .target = .generate };
    profile.prefs.zen.theme.gradient.value = false;
    profile.extra = &.{
        .{ .path = "zen.theme.gradient.show-custom-colors", .value = .{ .boolean = true } },
        .{ .path = "zen.urlbar.behavior", .value = .{ .string = "float" } },
    };
    try profile.apply(&fixture.output);
    try testing.expectEqualStrings(
        \\user_pref("zen.theme.gradient", false);
        \\user_pref("zen.theme.gradient.show-custom-colors", true);
        \\user_pref("zen.urlbar.behavior", "float");
        \\
    , try fixture.planned(".zen/b.work/user.js"));

    profile.extra = &.{.{ .path = "zen.theme.gradient", .value = .{ .boolean = true } }};
    try testing.expectError(error.AppFailed, profile.apply(&fixture.output));
    try testing.expectEqualStrings("extra 'zen.theme.gradient' and setting 'zen.theme.gradient' write the same key, or one inside the other; keep one", fixture.diagnostics.message());
    try testing.expectEqualStrings("~/.zen/b.work/user.js", fixture.diagnostics.file);
}
