//! Loads the images a kosmos names in its `Params` before the kosmos runs. ImageMagick decodes
//! each one, shrunk, into a PPM that kosm reads. That PPM is cached in the config's Zig cache
//! under the image's path, size and modification time, so only a new or changed image is decoded.

const std = @import("std");
const kosm = @import("kosm");
const params = @import("params.zig");

/// What loading needs from the runner.
pub const Context = struct {
    /// Holds the pixels for the whole run.
    arena: std.mem.Allocator,
    io: std.Io,
    /// What `~/` in an image's path stands for.
    home: []const u8,
    /// The folder decoded images are cached in; null caches nothing.
    cache: ?[]const u8,
    diagnostics: *kosm.Diagnostics,
    /// Where a failed cache write is reported; it never fails the apply.
    stderr: *std.Io.Writer,
};

pub const Error = error{Reported} || std.mem.Allocator.Error || std.Io.Writer.Error;

/// The cache folder inside a config project.
pub const cache_folder = ".zig-cache/kosm/images";

/// ImageMagick shrinks an image to fit this, keeping its aspect: plenty for its colors, and
/// quick to read. `-sample` picks pixels instead of averaging them, which is twice as fast.
const geometry = "256x256>";
/// The longest PPM a `geometry`-sized image gives, with room for its header.
const output_limit = 256 * 256 * 6 + 64;

/// Loads the pixels of every `kosm.Image` (or non-null `?kosm.Image`) field of `params_value`.
pub fn fill(comptime Params: type, params_value: *Params, context: Context) Error!void {
    const fields = @typeInfo(Params).@"struct";
    inline for (fields.field_names, fields.field_types) |name, Field| {
        if (comptime !params.isImage(Field)) continue;
        if (Field == kosm.Image) {
            const image = &@field(params_value, name);
            image.pixels = try load(context, name, image.path);
        } else if (@field(params_value, name)) |*image| {
            image.pixels = try load(context, name, image.path);
        }
    }
}

fn load(context: Context, comptime name: []const u8, path: []const u8) Error![]const kosm.Color {
    const full_path = try resolve(context, name, path);
    const stat = std.Io.Dir.cwd().statFile(context.io, full_path, .{}) catch |err|
        return fail(context, name, path, "cannot read the image: {s}", .{@errorName(err)});
    if (stat.kind != .file) return fail(context, name, path, "the image is not a file", .{});

    const cache_path = if (context.cache) |folder| try cachePath(context.arena, folder, full_path, stat) else null;
    if (cache_path) |cached| {
        // The cache is only a shortcut: a missing or unreadable entry is decoded again.
        if (readCache(context, cached)) |bytes| {
            if (parsePpm(context.arena, bytes)) |pixels| return pixels else |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {},
            }
        }
    }

    const bytes = try decode(context, name, path, full_path);
    const pixels = parsePpm(context.arena, bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return fail(context, name, path, "ImageMagick's output is not a PPM image: {s}", .{@errorName(err)}),
    };
    if (cache_path) |cached| writeCache(context, cached, bytes) catch |err| {
        try kosm.Diagnostics.writeReport(context.stderr, "warning", context.diagnostics.kosmos, "", path, try context.arena.print("cannot cache the decoded image in {s}: {s}", .{ cached, @errorName(err) }));
    };
    return pixels;
}

fn resolve(context: Context, comptime name: []const u8, path: []const u8) Error![]const u8 {
    if (std.mem.startsWith(u8, path, "~/")) return std.Io.Dir.path.join(context.arena, &.{ context.home, path[2..] });
    if (std.Io.Dir.path.isAbsolute(path)) return path;
    return fail(context, name, path, "image paths start with ~/ or /", .{});
}

/// The cache entry of the image at `full_path` as `stat` describes it; a changed size or
/// modification time gives a new entry.
pub fn cachePath(arena: std.mem.Allocator, folder: []const u8, full_path: []const u8, stat: std.Io.File.Stat) std.mem.Allocator.Error![]const u8 {
    const entry = try arena.print("{x:0>16}-{d}-{d}.ppm", .{ std.hash.Wyhash.hash(0, full_path), stat.size, stat.mtime.nanoseconds });
    return std.Io.Dir.path.join(arena, &.{ folder, entry });
}

fn readCache(context: Context, cache_path: []const u8) ?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(context.io, cache_path, context.arena, .limited(output_limit)) catch null;
}

