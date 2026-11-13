//! Every file an apply will write, with its old contents and the edits apps planned in it,
//! computed in memory before anything is written. Owns all of its memory.

const Plan = @This();

const std = @import("std");

allocator: std.mem.Allocator,
io: std.Io,
files: std.ArrayList(File) = .empty,
links: std.ArrayList(Link) = .empty,
/// Index into `files` by absolute path; plans of thousands of files stay fast.
file_index: std.StringHashMapUnmanaged(usize) = .empty,
/// Index into `links` by absolute path.
link_index: std.StringHashMapUnmanaged(usize) = .empty,

/// One planned file.
pub const File = @import("Plan/File.zig");
/// One planned change inside a file.
pub const Edit = @import("Plan/Edit.zig");
/// One planned symbolic link.
pub const Link = @import("Plan/Link.zig");

/// Larger files are refused rather than read whole.
pub const max_file_size = 64 * 1024 * 1024;

/// An empty plan reading current contents through `io`.
pub fn init(allocator: std.mem.Allocator, io: std.Io) Plan {
    return .{ .allocator = allocator, .io = io };
}

/// Frees every planned file.
pub fn deinit(plan: *Plan) void {
    for (plan.files.items) |*file| {
        plan.allocator.free(file.path);
        plan.allocator.free(file.display_path);
        if (file.old) |old| plan.allocator.free(old);
        for (file.edits.items) |edit| plan.freeEdit(edit);
        file.edits.deinit(plan.allocator);
        plan.allocator.free(file.new);
        if (file.group) |group| plan.allocator.free(group);
    }
    plan.files.deinit(plan.allocator);
    for (plan.links.items) |link| plan.freeLink(link);
    plan.links.deinit(plan.allocator);
    plan.file_index.deinit(plan.allocator);
    plan.link_index.deinit(plan.allocator);
    plan.* = undefined;
}

/// Errors from `load`.
pub const LoadError = std.mem.Allocator.Error || std.Io.Dir.ReadFileAllocError;

/// The planned file at absolute `path`, reading what is there now when it is new to the plan.
/// The pointer is valid until the next `load` or `add`. Copies both paths.
pub fn load(plan: *Plan, path: []const u8, display_path: []const u8) LoadError!*File {
    if (plan.findPlanned(path)) |file| return file;
    return plan.append(path, display_path, try plan.read(path));
}

/// Like `load`, but a file that is neither on disk nor planned is null, and stays out of the
/// plan.
pub fn loadExisting(plan: *Plan, path: []const u8, display_path: []const u8) LoadError!?*File {
    if (plan.findPlanned(path)) |file| return file;
    const old = try plan.read(path) orelse return null;
    return try plan.append(path, display_path, old);
}

fn findPlanned(plan: *Plan, path: []const u8) ?*File {
    const index = plan.file_index.get(path) orelse return null;
    return &plan.files.items[index];
}

/// The file's contents, or null when it does not exist.
fn read(plan: *Plan, path: []const u8) LoadError!?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(plan.io, path, plan.allocator, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => err,
    };
}

/// Whether the file at `path` has an execute bit; a file that can't be looked at has none.
fn isExecutable(plan: *Plan, path: []const u8) bool {
    const stat = std.Io.Dir.cwd().statFile(plan.io, path, .{}) catch return false;
    return stat.permissions.toMode() & executable_bits != 0;
}

/// The mode bits that let a file be run.
pub const executable_bits = 0o111;

/// Adds a file to the plan, taking ownership of `old`.
fn append(plan: *Plan, path: []const u8, display_path: []const u8, old: ?[]u8) LoadError!*File {
    errdefer if (old) |bytes| plan.allocator.free(bytes);
    const owned_path = try plan.allocator.dupe(u8, path);
    errdefer plan.allocator.free(owned_path);
    const owned_display_path = try plan.allocator.dupe(u8, display_path);
    errdefer plan.allocator.free(owned_display_path);
    const new = try plan.allocator.dupe(u8, old orelse "");
    errdefer plan.allocator.free(new);
    const was_executable = old != null and plan.isExecutable(path);
    try plan.file_index.ensureUnusedCapacity(plan.allocator, 1);
    try plan.files.append(plan.allocator, .{ .path = owned_path, .display_path = owned_display_path, .old = old, .new = new, .was_executable = was_executable });
    plan.file_index.putAssumeCapacity(owned_path, plan.files.items.len - 1);
    return &plan.files.items[plan.files.items.len - 1];
}

/// Shows `file` in diffs and reports as part of the folder `group`, one line for all of them.
/// Copies `group`.
pub fn setGroup(plan: *Plan, file: *File, group: []const u8) std.mem.Allocator.Error!void {
    const owned = try plan.allocator.dupe(u8, group);
    if (file.group) |old| plan.allocator.free(old);
    file.group = owned;
}

