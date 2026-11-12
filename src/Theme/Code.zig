//! Colors for highlighting code, in tree-sitter's capture names, for editors and anything
//! else showing code.

const Code = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const Palette = @import("../Palette.zig");
const Roles = @import("Roles.zig");
const Variations = @import("../Variations.zig");

/// Comments and documentation. Default: the foreground role, `emphasis.muted`.
comment: Color,
/// Keywords (`if`, `return`, `fn`). Default: purple.
keyword: Color,
/// Strings and characters. Default: green.
string: Color,
/// Numbers. Default: orange.
number: Color,
/// Constants and booleans. Default: orange.
constant: Color,
/// Functions and methods, called or defined. Default: blue.
function: Color,
/// Types, classes and modules. Default: yellow.
type: Color,
/// Variables and parameters. Default: the foreground role.
variable: Color,
/// Fields and properties. Default: the foreground role.
property: Color,
/// Operators (`+`, `==`, `=>`). Default: the foreground role.
operator: Color,
/// Brackets, delimiters and separators. Default: the foreground role.
punctuation: Color,
/// Markup tags (HTML, XML, JSX). Default: red.
tag: Color,

/// The code colors a kosmos sets itself, each optional.
pub const Overrides = @import("Code/Overrides.zig");

/// Every code color `overrides` leaves null from `palette`, the `roles`' foreground and
/// `variations`.
pub fn from(palette: Palette.Resolved, roles: Roles, variations: Variations, overrides: Overrides) Code {
    return .{
        .comment = overrides.comment orelse variations.emphasis.muted.apply(roles.foreground),
        .keyword = overrides.keyword orelse palette.purple,
        .string = overrides.string orelse palette.green,
        .number = overrides.number orelse palette.orange,
        .constant = overrides.constant orelse palette.orange,
        .function = overrides.function orelse palette.blue,
        .type = overrides.type orelse palette.yellow,
        .variable = overrides.variable orelse roles.foreground,
        .property = overrides.property orelse roles.foreground,
        .operator = overrides.operator orelse roles.foreground,
        .punctuation = overrides.punctuation orelse roles.foreground,
        .tag = overrides.tag orelse palette.red,
    };
}

test "every code color can be overridden" {
    try std.testing.expectEqualDeep(
        std.meta.fieldNames(Code),
        std.meta.fieldNames(Overrides),
    );
}