fn writeCache(context: Context, cache_path: []const u8, bytes: []const u8) !void {
    var atomic = try std.Io.Dir.cwd().createFileAtomic(context.io, cache_path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(context.io);
    try atomic.file.writeStreamingAll(context.io, bytes);
    try atomic.replace(context.io);
}

/// Runs ImageMagick on the image's first frame (`[0]`, which also keeps brackets in the file
/// name from being read as a frame list) and returns the PPM it prints.
fn decode(context: Context, comptime name: []const u8, path: []const u8, full_path: []const u8) Error![]const u8 {
    const input = try context.arena.print("{s}[0]", .{full_path});
    const result = std.process.run(context.arena, context.io, .{
        .argv = &.{ "magick", input, "-sample", geometry, "-colorspace", "sRGB", "-depth", "8", "ppm:-" },
        .stdout_limit = .limited(output_limit),
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return fail(context, name, path, "decoding the image needs ImageMagick's magick command, which is not installed", .{}),
        else => return fail(context, name, path, "cannot run ImageMagick's magick: {s}", .{@errorName(err)}),
    };
    if (!result.term.success()) {
        const message = std.mem.trim(u8, result.stderr, " \n");
        return fail(context, name, path, "ImageMagick cannot decode the image: {s}", .{message[0 .. std.mem.findScalar(u8, message, '\n') orelse message.len]});
    }
    return result.stdout;
}

pub const PpmError = error{ NotPpm, BadHeader, Truncated } || std.mem.Allocator.Error;

/// The pixels of a binary PPM (`P6`), with a maximum value up to 65535.
pub fn parsePpm(allocator: std.mem.Allocator, bytes: []const u8) PpmError![]const kosm.Color {
    if (!std.mem.startsWith(u8, bytes, "P6")) return error.NotPpm;
    var position: usize = 2;
    const width = try headerNumber(bytes, &position);
    const height = try headerNumber(bytes, &position);
    const maximum = try headerNumber(bytes, &position);
    if (width == 0 or height == 0 or maximum == 0 or maximum > 65535) return error.BadHeader;
    if (position >= bytes.len or !std.ascii.isWhitespace(bytes[position])) return error.Truncated;
    position += 1;

    const channel_size: usize = if (maximum > 255) 2 else 1;
    const pixel_count = std.math.mul(usize, width, height) catch return error.BadHeader;
    const data_length = std.math.mul(usize, pixel_count, 3 * channel_size) catch return error.BadHeader;
    if (bytes.len - position < data_length) return error.Truncated;
    const data = bytes[position..][0..data_length];

    const pixels = try allocator.alloc(kosm.Color, pixel_count);
    const scale: f64 = @floatFromInt(maximum);
    for (pixels, 0..) |*pixel, index| {
        var channels: [3]f64 = undefined;
        for (&channels, 0..) |*channel, offset| {
            const at = (index * 3 + offset) * channel_size;
            const value: u16 = if (channel_size == 2) std.mem.readInt(u16, data[at..][0..2], .big) else data[at];
            channel.* = @as(f64, @floatFromInt(value)) / scale;
        }
        pixel.* = .fromRgb(.{ .red = channels[0], .green = channels[1], .blue = channels[2] });
    }
    return pixels;
}

/// Skips whitespace and `#` comments, then reads a decimal number.
fn headerNumber(bytes: []const u8, position: *usize) PpmError!usize {
    while (position.* < bytes.len) {
        if (std.ascii.isWhitespace(bytes[position.*])) {
            position.* += 1;
        } else if (bytes[position.*] == '#') {
            position.* = std.mem.findScalarPos(u8, bytes, position.*, '\n') orelse bytes.len;
        } else break;
    }
    const start = position.*;
    while (position.* < bytes.len and std.ascii.isDigit(bytes[position.*])) position.* += 1;
    if (position.* == start) return if (position.* == bytes.len) error.Truncated else error.BadHeader;
    return std.fmt.parseInt(usize, bytes[start..position.*], 10) catch error.BadHeader;
}

fn fail(context: Context, comptime name: []const u8, path: []const u8, comptime format: []const u8, arguments: anytype) error{Reported} {
    context.diagnostics.set("", path, "Params." ++ name ++ ": " ++ format, arguments);
    return error.Reported;
}

const testing = std.testing;

test "a PPM's pixels are read as colors, 8 or 16 bits per channel" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const eight = try parsePpm(arena, "P6\n# made by a test\n2 1\n255\n\xff\x00\x00\x00\x00\xff");
    try testing.expectEqual(2, eight.len);
    try testing.expectEqualStrings("#ff0000", eight[0].hex().slice());
    try testing.expectEqualStrings("#0000ff", eight[1].hex().slice());
    const sixteen = try parsePpm(arena, "P6 1 1 65535 \xff\xff\x80\x00\x00\x00");
    try testing.expectEqualStrings("#ff8000", sixteen[0].hex().slice());
}

test "bad and cut-short PPMs are errors" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectError(error.NotPpm, parsePpm(arena, "P3\n1 1\n255\n0 0 0\n"));
    try testing.expectError(error.BadHeader, parsePpm(arena, "P6\n0 1\n255\n"));
    try testing.expectError(error.BadHeader, parsePpm(arena, "P6\n1 x\n255\n"));
    try testing.expectError(error.BadHeader, parsePpm(arena, "P6\n1 1\n70000\n\x00\x00\x00"));
    try testing.expectError(error.Truncated, parsePpm(arena, "P6\n2 1\n255\n\x00\x00\x00"));
    try testing.expectError(error.Truncated, parsePpm(arena, "P6\n2 1"));
    try testing.expectError(error.Truncated, parsePpm(arena, "P6\n1 1\n255"));
}

