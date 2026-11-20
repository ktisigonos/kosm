//! What `kosm new --language <frontend>` writes for each kind: the whole text of one script,
//! with `name_placeholder` standing wherever the new kosmos', app's, adapter's or frontend's
//! name goes. Null for a kind the frontend cannot write.

/// Stands for the name given to `kosm new`, which replaces every occurrence of it.
pub const name_placeholder = "scaffold_name";

/// A script kosmos, written as `kosmoi/<name><extension>`.
kosmos: ?[]const u8 = null,
/// An app written through the frontend, written as `apps/<name><extension>`.
app: ?[]const u8 = null,
/// An adapter written through the frontend, written as `adapters/<name><extension>`.
adapter: ?[]const u8 = null,
/// A frontend written through the frontend, written as `frontends/<name><extension>`.
frontend: ?[]const u8 = null,
