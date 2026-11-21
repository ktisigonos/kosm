//! What `kosm new --language <frontend>` writes for each kind: the whole text of one script,
//! with `name_placeholder` standing wherever the new script's
//! name goes. Null for a kind the frontend cannot write.

/// Stands for the name given to `kosm new`, which replaces every occurrence of it.
pub const name_placeholder = "scaffold_name";

/// A script kosmos, written as `kosmoi/<name><extension>`.
kosmos: ?[]const u8 = null,
/// An app written through the frontend, written as `apps/<name><extension>`.
app: ?[]const u8 = null,
/// The root of a package of its own holding an app, written as `<name>/root<extension>`; null
/// writes `app` there instead.
package: ?[]const u8 = null,
/// An adapter written through the frontend, written as `adapters/<name><extension>`.
adapter: ?[]const u8 = null,
/// A frontend written through the frontend, written as `frontends/<name><extension>`.
frontend: ?[]const u8 = null,
/// A modifier written through the frontend, written as `colors/<name><extension>`.
modifier: ?[]const u8 = null,
/// A palette style written through the frontend, written as `colors/<name><extension>`.
style: ?[]const u8 = null,
/// A variation family written through the frontend, written as `colors/<name><extension>`.
family: ?[]const u8 = null,
