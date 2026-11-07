//! Every file an apply will write, with its old contents and the edits apps planned in it,
//! computed in memory before anything is written (D36, D73). Owns all of its memory.

const Plan = @This();

const std = @import("std");

allocator: std.mem.Allocator,
io: std.Io,
files: std.ArrayList(File) = .empty,

/// One planned file.
pub const File = @import("Plan/File.zig");
/// One planned change inside a file.
pub const Edit = @import("Plan/Edit.zig");

/// Larger files are refused rather than read whole.
const max_file_size = 64 * 1024 * 1024;

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
    }
    plan.files.deinit(plan.allocator);
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
    for (plan.files.items) |*file| {
        if (std.mem.eql(u8, file.path, path)) return file;
    }
    return null;
}

/// The file's contents, or null when it does not exist.
fn read(plan: *Plan, path: []const u8) LoadError!?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(plan.io, path, plan.allocator, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => err,
    };
}

/// Adds a file to the plan, taking ownership of `old`.
fn append(plan: *Plan, path: []const u8, display_path: []const u8, old: ?[]u8) LoadError!*File {
    errdefer if (old) |bytes| plan.allocator.free(bytes);
    const owned_path = try plan.allocator.dupe(u8, path);
    errdefer plan.allocator.free(owned_path);
    const owned_display_path = try plan.allocator.dupe(u8, display_path);
    errdefer plan.allocator.free(owned_display_path);
    const new = try plan.allocator.dupe(u8, old orelse "");
    errdefer plan.allocator.free(new);
    try plan.files.append(plan.allocator, .{ .path = owned_path, .display_path = owned_display_path, .old = old, .new = new });
    return &plan.files.items[plan.files.items.len - 1];
}

/// Errors from `addEdit`.
pub const EditError = std.mem.Allocator.Error || error{EditsOverlap};

/// Plans `edit` in `file` and updates `file.new`. An edit clashing with a planned one is
/// `error.EditsOverlap` (D38); `File.clash` names it. Copies the edit's slices.
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
    for (plan.files.items) |*file| {
        if (std.mem.eql(u8, file.path, path)) return file;
    }
    return null;
}

/// Whether committing would change anything on disk.
pub fn hasChanges(plan: *const Plan) bool {
    for (plan.files.items) |file| {
        if (file.changed()) return true;
    }
    return false;
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
