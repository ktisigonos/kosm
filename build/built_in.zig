//! The built-in packages in `packages/` (D67). While they live in kosm's repo, kosm's own build
//! exposes each one as a module of its own name, so a config or a directory package that
//! depends on `kosm` can import them without listing them (D98).

const std = @import("std");
const package_build = @import("package.zig");

/// A package in `packages/` and the grammars it compiles (D78), which kosm's build.zig.zon lists too.
pub const Package = struct {
    name: []const u8,
    grammars: []const []const u8 = &.{},
};

/// Sorted by name, the order `kosm list` shows them in.
pub const packages = [_]Package{
    .{ .name = "kosm_css" },
    .{ .name = "kosm_ghostty" },
    .{ .name = "kosm_hyprland" },
    .{ .name = "kosm_json", .grammars = &.{"tree_sitter_json"} },
    .{ .name = "kosm_kitty" },
    .{ .name = "kosm_lua", .grammars = &.{"tree_sitter_lua"} },
    .{ .name = "kosm_nvim" },
    .{ .name = "kosm_toml" },
    .{ .name = "kosm_userjs" },
    .{ .name = "kosm_zen" },
};

/// Adds every built-in package to kosm's build `b` as a public module importing `kosm_module`
/// and every other built-in by name, in the order of `packages`.
pub fn addModules(b: *std.Build, kosm_module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) [packages.len]*std.Build.Module {
    var modules: [packages.len]*std.Build.Module = undefined;
    for (packages, &modules) |package, *module| {
        module.* = b.addModule(package.name, .{
            .root_source_file = b.path(b.fmt("packages/{s}/root.zig", .{package.name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "kosm", .module = kosm_module }},
        });
        for (package.grammars) |grammar| package_build.addGrammar(b, module.*, b.dependency(grammar, .{}));
    }
    for (modules, 0..) |module, index| {
        for (packages, modules, 0..) |other, other_module, other_index| {
            if (other_index != index) module.addImport(other.name, other_module);
        }
    }
    return modules;
}

/// The modules of every built-in package that `kosm`, a dependency, exposes.
pub fn modulesOf(kosm: *std.Build.Dependency) [packages.len]?*std.Build.Module {
    var modules: [packages.len]?*std.Build.Module = undefined;
    for (packages, &modules) |package, *module| module.* = kosm.builder.modules.get(package.name);
    return modules;
}
