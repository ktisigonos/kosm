//! A keyboard as XKB describes one: the layouts to switch between, each with an optional
//! variant, and the model, options and rules they share. A kosmos lists the layouts once and
//! each app writes them the way its program spells them; most take XKB's comma separated
//! lists (`us,rs` with `,latin`), which the functions here build.

const Keyboard = @This();

const std = @import("std");

/// The layouts in switching order; the first is the one active at startup. Default: none.
layouts: []const Layout = &.{},
/// The keyboard model, e.g. "pc105". null: the program's default.
model: ?[]const u8 = null,
/// XKB options, e.g. "grp:alt_shift_toggle" or "caps:escape". Default: none.
options: []const []const u8 = &.{},
/// The XKB rules file, e.g. "evdev". null: the program's default.
rules: ?[]const u8 = null,

/// One layout: its XKB name ("us", "rs") and the variant of it to use.
pub const Layout = struct {
    layout: []const u8,
    /// E.g. "latin" or "dvorak". Empty: the layout's default variant.
    variant: []const u8 = "",
};

/// A name XKB can't take, for the error an app gives.
pub const Problem = struct {
    /// What the name is: "layout", "variant", "model", "option" or "rules".
    kind: []const u8,
    name: []const u8,
    /// Why XKB can't take it, worded to follow the name: "holds a comma, ...".
    reason: []const u8,
};

const comma_reason = "holds a comma, which separates entries; give each its own entry";
const space_reason = "holds a space, which no XKB name has";
const empty_reason = "is empty";

/// The first name XKB can't take, or null when every name is fine. An app calls this before
/// writing and fails naming what it returns, so the lists below never hold a broken name.
pub fn problem(keyboard: Keyboard) ?Problem {
    for (keyboard.layouts) |entry| {
        if (entry.layout.len == 0) return .{ .kind = "layout", .name = entry.layout, .reason = empty_reason };
        if (nameProblem(entry.layout)) |reason| return .{ .kind = "layout", .name = entry.layout, .reason = reason };
        if (nameProblem(entry.variant)) |reason| return .{ .kind = "variant", .name = entry.variant, .reason = reason };
    }
    for (keyboard.options) |option| {
        if (option.len == 0) return .{ .kind = "option", .name = option, .reason = empty_reason };
        if (nameProblem(option)) |reason| return .{ .kind = "option", .name = option, .reason = reason };
    }
    if (keyboard.model) |model| {
        if (nameProblem(model)) |reason| return .{ .kind = "model", .name = model, .reason = reason };
    }
    if (keyboard.rules) |rules| {
        if (nameProblem(rules)) |reason| return .{ .kind = "rules", .name = rules, .reason = reason };
    }
    return null;
}

fn nameProblem(name: []const u8) ?[]const u8 {
    for (name) |byte| {
        if (byte == ',') return comma_reason;
        if (std.ascii.isWhitespace(byte)) return space_reason;
    }
    return null;
}

/// Every layout's name joined with commas, as XKB takes them: "us,rs,rs". Null without
/// layouts. The caller owns the text.
pub fn layoutList(keyboard: Keyboard, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8 {
    if (keyboard.layouts.len == 0) return null;
    var list: std.ArrayList(u8) = .empty;
    for (keyboard.layouts, 0..) |entry, index| {
        if (index > 0) try list.append(allocator, ',');
        try list.appendSlice(allocator, entry.layout);
    }
    return try list.toOwnedSlice(allocator);
}

/// Every layout's variant joined with commas, an empty one kept so each variant stays at its
/// layout's position: ",latin,". Null when no layout has a variant. The caller owns the text.
pub fn variantList(keyboard: Keyboard, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8 {
    const has_variant = for (keyboard.layouts) |entry| {
        if (entry.variant.len != 0) break true;
    } else false;
    if (!has_variant) return null;
    var list: std.ArrayList(u8) = .empty;
    for (keyboard.layouts, 0..) |entry, index| {
        if (index > 0) try list.append(allocator, ',');
        try list.appendSlice(allocator, entry.variant);
    }
    return try list.toOwnedSlice(allocator);
}

/// The options joined with commas: "grp:alt_shift_toggle,caps:escape". Null without options.
/// The caller owns the text.
pub fn optionList(keyboard: Keyboard, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8 {
    if (keyboard.options.len == 0) return null;
    return try std.mem.join(allocator, ",", keyboard.options);
}

const testing = std.testing;

test "layouts and variants join by position, an empty variant keeping its place" {
    const keyboard: Keyboard = .{ .layouts = &.{
        .{ .layout = "us" },
        .{ .layout = "rs", .variant = "latin" },
        .{ .layout = "rs" },
    } };
    const layouts = (try keyboard.layoutList(testing.allocator)).?;
    defer testing.allocator.free(layouts);
    const variants = (try keyboard.variantList(testing.allocator)).?;
    defer testing.allocator.free(variants);
    try testing.expectEqualStrings("us,rs,rs", layouts);
    try testing.expectEqualStrings(",latin,", variants);
}

test "nothing set joins to null, and layouts without any variant have no variant list" {
    const empty: Keyboard = .{};
    try testing.expectEqual(null, try empty.layoutList(testing.allocator));
    try testing.expectEqual(null, try empty.variantList(testing.allocator));
    try testing.expectEqual(null, try empty.optionList(testing.allocator));

    const plain: Keyboard = .{ .layouts = &.{ .{ .layout = "us" }, .{ .layout = "ru" } }, .options = &.{ "grp:alt_shift_toggle", "caps:escape" } };
    try testing.expectEqual(null, try plain.variantList(testing.allocator));
    const options = (try plain.optionList(testing.allocator)).?;
    defer testing.allocator.free(options);
    try testing.expectEqualStrings("grp:alt_shift_toggle,caps:escape", options);
}

test "a name with a comma or a space, or an empty layout or option, is a problem naming it" {
    const joined: Keyboard = .{ .layouts = &.{ .{ .layout = "us" }, .{ .layout = "rs,ru" } } };
    try testing.expectEqualStrings("layout", joined.problem().?.kind);
    try testing.expectEqualStrings("rs,ru", joined.problem().?.name);
    try testing.expectEqualStrings(comma_reason, joined.problem().?.reason);

    const variant: Keyboard = .{ .layouts = &.{.{ .layout = "rs", .variant = "latin unicode" }} };
    try testing.expectEqualStrings("variant", variant.problem().?.kind);
    try testing.expectEqualStrings(space_reason, variant.problem().?.reason);

    const unnamed: Keyboard = .{ .layouts = &.{.{ .layout = "" }} };
    try testing.expectEqualStrings(empty_reason, unnamed.problem().?.reason);
    const option: Keyboard = .{ .options = &.{ "caps:escape", "" } };
    try testing.expectEqualStrings("option", option.problem().?.kind);
    const model: Keyboard = .{ .model = "pc105,pc104" };
    try testing.expectEqualStrings("model", model.problem().?.kind);

    const fine: Keyboard = .{ .layouts = &.{.{ .layout = "rs", .variant = "latin" }}, .model = "pc105", .options = &.{"caps:escape"}, .rules = "evdev" };
    try testing.expectEqual(null, fine.problem());
}
