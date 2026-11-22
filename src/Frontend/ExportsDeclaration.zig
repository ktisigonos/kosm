//! What a package's root script exports for building on, as a frontend reads it without
//! calling any of its functions: typed values (a look, a typed kosmos), and a base: the struct of
//! apps it declares with the `from` building it. Kosm writes the package's Zig module from it.

const ExportsDeclaration = @This();

const Declaration = @import("Declaration.zig");

/// The values and functions the script exports, in the order it writes them: `look`, `kosmos`,
/// and `from` when it gives a base.
values: []const Value,
/// The fields of the base the script declares, in the order it writes them; null when it
/// declares none.
base: ?[]const Declaration.Field = null,
/// The doc comment of the base, without the comment markers; null for none.
base_doc: ?[]const u8 = null,
/// The line the base is declared on, for messages; 0 when unknown.
base_line: usize = 0,
/// The other structs the script declares as it declares the base, in the order it writes them,
/// for the values it exports to take (a kosmos' `Params`).
structs: []const Struct = &.{},

/// A struct the script declares besides the base.
pub const Struct = struct {
    /// Its name in the module, as the script gives it: "Params".
    name: []const u8,
    /// Its fields, in the order the script writes them.
    fields: []const Declaration.Field,
    /// The doc comment written above it, without the comment markers; null for none.
    doc: ?[]const u8 = null,
    /// The line it is declared on, for messages; 0 when unknown.
    line: usize = 0,
};

/// The name the type of the base the script declares has in its Zig module, and in a
/// `Value.type` naming it.
pub const base_name = "Base";

/// One value the script exports: a function of the module calling the script's own, which gives
/// a value of `type` built from what the script returns.
pub const Value = struct {
    /// Its name in the module: "look".
    name: []const u8,
    /// The Zig type it gives by the name a script reaches it under ("kosm_base.Look"), or
    /// `base_name` for the base the script declares.
    type: []const u8,
    /// What the function takes, in order; empty for a value.
    parameters: []const Parameter = &.{},
    /// The doc comment written above it, without the comment markers; null for none.
    doc: ?[]const u8 = null,
    /// The line it is written on, for messages; 0 when unknown.
    line: usize = 0,
};

/// One parameter of an exported function.
pub const Parameter = struct {
    /// The name the script gives it: "look".
    name: []const u8,
    /// Its Zig type by the name a script reaches it under ("kosm_base.Look"), or the name of a
    /// struct the script declares ("Params").
    type: []const u8,
};
