//! Kosmos names as `kosm apply` spells them (`personal`, `personal.nord`, `frost.cold.deep`):
//! whether a name is one of a config's, and the message naming the closest ones when it is not.
//! The command line and the runner share it, so a misspelled kosmos reads the same everywhere.

const std = @import("std");
const suggestion = @import("kosm_suggestion");

/// Whether `name` picks any of `known`: is one of them, or a file or group holding one
/// (`frost` picks `frost.iced`).
pub fn picksAny(name: []const u8, known: []const []const u8) bool {
    for (known) |kosmos| {
        if (picks(name, kosmos)) return true;
    }
    return false;
}

/// Whether `name` is one of `known`.
pub fn isKnown(name: []const u8, known: []const []const u8) bool {
    for (known) |kosmos| {
        if (std.mem.eql(u8, name, kosmos)) return true;
    }
    return false;
}

/// Whether `name` is `kosmos` or a file or group holding it.
pub fn picks(name: []const u8, kosmos: []const u8) bool {
    if (!std.mem.startsWith(u8, kosmos, name)) return false;
    return kosmos.len == name.len or kosmos[name.len] == '.';
}

/// Writes why `name` is none of `known`, without a leading `error: `: the closest names
/// (`there is no kosmos 'personal.frost'; did you mean 'personal.frozen'?`), or when none is
/// close the names as deep as `name` that start with it (`kryst` for `krystallos`), or else
/// the kosmoi of the longest file or group `name` starts with, or else every kosmos.
pub fn writeUnknown(writer: *std.Io.Writer, name: []const u8, known: []const []const u8) std.Io.Writer.Error!void {
    try writer.print("there is no kosmos '{s}'; ", .{name});
    const closest = suggestion.closestDistance(name, known);
    if (closest <= allowedEdits(name)) return suggestion.writeChoices(writer, known, Suggestion{ .name = name, .kind = .{ .edits = closest } });
    const completion: Suggestion = .{ .name = name, .kind = .completion };
    if (countSuggestions(known, completion) != 0) return suggestion.writeChoices(writer, known, completion);
    const holder = longestHolder(name, known);
    if (holder.len != 0) {
        try writer.print("kosmoi of {s}: ", .{holder});
        return writeList(writer, holder, known);
    }
    if (known.len == 0) return writer.writeAll("the config has no kosmoi");
    try writer.writeAll("kosmoi: ");
    try writeList(writer, "", known);
}

/// The message `writeUnknown` writes, in `allocator`'s memory.
pub fn unknownMessage(allocator: std.mem.Allocator, name: []const u8, known: []const []const u8) std.mem.Allocator.Error![]u8 {
    var message: std.Io.Writer.Allocating = .init(allocator);
    defer message.deinit();
    writeUnknown(&message.writer, name, known) catch return error.OutOfMemory;
    return message.toOwnedSlice();
}

/// The edits allowed for `name` count only its last segment, so a long file name allows no
/// more than a short one.
fn allowedEdits(name: []const u8) usize {
    const segment_start = if (std.mem.findScalarLast(u8, name, '.')) |dot| dot + 1 else 0;
    return suggestion.allowedEdits(name.len - segment_start);
}

/// Whether `kosmos` is as deep as `name` (as many dots) and starts with it.
fn completes(name: []const u8, kosmos: []const u8) bool {
    return std.mem.startsWith(u8, kosmos, name) and std.mem.countScalar(u8, kosmos, '.') == std.mem.countScalar(u8, name, '.');
}

/// Which names of a config are suggested for a misspelled `name`.
const Suggestion = struct {
    name: []const u8,
    kind: union(enum) {
        /// Those this many edits away.
        edits: usize,
        /// Those that `completes` it.
        completion,
    },

    pub fn picks(picked: Suggestion, kosmos: []const u8) bool {
        return switch (picked.kind) {
            .edits => |edits| suggestion.closeness(picked.name, kosmos) == edits,
            .completion => completes(picked.name, kosmos),
        };
    }
};

fn countSuggestions(known: []const []const u8, picked: Suggestion) usize {
    var total: usize = 0;
    for (known) |kosmos| {
        if (picked.picks(kosmos)) total += 1;
    }
    return total;
}

