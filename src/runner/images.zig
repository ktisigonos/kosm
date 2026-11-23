//! Loads the images a kosmos names in its `Params` before the kosmos runs. ImageMagick decodes
//! each one, shrunk, into a PPM that kosm reads. That PPM is cached in the config's Zig cache
//! under the image's path, size and modification time, so only a new or changed image is decoded.

const std = @import("std");
const kosm = @import("kosm");
const params = @import("params.zig");
const Places = @import("Places.zig");

/// What loading needs from the runner.
pub const Context = struct {
    /// Holds the pixels for the whole run.
    arena: std.mem.Allocator,
    io: std.Io,
    /// The folders an image's path may start from.
    places: Places,
    /// The folder decoded images are cached in; null caches nothing.
    cache: ?[]const u8,
    diagnostics: *kosm.Diagnostics,
    /// Where a failed cache write is reported; it never fails the apply.
    stderr: *std.Io.Writer,
};

pub const Error = error{Reported} || std.mem.Allocator.Error || std.Io.Writer.Error;

/// The cache folder inside a config project.
pub const cache_folder = ".zig-cache/kosm/images";

/// ImageMagick shrinks an image to fit this, keeping its aspect, averaging the pixels it
/// merges (`-scale`): large enough to tell crisp edges and fine texture from soft ones.
const geometry = "1024x1024>";
/// The longest PPM a `geometry`-sized image gives, with room for its header.
const output_limit = 1024 * 1024 * 6 + 64;
/// The colors are taken from every few pixels of the decoded copy, so that at most this many
/// lie along its long side: plenty for its colors, and quick to analyse.
const palette_side = 256;
/// Part of every cache entry's name; changing what is cached changes it, so older entries are
/// never read.
const cache_version = "1024";

/// Loads the pixels of every `kosm.Image` (or non-null `?kosm.Image`) field of `params_value`.
pub fn fill(comptime Params: type, params_value: *Params, context: Context) Error!void {
    const fields = @typeInfo(Params).@"struct";
    inline for (fields.field_names, fields.field_types) |name, Field| {
        if (comptime !params.isImage(Field)) continue;
        if (Field == kosm.Image) {
            try load(context, name, &@field(params_value, name));
        } else if (@field(params_value, name)) |*image| {
            try load(context, name, image);
        }
    }
}

/// Loads `image`'s pixels and makes its path absolute, so the kosmos can hand it to any program.
/// A folder is first replaced by a random picture in it.
fn load(context: Context, comptime name: []const u8, image: *kosm.Image) Error!void {
    var full_path = try resolve(context, name, image.path);
    var stat = std.Io.Dir.cwd().statFile(context.io, full_path, .{}) catch |err|
        return fail(context, name, image.path, "cannot read the image: {s}", .{@errorName(err)});
    if (stat.kind == .directory) {
        const picked = try pickPicture(context, name, image.path, full_path);
        image.path = try std.Io.Dir.path.join(context.arena, &.{ image.path, picked });
        full_path = try std.Io.Dir.path.join(context.arena, &.{ full_path, picked });
        stat = std.Io.Dir.cwd().statFile(context.io, full_path, .{}) catch |err|
            return fail(context, name, image.path, "cannot read the image: {s}", .{@errorName(err)});
    }
    if (stat.kind != .file) return fail(context, name, image.path, "the image is neither a file nor a folder", .{});
    const decoded = try loadFile(context, name, image.path, full_path, stat);
    image.pixels = decoded.pixels;
    image.width = decoded.width;
    image.lightness = decoded.lightness;
    image.lightness_width = decoded.lightness_width;
    image.path = full_path;
}

/// File extensions of the pictures a folder is picked from, lowercase.
const picture_extensions = [_][]const u8{ ".jxl", ".png", ".jpg", ".jpeg", ".webp", ".avif", ".gif", ".bmp", ".tif", ".tiff", ".ppm" };

/// A random picture in the folder `full_path` or its subfolders, as a path inside it.
fn pickPicture(context: Context, comptime name: []const u8, path: []const u8, full_path: []const u8) Error![]const u8 {
    var folder = std.Io.Dir.cwd().openDir(context.io, full_path, .{ .iterate = true }) catch |err|
        return fail(context, name, path, "cannot open the folder: {s}", .{@errorName(err)});
    defer folder.close(context.io);
    var walker = try folder.walk(context.arena);
    defer walker.deinit();
    var pictures: std.ArrayList([]const u8) = .empty;
    while (walker.next(context.io) catch |err| return fail(context, name, path, "cannot read the folder: {s}", .{@errorName(err)})) |entry| {
        if (entry.kind != .file or !isPicture(entry.basename)) continue;
        try pictures.append(context.arena, try context.arena.dupe(u8, entry.path));
    }
    if (pictures.items.len == 0) return fail(context, name, path, "the folder holds no pictures ({s})", .{comptime extensionList()});
    var bytes: [8]u8 = undefined;
    context.io.random(&bytes);
    return pictures.items[std.mem.readInt(u64, &bytes, .little) % pictures.items.len];
}

