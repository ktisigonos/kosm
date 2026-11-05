//! Every file an apply will write, with its old and new contents, computed in memory before
//! anything is written (D36). Owns all of its memory.

const Plan = @This();

const std = @import("std");

allocator: std.mem.Allocator,
io: std.Io,
files: std.ArrayList(File) = .empty,

/// One planned file.
pub const File = @import("Plan/File.zig");

/// Larger files are refused rather than read whole.
const max_file_size = 64 * 1024 * 1024;

/// An empty plan reading current contents through `io`.
pub fn init(allocator: std.mem.Allocator, io: std.Io) Plan {
    return .{ .allocator = allocator, .io = io };
}

/// Frees every planned file.
pub fn deinit(plan: *Plan) void {
    for (plan.files.items) |file| {
        plan.allocator.free(file.path);
        plan.allocator.free(file.display_path);
        plan.allocator.free(file.owner);
        if (file.old) |old| plan.allocator.free(old);
        plan.allocator.free(file.new);
    }
    plan.files.deinit(plan.allocator);
    plan.* = undefined;
}

/// Errors from `add`.
pub const AddError = std.mem.Allocator.Error || std.Io.Dir.ReadFileAllocError || error{FileWrittenTwice};

/// Plans `content` as the whole of the file at absolute `path`, reading what is there now.
/// A path already in the plan is `error.FileWrittenTwice` (D38); `find` names its owner.
/// Copies every argument.
pub fn add(plan: *Plan, path: []const u8, display_path: []const u8, owner: []const u8, content: []const u8) AddError!void {
    if (plan.find(path) != null) return error.FileWrittenTwice;
    const old = std.Io.Dir.cwd().readFileAlloc(plan.io, path, plan.allocator, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    errdefer if (old) |bytes| plan.allocator.free(bytes);
    const owned_path = try plan.allocator.dupe(u8, path);
    errdefer plan.allocator.free(owned_path);
    const owned_display_path = try plan.allocator.dupe(u8, display_path);
    errdefer plan.allocator.free(owned_display_path);
    const owned_owner = try plan.allocator.dupe(u8, owner);
    errdefer plan.allocator.free(owned_owner);
    const owned_content = try plan.allocator.dupe(u8, content);
    errdefer plan.allocator.free(owned_content);
    try plan.files.append(plan.allocator, .{
        .path = owned_path,
        .display_path = owned_display_path,
        .owner = owned_owner,
        .old = old,
        .new = owned_content,
    });
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
