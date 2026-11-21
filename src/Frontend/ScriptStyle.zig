//! A palette style written through a frontend: where its script is, and the call the Zig module
//! kosm generates for it makes to run the script's `apply(self, hue, background)` through
//! `Host.current()`. Its `Style` type keeps the shape `kosm.Image.Style.Function.of` takes, so
//! it is used like one written in Zig.

const ScriptStyle = @This();

const std = @import("std");
const Loose = @import("../Loose.zig");
const Color = @import("../Color.zig");
const failure = @import("../failure.zig");
const color_call = @import("color_call.zig");
const Host = @import("Host.zig");
const Call = @import("Call.zig");
const Handle = @import("Handle.zig");
const ScriptFile = @import("ScriptFile.zig");

/// The frontend reading the script, by `Frontend.name`: "lua".
frontend: []const u8,
/// The script, relative to the config: "colors/pastel.lua".
path: []const u8,

/// The script, as the host runs it.
pub fn file(style: ScriptStyle) ScriptFile {
    return .{ .frontend = style.frontend, .path = style.path };
}

/// The final color the script's `apply(self, hue, background)` gives `hue`. It cannot fail: a
/// failure is recorded like `kosm.fail`'s message, which kosm reports before anything is
/// written, and `hue` is given unchanged.
pub fn apply(style: ScriptStyle, comptime Style: type, self: Style, hue: Color, background: Color) Color {
    return color_call.apply(Style, style.file(), "a palette style", self, &.{ hue, background });
}

const testing = std.testing;

/// A host whose `apply` returns the background for `colors/flat.lua` and fails otherwise.
const TestHost = struct {
    fn run(state: *anyopaque, call: *Call, script: ScriptFile, function: []const u8, arguments: []const Loose) Call.Error!Loose {
        _ = state;
        std.debug.assert(std.mem.eql(u8, function, "apply") and arguments.len == 3);
        if (std.mem.eql(u8, script.path, "colors/flat.lua")) return arguments[2];
        return call.fail("{s}:2: attempt to call a nil value", .{script.path});
    }

    fn handle(state: *anyopaque, id: *const anyopaque, pointer: *anyopaque) ?Handle {
        _ = state;
        inline for (.{ Color, TestStyle }) |T| {
            if (id == Handle.id(T)) return .{ .pointer = pointer, .type = tableOf(T) };
        }
        return null;
    }

    /// A table good only for telling the handle's type; nothing reads through it.
    fn tableOf(comptime T: type) *const Handle.Type {
        return &struct {
            const table: Handle.Type = .{ .id = Handle.id(T), .name = @typeName(T), .get = undefined, .set = undefined, .length = undefined };
        }.table;
    }
};

const TestStyle = struct {};

test "apply hands the script the hue and the background, and a failure keeps the hue" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host: Host = .{ .state = undefined, .arena = arena.allocator(), .run = TestHost.run, .handle = TestHost.handle };
    Host.install(&host);
    defer Host.install(null);
    defer failure.clear();
    failure.clear();
    const hue: Color = .{ .lightness = 0.7, .chroma = 0.1, .hue = 30 };
    const background: Color = .{ .lightness = 0.2, .chroma = 0, .hue = 0 };
    const flat: ScriptStyle = .{ .frontend = "test", .path = "colors/flat.lua" };
    try testing.expectEqual(background, flat.apply(TestStyle, .{}, hue, background));
    try testing.expectEqual(null, failure.message());
    const broken: ScriptStyle = .{ .frontend = "test", .path = "colors/broken.lua" };
    try testing.expectEqual(hue, broken.apply(TestStyle, .{}, hue, background));
    try testing.expectEqualStrings("colors/broken.lua:2: attempt to call a nil value", failure.message().?);
}
