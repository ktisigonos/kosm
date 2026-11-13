//! Writes a plan to disk: every changed file goes to a temp file next to it first, and
//! only once all of them are written are they renamed into place. Links are made the same
//! way. Unchanged files and links are not touched.

const std = @import("std");
const Plan = @import("Plan.zig");

/// Which file a failed `writePlan` was working on, as the app wrote it.
pub const Failure = struct {
    path: []const u8 = "",
};

/// Writes every changed file of `plan`. A failure before the renames leaves the disk as it was.
/// A rename failing halfway (rare: same directory, already created) can leave earlier files
/// replaced. Symlinked files are written through to their target, and a replaced file keeps
/// its permissions. A planned link replaces the link at its path, never a file.
pub fn writePlan(allocator: std.mem.Allocator, io: std.Io, plan: *const Plan, failure: *Failure) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var pending: std.ArrayList(std.Io.File.Atomic) = .empty;
    defer for (pending.items) |*atomic| atomic.deinit(io);
    var pending_links: std.ArrayList(PendingLink) = .empty;
    defer for (pending_links.items) |link| link.discard(io);

    for (plan.files.items) |file| {
        if (!file.changed()) continue;
        failure.path = file.display_path;
        var atomic = try createTemp(arena.allocator(), io, file.path, file.old != null, file.executable);
        errdefer atomic.deinit(io);
        try writeContents(io, &atomic, file.new);
        try pending.append(arena.allocator(), atomic);
    }
    for (plan.links.items) |*link| {
        if (!link.changed()) continue;
        failure.path = link.display_path;
        try pending_links.ensureUnusedCapacity(arena.allocator(), 1);
        pending_links.appendAssumeCapacity(try createTempLink(arena.allocator(), io, link));
    }
    for (pending.items, 0..) |*atomic, index| {
        failure.path = changedFile(plan, index).display_path;
        try atomic.replace(io);
    }
    for (pending_links.items) |*link| {
        failure.path = link.planned.display_path;
        try std.Io.Dir.renameAbsolute(link.temp_path, link.planned.path, io);
        link.renamed = true;
    }
    failure.path = "";
}

/// A link made under a temp name next to its final path, waiting to be renamed there.
const PendingLink = struct {
    planned: *const Plan.Link,
    temp_path: []const u8,
    renamed: bool = false,

    /// Deletes the temp link unless it was renamed into place.
    fn discard(link: PendingLink, io: std.Io) void {
        if (!link.renamed) std.Io.Dir.deleteFileAbsolute(io, link.temp_path) catch {};
    }
};

fn createTempLink(allocator: std.mem.Allocator, io: std.Io, link: *const Plan.Link) !PendingLink {
    const folder = std.Io.Dir.path.dirname(link.path) orelse return error.FileNotFound;
    try std.Io.Dir.cwd().createDirPath(io, folder);
    while (true) {
        var random: u64 = undefined;
        io.random(std.mem.asBytes(&random));
        const temp_path = try allocator.print("{s}.kosm-{s}", .{ link.path, &std.fmt.hex(random) });
        if (std.Io.Dir.cwd().symLink(io, link.target, temp_path, .{})) {
            return .{ .planned = link, .temp_path = temp_path };
        } else |err| switch (err) {
            error.PathAlreadyExists => continue,
            else => return err,
        }
    }
}

fn createTemp(allocator: std.mem.Allocator, io: std.Io, path: []const u8, exists: bool, executable: bool) !std.Io.File.Atomic {
    const cwd = std.Io.Dir.cwd();
    var target = path;
    var permissions: std.Io.File.Permissions = .default_file;
    if (exists) {
        // Replacing a symlink with a file would cut it loose from the dotfiles it points into.
        target = try cwd.realPathFileAlloc(io, path, allocator);
        permissions = (try cwd.statFile(io, target, .{})).permissions;
    }
    // Whoever may read the file may run it, as `chmod +x` under a umask does.
    if (executable) permissions = .fromMode(permissions.toMode() | ((permissions.toMode() & 0o444) >> 2));
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

test "an executable file is created runnable, and an existing one gains the bits with unchanged contents" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "existing.sh", .data = "same\n" });
    try tmp.dir.setFilePermissions(testing.io, "existing.sh", .fromMode(0o640), .{});
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = try tmpPath(&tmp, &root_buffer);

    var plan: Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    const existing = try std.Io.Dir.path.join(testing.allocator, &.{ root, "existing.sh" });
    defer testing.allocator.free(existing);
    const created = try std.Io.Dir.path.join(testing.allocator, &.{ root, "created.sh" });
    defer testing.allocator.free(created);
    try plan.add(existing, "~/existing.sh", "browser", "same\n");
    try plan.add(created, "~/created.sh", "browser", "#!/bin/sh\n");
    for (plan.files.items) |*file| file.executable = true;
    try testing.expect(plan.files.items[0].changed());

    var failure: Failure = .{};
    try writePlan(testing.allocator, testing.io, &plan, &failure);

    try testing.expectEqual(0o750, (try tmp.dir.statFile(testing.io, "existing.sh", .{})).permissions.toMode() & 0o777);
    try testing.expect((try tmp.dir.statFile(testing.io, "created.sh", .{})).permissions.toMode() & 0o100 != 0);
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
    try testing.expectError(error.EditsOverlap, plan.add("/nonexistent/kosm-test/a.conf", "~/a.conf", "two", "2\n"));
    try testing.expectEqualStrings("one", plan.find("/nonexistent/kosm-test/a.conf").?.owner());
}

