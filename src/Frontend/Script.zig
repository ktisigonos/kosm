//! What a script kosmos says, as a frontend reads it: the kosmos it builds on, or none, and the
//! values it sets. Kosm puts the values into the typed tree, all or nothing.

const Loose = @import("../Loose.zig");

/// The kosmos this one builds on, as `kosm apply` spells it: a Zig kosmos ("personal",
/// "frost.iced") or another script kosmos ("minimal"). Null builds the kosmos from `theme`
/// alone, with the apps `overrides` names.
base: ?[]const u8 = null,
/// A table for the base's `Params`, set before the command line's parameters. Only with a
/// base, and only for one that takes parameters.
params: ?Loose = null,
/// A table for the theme's input (`palette`, `mode`, `roles`, ...) the apps are built from.
/// Only without a base, where it is required as soon as an app is named.
theme: ?Loose = null,
/// A table of the tree's values, set on top of the base. Without a base, naming an app (even
/// with an empty table) chooses it; apps it does not name are not applied.
overrides: ?Loose = null,
