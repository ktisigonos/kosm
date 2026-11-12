//! Colors for highlighting code, in tree-sitter's capture names, for editors and anything
//! else showing code.

const Code = @This();

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

/// Every code color's default from `palette`, the `roles`' foreground and `variations`.
pub fn from(palette: Palette.Resolved, roles: Roles, variations: Variations) Code {
    return .{
        .comment = variations.emphasis.muted.apply(roles.foreground),
        .keyword = palette.purple,
        .string = palette.green,
        .number = palette.orange,
        .constant = palette.orange,
        .function = palette.blue,
        .type = palette.yellow,
        .variable = roles.foreground,
        .property = roles.foreground,
        .operator = roles.foreground,
        .punctuation = roles.foreground,
        .tag = palette.red,
    };
}
