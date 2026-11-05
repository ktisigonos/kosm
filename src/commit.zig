//! Writes a plan to disk (D36): every changed file goes to a temp file next to it first, and
//! only once all of them are written are they renamed into place. Unchanged files are not
//! touched (D35).

const std = @import("std");
const Plan = @import("Plan.zig");

/// Which file a failed `writePlan` was working on, as the app wrote it.
pub const Failure = struct {
    path: []const u8 = "",
};

/// Writes every changed file of `plan`. A failure before the renames leaves the disk as it was.
/// A rename failing halfway (rare: same directory, already created) can leave earlier files
/// replaced. Symlinked files are written through to their target, and a replaced file keeps
/// its permissions.
pub fn writePlan(allocator: std.mem.Allocator, io: std.Io, plan: *const Plan, failure: *Failure) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var pending: std.ArrayList(std.Io.File.Atomic) = .empty;
    defer for (pending.items) |*atomic| atomic.deinit(io);

    for (plan.files.items) |file| {
        if (!file.changed()) continue;
        failure.path = file.display_path;
        var atomic = try createTemp(arena.allocator(), io, file.path, file.old != null);
        errdefer atomic.deinit(io);
        try writeContents(io, &atomic, file.new);
        try pending.append(arena.allocator(), atomic);
    }
    for (pending.items, 0..) |*atomic, index| {
        failure.path = changedFile(plan, index).display_path;
        try atomic.replace(io);
    }
    failure.path = "";
}

fn createTemp(allocator: std.mem.Allocator, io: std.Io, path: []const u8, exists: bool) !std.Io.File.Atomic {
    const cwd = std.Io.Dir.cwd();
    var target = path;
    var permissions: std.Io.File.Permissions = .default_file;
    if (exists) {
        // Replacing a symlink with a file would cut it loose from the dotfiles it points into.
        target = try cwd.realPathFileAlloc(io, path, allocator);
        permissions = (try cwd.statFile(io, target, .{})).permissions;
    }
    return cwd.createFileAtomic(io, target, .{ .permissions = permissions, .make_path = true, .replace = true });
}

fn writeContents(io: std.Io, atomic: *std.Io.File.Atomic, contents: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var file_writer = atomic.file.writer(io, &buffer);
    file_writer.interface.writeAll(contents) catch return file_writer.err orelse error.WriteFailed;
    file_writer.interface.flush() catch return file_writer.err orelse error.WriteFailed;
}

fn changedFile(plan: *const Plan, changed_index: usize) *const Plan.File {
    var seen: usize = 0;
    for (plan.files.items) |*file| {
        if (!file.changed()) continue;
        if (seen == changed_index) return file;
        seen += 1;
    }
    unreachable; // writePlan created exactly one temp file per changed file.
}

const testing = std.testing;

fn tmpPath(tmp: *testing.TmpDir, buffer: []u8) ![]const u8 {
    const length = try tmp.dir.realPath(testing.io, buffer);
    return buffer[0..length];
}

fn readTmp(tmp: *testing.TmpDir, name: []const u8) ![]u8 {
    return tmp.dir.readFileAlloc(testing.io, name, testing.allocator, .limited(4096));
}

test "writePlan writes changed files, creating folders, and keeps permissions" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "existing.conf", .data = "old\n" });
    try tmp.dir.setFilePermissions(testing.io, "existing.conf", .fromMode(0o600), .{});
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = try tmpPath(&tmp, &root_buffer);

    var plan: Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    const existing = try std.Io.Dir.path.join(testing.allocator, &.{ root, "existing.conf" });
    defer testing.allocator.free(existing);
    const created = try std.Io.Dir.path.join(testing.allocator, &.{ root, "new/folder/created.css" });
    defer testing.allocator.free(created);
    try plan.add(existing, "~/existing.conf", "terminal", "new\n");
    try plan.add(created, "~/new/folder/created.css", "browser", "body {}\n");

    var failure: Failure = .{};
    try writePlan(testing.allocator, testing.io, &plan, &failure);

    const existing_contents = try readTmp(&tmp, "existing.conf");
    defer testing.allocator.free(existing_contents);
    try testing.expectEqualStrings("new\n", existing_contents);
    const created_contents = try readTmp(&tmp, "new/folder/created.css");
    defer testing.allocator.free(created_contents);
    try testing.expectEqualStrings("body {}\n", created_contents);
    const stat = try tmp.dir.statFile(testing.io, "existing.conf", .{});
    try testing.expectEqual(0o600, stat.permissions.toMode() & 0o777);
}

