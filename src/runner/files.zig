//! Reads the files a kosmos names in its `Params` before the kosmos runs, so the kosmos itself
//! does no IO.

const std = @import("std");
const kosm = @import("kosm");
const Places = @import("Places.zig");

/// What reading needs from the runner.
pub const Context = struct {
    /// Holds the bytes for the whole run.
    arena: std.mem.Allocator,
    io: std.Io,
    /// The folders a file's path may start from.
    places: Places,
    diagnostics: *kosm.Diagnostics,
};

pub const Error = error{Reported} || std.mem.Allocator.Error;

/// The largest file kosm reads for a kosmos: far beyond any script, and a guard against
/// naming a disk image by mistake.
const size_limit = 16 * 1024 * 1024;

/// Reads the bytes of every `kosm.File` (or non-null `?kosm.File`) field of `params_value`, and
/// makes its path absolute, so the kosmos can hand it to any program.
pub fn fill(comptime Params: type, params_value: *Params, context: Context) Error!void {
    const fields = @typeInfo(Params).@"struct";
    inline for (fields.field_names, fields.field_types) |name, Field| {
        if (Field == kosm.File) {
            try read(context, name, &@field(params_value, name));
        } else if (Field == ?kosm.File) {
            if (@field(params_value, name)) |*file| try read(context, name, file);
        }
    }
}

fn read(context: Context, comptime name: []const u8, file: *kosm.File) Error!void {
    const full_path = context.places.resolve(context.arena, file.path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnknownPlace => return fail(context, name, file.path, "{s}", .{try context.places.unknownPlaceMessage(context.arena, file.path)}),
    };
    file.bytes = std.Io.Dir.cwd().readFileAlloc(context.io, full_path, context.arena, .limited(size_limit)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.IsDir => return fail(context, name, file.path, "it is a folder, not a file", .{}),
        error.StreamTooLong => return fail(context, name, file.path, "the file is larger than {d} MiB", .{size_limit / (1024 * 1024)}),
        else => return fail(context, name, file.path, "cannot read the file: {s}", .{@errorName(err)}),
    };
    file.path = full_path;
}

fn fail(context: Context, comptime name: []const u8, path: []const u8, comptime format: []const u8, arguments: anytype) error{Reported} {
    context.diagnostics.set("", path, "Params." ++ name ++ ": " ++ format, arguments);
    return error.Reported;
}

const testing = std.testing;

/// A reading context over a temporary folder, which is home, config and kosmos folder at once.
const Fixture = struct {
    tmp: std.testing.TmpDir,
    arena_state: std.heap.ArenaAllocator,
    root: []const u8,
    diagnostics: kosm.Diagnostics = .{ .kosmos = "test" },

    fn init() !Fixture {
        var tmp = testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
        const root = try tmp.dir.realPathFileAlloc(testing.io, ".", arena_state.allocator());
        return .{ .tmp = tmp, .arena_state = arena_state, .root = root };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.arena_state.deinit();
        fixture.tmp.cleanup();
    }

    fn context(fixture: *Fixture) Context {
        return .{
            .arena = fixture.arena_state.allocator(),
            .io = testing.io,
            .places = .{ .home = fixture.root, .config = fixture.root, .kosmos = fixture.root },
            .diagnostics = &fixture.diagnostics,
        };
    }
};

test "the files a kosmos names are read, an empty one too, and a null optional is skipped" {
    var fixture: Fixture = try .init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "personal.lua", .data = "return {}\n" });
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "empty.lua", .data = "" });
    const Params = struct {
        script: kosm.File = .{ .path = "./personal.lua" },
        empty: ?kosm.File = .{ .path = "~/empty.lua" },
        unused: ?kosm.File = null,
    };
    var params_value: Params = .{};
    try fill(Params, &params_value, fixture.context());
    try testing.expectEqualStrings("return {}\n", try params_value.script.contents());
    try testing.expectEqualStrings(try std.Io.Dir.path.join(fixture.arena_state.allocator(), &.{ fixture.root, "personal.lua" }), params_value.script.path);
    try testing.expectEqualStrings("", try params_value.empty.?.contents());
    try testing.expectEqual(null, params_value.unused);
}

test "a missing file, a folder and an unknown place fail naming the parameter and the path" {
    var fixture: Fixture = try .init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "scripts");
    const Params = struct { script: kosm.File };

    var missing: Params = .{ .script = .{ .path = "~~kosmos/missing.lua" } };
    try testing.expectError(error.Reported, fill(Params, &missing, fixture.context()));
    try testing.expectEqualStrings("~~kosmos/missing.lua", fixture.diagnostics.file);
    try testing.expectEqualStrings("Params.script: cannot read the file: FileNotFound", fixture.diagnostics.message());

    var folder: Params = .{ .script = .{ .path = "scripts" } };
    try testing.expectError(error.Reported, fill(Params, &folder, fixture.context()));
    try testing.expectEqualStrings("Params.script: it is a folder, not a file", fixture.diagnostics.message());

    var unknown: Params = .{ .script = .{ .path = "~nobody/x.lua" } };
    try testing.expectError(error.Reported, fill(Params, &unknown, fixture.context()));
    try testing.expect(std.mem.startsWith(u8, fixture.diagnostics.message(), "Params.script: ~nobody/ names no folder kosm knows: use ~/ (home)"));
}
