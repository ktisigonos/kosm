//! The code colors a kosmos sets itself; every one left null takes its default from the
//! palette or the foreground role.

const Color = @import("../../Color.zig");

/// Comments and documentation. null: the foreground role, `emphasis.muted`.
comment: ?Color = null,
/// Keywords (`if`, `return`, `fn`). null: purple.
keyword: ?Color = null,
/// Strings and characters. null: green.
string: ?Color = null,
/// Numbers. null: orange.
number: ?Color = null,
/// Constants and booleans. null: orange.
constant: ?Color = null,
/// Functions and methods, called or defined. null: blue.
function: ?Color = null,
/// Types, classes and modules. null: yellow.
type: ?Color = null,
/// Variables and parameters. null: the foreground role.
variable: ?Color = null,
/// Fields and properties. null: the foreground role.
property: ?Color = null,
/// Operators (`+`, `==`, `=>`). null: the foreground role.
operator: ?Color = null,
/// Brackets, delimiters and separators. null: the foreground role.
punctuation: ?Color = null,
/// Markup tags (HTML, XML, JSX). null: red.
tag: ?Color = null,