test "a failing plan writes nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "first.conf", .data = "old\n" });
    // Reading a missing file in a read-only folder works, so only the commit can fail.
    try tmp.dir.createDirPath(testing.io, "locked");
    try tmp.dir.setFilePermissions(testing.io, "locked", .fromMode(0o500), .{});
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = try tmpPath(&tmp, &root_buffer);

    var plan: Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    const first = try std.Io.Dir.path.join(testing.allocator, &.{ root, "first.conf" });
    defer testing.allocator.free(first);
    const impossible = try std.Io.Dir.path.join(testing.allocator, &.{ root, "locked/second.conf" });
    defer testing.allocator.free(impossible);
    try plan.add(first, "~/first.conf", "one", "new\n");
    try plan.add(impossible, "~/locked/second.conf", "two", "never\n");

    var failure: Failure = .{};
    try testing.expect(std.meta.isError(writePlan(testing.allocator, testing.io, &plan, &failure)));
    try testing.expectEqualStrings("~/locked/second.conf", failure.path);

    const contents = try readTmp(&tmp, "first.conf");
    defer testing.allocator.free(contents);
    try testing.expectEqualStrings("old\n", contents);
    var directory = try tmp.dir.openDir(testing.io, ".", .{ .iterate = true });
    defer directory.close(testing.io);
    var iterator = directory.iterate();
    var count: usize = 0;
    while (try iterator.next(testing.io)) |_| count += 1;
    try testing.expectEqual(2, count); // no temp files left behind
}

test "unchanged files are not rewritten" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "same.conf", .data = "same\n" });
    try tmp.dir.setFilePermissions(testing.io, "same.conf", .fromMode(0o400), .{});
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = try tmpPath(&tmp, &root_buffer);

    var plan: Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    const same = try std.Io.Dir.path.join(testing.allocator, &.{ root, "same.conf" });
    defer testing.allocator.free(same);
    try plan.add(same, "~/same.conf", "terminal", "same\n");
    try testing.expect(!plan.hasChanges());

    // A read-only file in a writable folder could be replaced, so check the inode stayed.
    const before = try tmp.dir.statFile(testing.io, "same.conf", .{});
    var failure: Failure = .{};
    try writePlan(testing.allocator, testing.io, &plan, &failure);
    const after = try tmp.dir.statFile(testing.io, "same.conf", .{});
    try testing.expectEqual(before.inode, after.inode);
}

test "a symlinked file is written through to its target" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "dotfiles");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "dotfiles/kitty.conf", .data = "old\n" });
    try tmp.dir.symLink(testing.io, "dotfiles/kitty.conf", "kitty.conf", .{});
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = try tmpPath(&tmp, &root_buffer);

    var plan: Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    const link = try std.Io.Dir.path.join(testing.allocator, &.{ root, "kitty.conf" });
    defer testing.allocator.free(link);
    try plan.add(link, "~/kitty.conf", "terminal", "new\n");
    var failure: Failure = .{};
    try writePlan(testing.allocator, testing.io, &plan, &failure);

    const target = try readTmp(&tmp, "dotfiles/kitty.conf");
    defer testing.allocator.free(target);
    try testing.expectEqualStrings("new\n", target);
    const link_stat = try tmp.dir.statFile(testing.io, "kitty.conf", .{ .follow_symlinks = false });
    try testing.expectEqual(.sym_link, link_stat.kind);
}

test "two apps writing one file is an error" {
    var plan: Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    try plan.add("/nonexistent/kosm-test/a.conf", "~/a.conf", "one", "1\n");
    try testing.expectError(error.FileWrittenTwice, plan.add("/nonexistent/kosm-test/a.conf", "~/a.conf", "two", "2\n"));
    try testing.expectEqualStrings("one", plan.find("/nonexistent/kosm-test/a.conf").?.owner);
}