/// Errors from `addLink`.
pub const LinkError = std.mem.Allocator.Error || std.Io.Dir.ReadLinkError || error{
    /// Something other than a link is at the path; kosm replaces only links.
    NotALink,
    /// The path is already planned, as a file or as a link.
    AlreadyPlanned,
};

/// Plans a symbolic link at absolute `path` pointing to `target`, reading what is there now.
/// A path planned before, as a link or a file, is `error.AlreadyPlanned`. Copies every argument.
pub fn addLink(plan: *Plan, path: []const u8, display_path: []const u8, owner: []const u8, target: []const u8, group: ?[]const u8) LinkError!void {
    if (plan.file_index.contains(path) or plan.link_index.contains(path)) return error.AlreadyPlanned;
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const old_target: ?[]const u8 = if (std.Io.Dir.readLinkAbsolute(plan.io, path, &buffer)) |length|
        buffer[0..length]
    else |err| switch (err) {
        error.FileNotFound => null,
        error.NotLink => return error.NotALink,
        else => |other| return other,
    };

    var link: Link = .{ .path = "", .display_path = "", .target = "", .old_target = null, .owner = "", .group = null };
    errdefer plan.freeLink(link);
    link.path = try plan.allocator.dupe(u8, path);
    link.display_path = try plan.allocator.dupe(u8, display_path);
    link.target = try plan.allocator.dupe(u8, target);
    link.owner = try plan.allocator.dupe(u8, owner);
    if (old_target) |bytes| link.old_target = try plan.allocator.dupe(u8, bytes);
    if (group) |bytes| link.group = try plan.allocator.dupe(u8, bytes);
    try plan.link_index.ensureUnusedCapacity(plan.allocator, 1);
    try plan.links.append(plan.allocator, link);
    plan.link_index.putAssumeCapacity(link.path, plan.links.items.len - 1);
}

fn freeLink(plan: *Plan, link: Link) void {
    plan.allocator.free(link.path);
    plan.allocator.free(link.display_path);
    plan.allocator.free(link.target);
    if (link.old_target) |old_target| plan.allocator.free(old_target);
    plan.allocator.free(link.owner);
    if (link.group) |group| plan.allocator.free(group);
}

/// The planned link at absolute `path`, if any.
pub fn findLink(plan: *const Plan, path: []const u8) ?*const Link {
    const index = plan.link_index.get(path) orelse return null;
    return &plan.links.items[index];
}

/// Errors from `addEdit`.
pub const EditError = std.mem.Allocator.Error || error{EditsOverlap};

/// Plans `edit` in `file` and updates `file.new`. An edit clashing with a planned one is
/// `error.EditsOverlap`; `File.clash` names it. Copies the edit's slices.
pub fn addEdit(plan: *Plan, file: *File, edit: Edit) EditError!void {
    std.debug.assert(edit.start <= edit.end and edit.end <= file.current().len);
    if (file.clash(edit) != null) return error.EditsOverlap;
    const owned = try plan.copyEdit(edit);
    errdefer plan.freeEdit(owned);
    try file.edits.append(plan.allocator, owned);
    errdefer _ = file.edits.pop();
    const new = try applyEdits(plan.allocator, file.current(), file.edits.items);
    plan.allocator.free(file.new);
    file.new = new;
}

/// Errors from `add`.
pub const AddError = LoadError || EditError;

/// Plans `content` as the whole of the file at absolute `path`. Copies every argument.
pub fn add(plan: *Plan, path: []const u8, display_path: []const u8, owner: []const u8, content: []const u8) AddError!void {
    const file = try plan.load(path, display_path);
    try plan.addEdit(file, .{ .target = .whole_file, .start = 0, .end = file.current().len, .content = content, .owner = owner });
}

/// The planned file at absolute `path`, if any.
pub fn find(plan: *const Plan, path: []const u8) ?*const File {
    const index = plan.file_index.get(path) orelse return null;
    return &plan.files.items[index];
}

/// Whether committing would change anything on disk.
pub fn hasChanges(plan: *const Plan) bool {
    for (plan.files.items) |file| {
        if (file.changed()) return true;
    }
    for (plan.links.items) |link| {
        if (link.changed()) return true;
    }
    return false;
}

/// The changed files and links of one group, counted for diffs and reports.
pub const GroupCount = struct {
    group: []const u8,
    files: usize = 0,
    links: usize = 0,

    /// Prints `<group>: 3 files and 1 link`, leaving out a kind with none.
    pub fn format(count: GroupCount, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s}: ", .{count.group});
        if (count.files != 0) try writer.print("{d} file{s}", .{ count.files, plural(count.files) });
        if (count.files != 0 and count.links != 0) try writer.writeAll(" and ");
        if (count.links != 0) try writer.print("{d} link{s}", .{ count.links, plural(count.links) });
    }

    fn plural(number: usize) []const u8 {
        return if (number == 1) "" else "s";
    }
};

