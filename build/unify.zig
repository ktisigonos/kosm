//! One copy of each package per build. Every package pins its own copies of kosm and of the
//! packages it uses, and two copies of one package are two sets of different types (`Theme` and
//! `Theme`), or one grammar's C symbols twice. The build root (a config project, or a package
//! built on its own) decides: the copy it lists itself is the one everything uses.

const std = @import("std");

/// Packages that pin different copies of a package the build root does not list. Only the
/// root can say which copy they all use, by listing it.
pub const Conflict = struct {
    /// The two packages importing it, by the names they are imported under.
    first_importer: []const u8,
    second_importer: []const u8,
    package: []const u8,
};

/// Re-points every import of a package in `listed` (the build root's own dependencies, each
/// under its dependency name) to the root's copy, through the whole module graph below them.
/// Returns the first conflict among the packages the root does not list, or null.
pub fn unify(b: *std.Build, listed: []const std.Build.Module.Import) ?Conflict {
    var visited: std.AutoArrayHashMapUnmanaged(*std.Build.Module, void) = .empty;
    var pinned: std.array_hash_map.String(Pin) = .empty;
    var pending: std.ArrayList(std.Build.Module.Import) = .empty;
    pending.appendSlice(b.allocator, listed) catch @panic("OOM");
    while (pending.pop()) |importer| {
        const seen = visited.getOrPut(b.allocator, importer.module) catch @panic("OOM");
        if (seen.found_existing) continue;
        // By index: `addImport` may grow the table even when it only replaces a value, which
        // frees the slices `keys()` and `values()` return.
        for (0..importer.module.import_table.count()) |index| {
            const import_name = importer.module.import_table.keys()[index];
            const imported = importer.module.import_table.values()[index];
            if (listedModule(listed, import_name)) |own| {
                importer.module.addImport(import_name, own);
                continue;
            }
            pending.append(b.allocator, .{ .name = import_name, .module = imported }) catch @panic("OOM");
            if (!isPackageModule(imported, import_name)) continue;
            const first = pinned.getOrPut(b.allocator, import_name) catch @panic("OOM");
            if (!first.found_existing) {
                first.value_ptr.* = .{ .module = imported, .importer = importer.name };
            } else if (first.value_ptr.module != imported) {
                return .{ .first_importer = first.value_ptr.importer, .second_importer = importer.name, .package = import_name };
            }
        }
    }
    return null;
}

/// The copy of an unlisted package met first, and the package importing it.
const Pin = struct { module: *std.Build.Module, importer: []const u8 };

/// The build root's own copy of package `name`, or null when it does not list it.
fn listedModule(listed: []const std.Build.Module.Import, name: []const u8) ?*std.Build.Module {
    for (listed) |own| {
        if (std.mem.eql(u8, own.name, name)) return own.module;
    }
    return null;
}

/// Whether `module` is what a package exposes as `name`, rather than a private module of one:
/// a package's module is named like the package in its own build.
fn isPackageModule(module: *std.Build.Module, name: []const u8) bool {
    const exposed = module.owner.modules.get(name) orelse return false;
    return exposed == module;
}