fn readTmpLink(tmp: *testing.TmpDir, name: []const u8, buffer: []u8) ![]const u8 {
    return buffer[0..try tmp.dir.readLink(testing.io, name, buffer)];
}

test "links are made, replaced and left alone when unchanged, creating folders" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(testing.io, "old.svg", "replaced.svg", .{});
    try tmp.dir.symLink(testing.io, "same.svg", "kept.svg", .{});
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = try tmpPath(&tmp, &root_buffer);

    var plan: Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    const created = try std.Io.Dir.path.join(testing.allocator, &.{ root, "apps/new.svg" });
    defer testing.allocator.free(created);
    const replaced = try std.Io.Dir.path.join(testing.allocator, &.{ root, "replaced.svg" });
    defer testing.allocator.free(replaced);
    const kept = try std.Io.Dir.path.join(testing.allocator, &.{ root, "kept.svg" });
    defer testing.allocator.free(kept);
    try plan.addLink(created, "~/apps/new.svg", "icons", "../target.svg", null);
    try plan.addLink(replaced, "~/replaced.svg", "icons", "new.svg", null);
    try plan.addLink(kept, "~/kept.svg", "icons", "same.svg", null);
    try testing.expect(!plan.links.items[2].changed());

    const kept_before = try tmp.dir.statFile(testing.io, "kept.svg", .{ .follow_symlinks = false });
    var failure: Failure = .{};
    try writePlan(testing.allocator, testing.io, &plan, &failure);

    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try testing.expectEqualStrings("../target.svg", try readTmpLink(&tmp, "apps/new.svg", &buffer));
    try testing.expectEqualStrings("new.svg", try readTmpLink(&tmp, "replaced.svg", &buffer));
    const kept_after = try tmp.dir.statFile(testing.io, "kept.svg", .{ .follow_symlinks = false });
    try testing.expectEqual(kept_before.inode, kept_after.inode);
}

test "a link never replaces a file, and a failed commit leaves no temp link" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "file.svg", .data = "<svg/>" });
    try tmp.dir.createDirPath(testing.io, "locked");
    try tmp.dir.setFilePermissions(testing.io, "locked", .fromMode(0o500), .{});
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = try tmpPath(&tmp, &root_buffer);

    var plan: Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    const file = try std.Io.Dir.path.join(testing.allocator, &.{ root, "file.svg" });
    defer testing.allocator.free(file);
    try testing.expectError(error.NotALink, plan.addLink(file, "~/file.svg", "icons", "other.svg", null));
    try testing.expectError(error.AlreadyPlanned, blk: {
        try plan.add(file, "~/file.svg", "icons", "<svg/>");
        break :blk plan.addLink(file, "~/file.svg", "icons", "other.svg", null);
    });

    const first = try std.Io.Dir.path.join(testing.allocator, &.{ root, "first.svg" });
    defer testing.allocator.free(first);
    const impossible = try std.Io.Dir.path.join(testing.allocator, &.{ root, "locked/second.svg" });
    defer testing.allocator.free(impossible);
    try plan.addLink(first, "~/first.svg", "icons", "file.svg", null);
    try plan.addLink(impossible, "~/locked/second.svg", "icons", "../file.svg", null);
    try testing.expectError(error.AlreadyPlanned, plan.addLink(first, "~/first.svg", "icons", "file.svg", null));

    var failure: Failure = .{};
    try testing.expect(std.meta.isError(writePlan(testing.allocator, testing.io, &plan, &failure)));
    try testing.expectEqualStrings("~/locked/second.svg", failure.path);
    var directory = try tmp.dir.openDir(testing.io, ".", .{ .iterate = true });
    defer directory.close(testing.io);
    var iterator = directory.iterate();
    var count: usize = 0;
    while (try iterator.next(testing.io)) |_| count += 1;
    try testing.expectEqual(2, count); // file.svg and locked, no link or temp link
}