/// Every group with changes, in the order first planned. Caller frees the slice; the names
/// belong to the plan.
pub fn changedGroups(plan: *const Plan, allocator: std.mem.Allocator) std.mem.Allocator.Error![]GroupCount {
    var counts: std.ArrayList(GroupCount) = .empty;
    errdefer counts.deinit(allocator);
    for (plan.files.items) |file| {
        const group = file.group orelse continue;
        if (file.changed()) (try countFor(allocator, &counts, group)).files += 1;
    }
    for (plan.links.items) |link| {
        const group = link.group orelse continue;
        if (link.changed()) (try countFor(allocator, &counts, group)).links += 1;
    }
    return counts.toOwnedSlice(allocator);
}

fn countFor(allocator: std.mem.Allocator, counts: *std.ArrayList(GroupCount), group: []const u8) std.mem.Allocator.Error!*GroupCount {
    for (counts.items) |*count| {
        if (std.mem.eql(u8, count.group, group)) return count;
    }
    try counts.append(allocator, .{ .group = group });
    return &counts.items[counts.items.len - 1];
}

fn copyEdit(plan: *Plan, edit: Edit) std.mem.Allocator.Error!Edit {
    var owned = edit;
    owned.content = try plan.allocator.dupe(u8, edit.content);
    errdefer plan.allocator.free(owned.content);
    owned.owner = try plan.allocator.dupe(u8, edit.owner);
    errdefer plan.allocator.free(owned.owner);
    if (edit.target == .block) owned.target = .{ .block = try plan.allocator.dupe(u8, edit.target.block) };
    return owned;
}

fn freeEdit(plan: *Plan, edit: Edit) void {
    plan.allocator.free(edit.content);
    plan.allocator.free(edit.owner);
    if (edit.target == .block) plan.allocator.free(edit.target.block);
}

/// `old` with every edit applied. Edits never overlap; insertions at one offset keep the order
/// they were planned in, and come before a range starting there.
fn applyEdits(allocator: std.mem.Allocator, old: []const u8, edits: []const Edit) std.mem.Allocator.Error![]u8 {
    const order = try allocator.alloc(usize, edits.len);
    defer allocator.free(order);
    for (order, 0..) |*index, position| index.* = position;
    std.sort.insertion(usize, order, edits, startsBefore);

    var new: std.ArrayList(u8) = .empty;
    errdefer new.deinit(allocator);
    var cursor: usize = 0;
    for (order) |index| {
        const edit = edits[index];
        try new.appendSlice(allocator, old[cursor..edit.start]);
        try new.appendSlice(allocator, edit.content);
        cursor = edit.end;
    }
    try new.appendSlice(allocator, old[cursor..]);
    return new.toOwnedSlice(allocator);
}

fn startsBefore(edits: []const Edit, left: usize, right: usize) bool {
    if (edits[left].start != edits[right].start) return edits[left].start < edits[right].start;
    return edits[left].end < edits[right].end;
}

const testing = std.testing;

test "edits apply by position whatever order they were planned in" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "a.conf", .data = "0123456789" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(testing.io, &buffer);
    const path = try std.Io.Dir.path.join(testing.allocator, &.{ buffer[0..length], "a.conf" });
    defer testing.allocator.free(path);

    var plan: Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    const file = try plan.load(path, "~/a.conf");
    try plan.addEdit(file, .{ .target = .{ .block = "late" }, .start = 6, .end = 8, .content = "B", .owner = "one" });
    try plan.addEdit(file, .{ .target = .{ .block = "end1" }, .start = 10, .end = 10, .content = "X", .owner = "two" });
    try plan.addEdit(file, .{ .target = .{ .block = "early" }, .start = 1, .end = 3, .content = "AAA", .owner = "two" });
    try plan.addEdit(file, .{ .target = .{ .block = "end2" }, .start = 10, .end = 10, .content = "Y", .owner = "one" });
    try plan.addEdit(file, .{ .target = .{ .block = "at" }, .start = 6, .end = 6, .content = "i", .owner = "one" });
    try testing.expectEqualStrings("0AAA345iB89XY", file.new);
    try testing.expectEqualStrings("", file.owner());

    try testing.expectError(error.EditsOverlap, plan.addEdit(file, .{ .target = .{ .block = "other" }, .start = 2, .end = 4, .content = "", .owner = "three" }));
    try testing.expectEqualStrings("one", file.clash(.{ .target = .whole_file, .start = 0, .end = 10, .content = "", .owner = "three" }).?.owner);
    try testing.expectEqualStrings("0AAA345iB89XY", file.new);
}