fn isPicture(basename: []const u8) bool {
    const extension = std.Io.Dir.path.extension(basename);
    for (picture_extensions) |picture_extension| {
        if (std.ascii.eqlIgnoreCase(extension, picture_extension)) return true;
    }
    return false;
}

fn extensionList() []const u8 {
    var list: []const u8 = "";
    for (picture_extensions, 0..) |extension, index| list = list ++ (if (index == 0) "" else ", ") ++ extension;
    return list;
}

fn loadFile(context: Context, comptime name: []const u8, path: []const u8, full_path: []const u8, stat: std.Io.File.Stat) Error!Decoded {
    const cache_path = if (context.cache) |folder| try cachePath(context.arena, folder, full_path, stat) else null;
    if (cache_path) |cached| {
        // The cache is only a shortcut: a missing or unreadable entry is decoded again.
        if (readCache(context, cached)) |bytes| {
            if (parsePpm(context.arena, bytes)) |decoded| return decoded else |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {},
            }
        }
    }

    const bytes = try decode(context, name, path, full_path);
    const decoded = parsePpm(context.arena, bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return fail(context, name, path, "ImageMagick's output is not a PPM image: {s}", .{@errorName(err)}),
    };
    if (cache_path) |cached| writeCache(context, cached, bytes) catch |err| {
        try kosm.Diagnostics.writeReport(context.stderr, "warning", context.diagnostics.kosmos, "", path, try context.arena.print("cannot cache the decoded image in {s}: {s}", .{ cached, @errorName(err) }));
    };
    return decoded;
}

fn resolve(context: Context, comptime name: []const u8, path: []const u8) Error![]const u8 {
    return context.places.resolve(context.arena, path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnknownPlace => return fail(context, name, path, "{s}", .{try context.places.unknownPlaceMessage(context.arena, path)}),
    };
}

/// The cache entry of the image at `full_path` as `stat` describes it; a changed size or
/// modification time gives a new entry.
pub fn cachePath(arena: std.mem.Allocator, folder: []const u8, full_path: []const u8, stat: std.Io.File.Stat) std.mem.Allocator.Error![]const u8 {
    const entry = try arena.print("{x:0>16}-{d}-{d}-{s}.ppm", .{ std.hash.Wyhash.hash(0, full_path), stat.size, stat.mtime.nanoseconds, cache_version });
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
        .argv = &.{ "magick", input, "-scale", geometry, "-colorspace", "sRGB", "-depth", "8", "ppm:-" },
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

/// What kosm keeps of a decoded image: the fields of `kosm.Image` it fills.
pub const Decoded = struct {
    /// Every few pixels' colors, at most `palette_side` along the long side.
    pixels: []const kosm.Color,
    width: usize,
    /// Every pixel's OKLCH lightness.
    lightness: []const f32,
    lightness_width: usize,
};

/// The pixels of a binary PPM (`P6`), with a maximum value up to 65535.
pub fn parsePpm(allocator: std.mem.Allocator, bytes: []const u8) PpmError!Decoded {
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
    const reader: PpmPixels = .{ .data = bytes[position..][0..data_length], .channel_size = channel_size, .scale = @floatFromInt(maximum) };

    const lightness = try allocator.alloc(f32, pixel_count);
    for (lightness, 0..) |*value, index| value.* = @floatCast(reader.color(index).lightness);

    const step = std.math.divCeil(usize, @max(width, height), palette_side) catch unreachable;
    const sampled_width = std.math.divCeil(usize, width, step) catch unreachable;
    const sampled_height = std.math.divCeil(usize, height, step) catch unreachable;
    const pixels = try allocator.alloc(kosm.Color, sampled_width * sampled_height);
    for (0..sampled_height) |row| for (0..sampled_width) |column| {
        pixels[row * sampled_width + column] = reader.color(row * step * width + column * step);
    };
    return .{ .pixels = pixels, .width = sampled_width, .lightness = lightness, .lightness_width = width };
}

/// The pixel data of a PPM, read one pixel at a time.
const PpmPixels = struct {
    data: []const u8,
    channel_size: usize,
    scale: f64,

    fn color(pixels: PpmPixels, index: usize) kosm.Color {
        var channels: [3]f64 = undefined;
        for (&channels, 0..) |*channel, offset| {
            const at = (index * 3 + offset) * pixels.channel_size;
            const value: u16 = if (pixels.channel_size == 2) std.mem.readInt(u16, pixels.data[at..][0..2], .big) else pixels.data[at];
            channel.* = @as(f64, @floatFromInt(value)) / pixels.scale;
        }
        return .fromRgb(.{ .red = channels[0], .green = channels[1], .blue = channels[2] });
    }
};

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
    try testing.expectEqual(2, eight.pixels.len);
    try testing.expectEqualStrings("#ff0000", eight.pixels[0].hex().slice());
    try testing.expectEqualStrings("#0000ff", eight.pixels[1].hex().slice());
    const sixteen = try parsePpm(arena, "P6 1 1 65535 \xff\xff\x80\x00\x00\x00");
    try testing.expectEqualStrings("#ff8000", sixteen.pixels[0].hex().slice());
}