/// The longest file or group (`personal`, `personal.catppuccin`) `name` starts with that holds
/// any of `known`; empty when even its first segment holds none.
fn longestHolder(name: []const u8, known: []const []const u8) []const u8 {
    var end = name.len;
    while (std.mem.findScalarLast(u8, name[0..end], '.')) |dot| {
        end = dot;
        if (picksAny(name[0..end], known)) return name[0..end];
    }
    return "";
}

/// Every name of `known` that `holder` picks (every name when it is empty), comma-separated.
fn writeList(writer: *std.Io.Writer, holder: []const u8, known: []const []const u8) std.Io.Writer.Error!void {
    var written = false;
    for (known) |kosmos| {
        if (holder.len != 0 and !picks(holder, kosmos)) continue;
        if (written) try writer.writeAll(", ");
        try writer.writeAll(kosmos);
        written = true;
    }
}

const testing = std.testing;

const test_known: []const []const u8 = &.{ "kyanos", "personal", "personal.frozen", "personal.nord", "personal.catppuccin.latte", "personal.catppuccin.mocha" };

fn testUnknown(name: []const u8) ![]u8 {
    return unknownMessage(testing.allocator, name, test_known);
}

test "a misspelled variant suggests the closest name" {
    const message = try testUnknown("personal.frost");
    defer testing.allocator.free(message);
    try testing.expectEqualStrings("there is no kosmos 'personal.frost'; did you mean 'personal.frozen'?", message);
}

test "names equally close are all suggested" {
    const message = try testUnknown("personal.catppuccin.mochi");
    defer testing.allocator.free(message);
    try testing.expectEqualStrings("there is no kosmos 'personal.catppuccin.mochi'; did you mean 'personal.catppuccin.mocha'?", message);
    const known: []const []const u8 = &.{ "frost.a", "frost.b", "frost.c" };
    const three = try unknownMessage(testing.allocator, "frost.d", known);
    defer testing.allocator.free(three);
    try testing.expectEqualStrings("there is no kosmos 'frost.d'; did you mean 'frost.a', 'frost.b' or 'frost.c'?", three);
}

test "with nothing close, the kosmoi of the longest known file or group are listed" {
    const group = try testUnknown("personal.catppuccin.frappe");
    defer testing.allocator.free(group);
    try testing.expectEqualStrings("there is no kosmos 'personal.catppuccin.frappe'; kosmoi of personal.catppuccin: personal.catppuccin.latte, personal.catppuccin.mocha", group);
    const file = try testUnknown("personal.everforest");
    defer testing.allocator.free(file);
    try testing.expectEqualStrings("there is no kosmos 'personal.everforest'; kosmoi of personal: personal, personal.frozen, personal.nord, personal.catppuccin.latte, personal.catppuccin.mocha", file);
}

test "an unknown file lists every kosmos, and an empty config says so" {
    const message = try testUnknown("everforest");
    defer testing.allocator.free(message);
    try testing.expectEqualStrings("there is no kosmos 'everforest'; kosmoi: kyanos, personal, personal.frozen, personal.nord, personal.catppuccin.latte, personal.catppuccin.mocha", message);
    const empty = try unknownMessage(testing.allocator, "frost", &.{});
    defer testing.allocator.free(empty);
    try testing.expectEqualStrings("there is no kosmos 'frost'; the config has no kosmoi", empty);
}

test "the start of a name suggests the names as deep as it that it starts" {
    const message = try testUnknown("pers");
    defer testing.allocator.free(message);
    try testing.expectEqualStrings("there is no kosmos 'pers'; did you mean 'personal'?", message);
    const variant = try testUnknown("personal.catppuccin.l");
    defer testing.allocator.free(variant);
    try testing.expectEqualStrings("there is no kosmos 'personal.catppuccin.l'; did you mean 'personal.catppuccin.latte'?", variant);
}

test "a short name gets no wild guesses" {
    const message = try unknownMessage(testing.allocator, "ab", &.{ "xy", "frost" });
    defer testing.allocator.free(message);
    try testing.expectEqualStrings("there is no kosmos 'ab'; kosmoi: xy, frost", message);
}

test "a file or group picks the kosmoi it holds, not a longer name sharing its start" {
    try testing.expect(picksAny("personal", test_known));
    try testing.expect(picksAny("personal.catppuccin", test_known));
    try testing.expect(!picksAny("person", test_known));
    try testing.expect(!isKnown("personal.catppuccin", test_known));
    try testing.expect(isKnown("personal.nord", test_known));
}