/// A loading context over a temporary folder, with the diagnostics and stderr it reports to.
const Fixture = struct {
    tmp: std.testing.TmpDir,
    arena_state: std.heap.ArenaAllocator,
    root: []const u8,
    diagnostics: kosm.Diagnostics = .{ .kosmos = "test" },
    stderr: std.Io.Writer.Allocating,

    fn init() !Fixture {
        var tmp = testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
        const root = try tmp.dir.realPathFileAlloc(testing.io, ".", arena_state.allocator());
        return .{ .tmp = tmp, .arena_state = arena_state, .root = root, .stderr = .init(testing.allocator) };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.stderr.deinit();
        fixture.arena_state.deinit();
        fixture.tmp.cleanup();
    }

    fn context(fixture: *Fixture, cache: ?[]const u8) Context {
        return .{
            .arena = fixture.arena_state.allocator(),
            .io = testing.io,
            .home = fixture.root,
            .cache = cache,
            .diagnostics = &fixture.diagnostics,
            .stderr = &fixture.stderr.writer,
        };
    }
};

fn hasMagick() bool {
    const result = std.process.run(testing.allocator, testing.io, .{ .argv = &.{ "magick", "-version" } }) catch return false;
    testing.allocator.free(result.stdout);
    testing.allocator.free(result.stderr);
    return result.term.success();
}

test "an image is decoded once, then read from the cache until it changes" {
    if (!hasMagick()) return error.SkipZigTest;
    var fixture: Fixture = try .init();
    defer fixture.deinit();
    const cache = try std.Io.Dir.path.join(fixture.arena_state.allocator(), &.{ fixture.root, cache_folder });
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "red.ppm", .data = "P6 1 1 255 \xff\x00\x00" });

    const Params = struct { wallpaper: kosm.Image = .{ .path = "~/red.ppm" }, lock: ?kosm.Image = null };
    var first: Params = .{};
    try fill(Params, &first, fixture.context(cache));
    try testing.expectEqualStrings("#ff0000", first.wallpaper.pixels[0].hex().slice());
    try testing.expectEqual(null, first.lock);

    // A cache entry holding another color shows the second load reads the cache, not the image.
    const stat = try fixture.tmp.dir.statFile(testing.io, "red.ppm", .{});
    const entry = try cachePath(fixture.arena_state.allocator(), cache, try std.Io.Dir.path.join(fixture.arena_state.allocator(), &.{ fixture.root, "red.ppm" }), stat);
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = entry, .data = "P6 1 1 255 \x00\xff\x00" });
    var second: Params = .{};
    try fill(Params, &second, fixture.context(cache));
    try testing.expectEqualStrings("#00ff00", second.wallpaper.pixels[0].hex().slice());

    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "red.ppm", .data = "P6 2 1 255 \x00\x00\xff\x00\x00\xff" });
    var changed: Params = .{};
    try fill(Params, &changed, fixture.context(cache));
    try testing.expectEqual(2, changed.wallpaper.pixels.len);
    try testing.expectEqualStrings("#0000ff", changed.wallpaper.pixels[0].hex().slice());
}

test "a missing image, a relative path and an image ImageMagick cannot read name the parameter and the file" {
    var fixture: Fixture = try .init();
    defer fixture.deinit();
    const Params = struct { wallpaper: kosm.Image };

    var missing: Params = .{ .wallpaper = .{ .path = "~/missing.jxl" } };
    try testing.expectError(error.Reported, fill(Params, &missing, fixture.context(null)));
    try testing.expectEqualStrings("~/missing.jxl", fixture.diagnostics.file);
    try testing.expectEqualStrings("Params.wallpaper: cannot read the image: FileNotFound", fixture.diagnostics.message());

    var relative: Params = .{ .wallpaper = .{ .path = "missing.jxl" } };
    try testing.expectError(error.Reported, fill(Params, &relative, fixture.context(null)));
    try testing.expectEqualStrings("Params.wallpaper: image paths start with ~/ or /", fixture.diagnostics.message());

    if (!hasMagick()) return error.SkipZigTest;
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "broken.png", .data = "not a png" });
    var broken: Params = .{ .wallpaper = .{ .path = "~/broken.png" } };
    try testing.expectError(error.Reported, fill(Params, &broken, fixture.context(null)));
    try testing.expect(std.mem.startsWith(u8, fixture.diagnostics.message(), "Params.wallpaper: ImageMagick cannot decode the image: "));
}