test "a large PPM keeps every pixel's lightness and every few pixels' colors" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const width = 2 * palette_side + 1;
    const header = std.fmt.comptimePrint("P6 {d} 2 255\n", .{width});
    const bytes = try arena.alloc(u8, header.len + width * 2 * 3);
    @memcpy(bytes[0..header.len], header);
    for (bytes[header.len..], 0..) |*byte, index| byte.* = if (index / 3 % width % 2 == 0) 255 else 0;
    const decoded = try parsePpm(arena, bytes);
    try testing.expectEqual(width, decoded.lightness_width);
    try testing.expectEqual(width * 2, decoded.lightness.len);
    try testing.expectApproxEqAbs(0, decoded.lightness[3], 1e-6);
    try testing.expectApproxEqAbs(1, decoded.lightness[4], 1e-6);
    // Every third pixel of one row: 513 wide is 171 sampled, at most `palette_side`.
    try testing.expectEqual(171, decoded.width);
    try testing.expectEqual(171, decoded.pixels.len);
    try testing.expectEqualStrings("#ffffff", decoded.pixels[0].hex().slice());
    try testing.expectEqualStrings("#000000", decoded.pixels[1].hex().slice());
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
            .places = .{ .home = fixture.root, .config = fixture.root, .kosmos = fixture.root },
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

test "a missing image, an unknown place and an image ImageMagick cannot read name the parameter and the file" {
    var fixture: Fixture = try .init();
    defer fixture.deinit();
    const Params = struct { wallpaper: kosm.Image };

    var missing: Params = .{ .wallpaper = .{ .path = "~/missing.jxl" } };
    try testing.expectError(error.Reported, fill(Params, &missing, fixture.context(null)));
    try testing.expectEqualStrings("~/missing.jxl", fixture.diagnostics.file);
    try testing.expectEqualStrings("Params.wallpaper: cannot read the image: FileNotFound", fixture.diagnostics.message());

    var unknown: Params = .{ .wallpaper = .{ .path = "~~kosmso/missing.jxl" } };
    try testing.expectError(error.Reported, fill(Params, &unknown, fixture.context(null)));
    try testing.expect(std.mem.startsWith(u8, fixture.diagnostics.message(), "Params.wallpaper: ~~kosmso/ names no folder kosm knows: use ~/ (home)"));

    if (!hasMagick()) return error.SkipZigTest;
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "broken.png", .data = "not a png" });
    var broken: Params = .{ .wallpaper = .{ .path = "~/broken.png" } };
    try testing.expectError(error.Reported, fill(Params, &broken, fixture.context(null)));
    try testing.expect(std.mem.startsWith(u8, fixture.diagnostics.message(), "Params.wallpaper: ImageMagick cannot decode the image: "));
}

test "a folder gives a random picture in it or its subfolders, whose path the image then holds" {
    if (!hasMagick()) return error.SkipZigTest;
    var fixture: Fixture = try .init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "pictures/nested");
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "pictures/nested/red.ppm", .data = "P6 1 1 255 \xff\x00\x00" });
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "pictures/notes.txt", .data = "not a picture" });
    const Params = struct { wallpaper: kosm.Image = .{ .path = "~/pictures" } };
    var params_value: Params = .{};
    try fill(Params, &params_value, fixture.context(null));
    try testing.expectEqualStrings(try std.Io.Dir.path.join(fixture.arena_state.allocator(), &.{ fixture.root, "pictures/nested/red.ppm" }), params_value.wallpaper.path);
    try testing.expectEqualStrings("#ff0000", params_value.wallpaper.pixels[0].hex().slice());
}

test "a folder without pictures is an error naming the extensions" {
    var fixture: Fixture = try .init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "empty");
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "empty/notes.txt", .data = "not a picture" });
    const Params = struct { wallpaper: kosm.Image = .{ .path = "~/empty" } };
    var params_value: Params = .{};
    try testing.expectError(error.Reported, fill(Params, &params_value, fixture.context(null)));
    try testing.expect(std.mem.startsWith(u8, fixture.diagnostics.message(), "Params.wallpaper: the folder holds no pictures (.jxl, .png"));
}
