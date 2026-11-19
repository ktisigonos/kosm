//! Finds kosmoi, apps and adapters by reflection, all at compile time.

const std = @import("std");
const kosm = @import("kosm");
const Target = @import("Target.zig");

/// Nested app trees and big package roots need far more than the default 1000 branches.
pub const branch_quota = 10_000_000;

/// Whether `T` is an app: a struct with exactly `pub fn apply(self: T, output: *kosm.Output) !void`.
pub fn isApp(comptime T: type) bool {
    return kosm.app.is(T);
}

/// Whether app `T` declares a reload. A `reload` of any other shape than
/// `pub fn reload(self: T, reloader: *kosm.Reloader) !void` is a compile error, so it is never skipped silently.
pub fn hasReload(comptime T: type) bool {
    @setEvalBranchQuota(branch_quota);
    if (!@hasDecl(T, "reload")) return false;
    const wrong_shape = @typeName(T) ++ ".reload must be `pub fn reload(self: " ++ @typeName(T) ++ ", reloader: *kosm.Reloader) !void`";
    const function = switch (@typeInfo(@TypeOf(T.reload))) {
        .@"fn" => |function| function,
        else => @compileError(wrong_shape),
    };
    if (function.is_generic or function.param_types.len != 2) @compileError(wrong_shape);
    if (function.param_types[0] != T or function.param_types[1] != *kosm.Reloader) @compileError(wrong_shape);
    const Return = function.return_type orelse @compileError(wrong_shape);
    switch (@typeInfo(Return)) {
        .error_union => |error_union| if (error_union.payload != void) @compileError(wrong_shape),
        else => @compileError(wrong_shape),
    }
    return true;
}

/// Whether a kosmos tree of type `T` holds at least one app, looking through structs and optionals.
pub fn containsApp(comptime T: type) bool {
    @setEvalBranchQuota(branch_quota);
    const Unwrapped = switch (@typeInfo(T)) {
        .optional => |optional| optional.child,
        else => T,
    };
    if (isApp(Unwrapped)) return true;
    if (@typeInfo(Unwrapped) != .@"struct") return false;
    inline for (@typeInfo(Unwrapped).@"struct".field_types) |Field| {
        if (containsApp(Field)) return true;
    }
    return false;
}

/// Why `File.name` is not a kosmos, or null when it is one.
pub fn notKosmosReason(comptime File: type, comptime name: []const u8) ?[]const u8 {
    @setEvalBranchQuota(branch_quota);
    if (!@hasDecl(File, name)) return "there is no public declaration with that name";
    const function = switch (@typeInfo(@TypeOf(@field(File, name)))) {
        .@"fn" => |function| function,
        else => return "it is not a function",
    };
    if (function.is_generic) return "it is generic";
    switch (function.param_types.len) {
        0 => {},
        1 => if (!isParams(function.param_types[0] orelse return "its parameter has no concrete type"))
            return "its parameter must be a Params struct whose fields all have defaults",
        else => return "it takes more than one parameter",
    }
    const Tree = Payload(function.return_type orelse return "its return type is not concrete");
    if (@typeInfo(Tree) != .@"struct" or !containsApp(Tree)) return "it does not return a struct holding at least one app";
    return null;
}

/// One kosmos a file declares: where its function is, and its name after the file's.
pub const Declared = struct {
    /// `""` for the file's own `kosmos`, `iced` for a variant, `catppuccin` for a group's own
    /// `kosmos`, `catppuccin.latte` for a variant in a group.
    name: []const u8,
    /// The file, or the group, declaring the function.
    Namespace: type,
    /// The function's name in `Namespace`.
    function: []const u8,
};

/// Every kosmos function in `File` and in its groups, in declaration order. A group is a public
/// struct declared in the file (not imported) holding at least one kosmos.
pub fn declaredKosmoi(comptime File: type) []const Declared {
    @setEvalBranchQuota(branch_quota);
    comptime var found: []const Declared = &.{};
    inline for (@typeInfo(File).@"struct".decl_names) |name| {
        if (comptime notKosmosReason(File, name) == null) {
            found = found ++ .{Declared{ .name = comptime if (std.mem.eql(u8, name, "kosmos")) "" else name, .Namespace = File, .function = name }};
        } else if (comptime isGroup(File, name)) {
            inline for (comptime declaredKosmoi(@field(File, name))) |inner| {
                found = found ++ .{Declared{ .name = comptime if (inner.name.len == 0) name else name ++ "." ++ inner.name, .Namespace = inner.Namespace, .function = inner.function }};
            }
        }
    }
    const final = found[0..found.len].*;
    return &final;
}

/// Whether `File.name` is a group of kosmoi: a public struct declared inside `File`, so a
/// re-exported package is not one, holding at least one kosmos.
pub fn isGroup(comptime File: type, comptime name: []const u8) bool {
    @setEvalBranchQuota(branch_quota);
    if (!@hasDecl(File, name) or @TypeOf(@field(File, name)) != type) return false;
    const Group = @field(File, name);
    if (@typeInfo(Group) != .@"struct") return false;
    if (comptime !std.mem.eql(u8, @typeName(Group), @typeName(File) ++ "." ++ name)) return false;
    return comptime declaredKosmoi(Group).len != 0;
}

/// The kosmos `name` (as `declaredKosmoi` names them, `kosmos` also naming the file's own) in
/// `File`, or null.
pub fn findKosmos(comptime File: type, comptime name: []const u8) ?Declared {
    const wanted = comptime if (std.mem.eql(u8, name, "kosmos")) "" else name;
    inline for (comptime declaredKosmoi(File)) |declared| {
        if (comptime std.mem.eql(u8, declared.name, wanted)) return declared;
    }
    return null;
}

/// Why `name` in `File` (`kosmos`, `iced`, `catppuccin.latte`) is not a kosmos.
pub fn notFoundReason(comptime File: type, comptime name: []const u8) []const u8 {
    return comptime reason: {
        const dot = std.mem.findScalar(u8, name, '.') orelse {
            if (isGroup(File, name)) break :reason "it is a group without a kosmos of its own; add `pub fn kosmos()` to it";
            break :reason notKosmosReason(File, name) orelse "it is not a kosmos";
        };
        const group = name[0..dot];
        if (!isGroup(File, group)) break :reason "'" ++ group ++ "' is not a group of kosmoi: a public struct declared in the file holding at least one kosmos";
        break :reason notFoundReason(@field(File, group), name[dot + 1 ..]);
    };
}

/// The kosmoi in `File`, comma-separated, as `kosm apply` spells them (`frost, frost.iced,
/// frost.cold.deep`), or "none".
pub fn kosmosList(comptime File: type, comptime file_name: []const u8) []const u8 {
    @setEvalBranchQuota(branch_quota);
    comptime var list: []const u8 = "";
    inline for (comptime declaredKosmoi(File)) |declared| {
        const spelled = if (declared.name.len == 0) file_name else file_name ++ "." ++ declared.name;
        list = list ++ (if (list.len == 0) "" else ", ") ++ spelled;
    }
    return if (list.len == 0) "none" else list;
}

/// Every public struct type declared at the top of `Module` that holds apps without being one:
/// a base (`kosm_base.Base`) or a kosmos' own tree, which a script may build and return.
pub fn exportedTrees(comptime Module: type) []const type {
    @setEvalBranchQuota(branch_quota);
    comptime var found: []const type = &.{};
    inline for (@typeInfo(Module).@"struct".decl_names) |name| {
        if (comptime @TypeOf(@field(Module, name)) == type) {
            const Exported = @field(Module, name);
            if (comptime @typeInfo(Exported) == .@"struct" and !isApp(Exported) and containsApp(Exported)) found = found ++ .{Exported};
        }
    }
    const final = found[0..found.len].*;
    return &final;
}

/// The tree type a kosmos function returns, without its error union.
pub fn Payload(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .error_union => |error_union| error_union.payload,
        else => T,
    };
}

fn isParams(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    for (@typeInfo(T).@"struct".field_attrs) |attributes| {
        if (attributes.default_value_ptr == null) return false;
    }
    return true;
}

/// The adapters a kosmos can use, and the names packages export as different adapters.
pub const Adapters = struct {
    /// One adapter per name: the first found when packages clash.
    list: []const kosm.Adapter,
    clashes: []const kosm.Output.AdapterClash,
};

/// Every public `kosm.Adapter` constant declared at the top of `Module`.
pub fn declaredAdapters(comptime Module: type) []const kosm.Adapter {
    @setEvalBranchQuota(branch_quota);
    comptime var found: []const kosm.Adapter = &.{};
    inline for (@typeInfo(Module).@"struct".decl_names) |name| {
        if (@TypeOf(@field(Module, name)) == kosm.Adapter) found = found ++ .{@field(Module, name)};
    }
    const final = found[0..found.len].*;
    return &final;
}

/// The adapters of every module in `sources`. An adapter reached twice (a re-export) counts
/// once; a name exported as two different adapters is a clash.
pub fn adapters(comptime sources: []const Target.AdapterSource) Adapters {
    @setEvalBranchQuota(branch_quota);
    comptime var list: []const kosm.Adapter = &.{};
    comptime var packages: []const []const u8 = &.{};
    comptime var clashes: []const kosm.Output.AdapterClash = &.{};
    inline for (sources) |source| {
        inline for (comptime declaredAdapters(source.module)) |adapter| {
            const index = comptime indexOfName(list, adapter.name);
            if (index == null) {
                list = list ++ .{adapter};
                packages = packages ++ .{source.package};
            } else if (!std.meta.eql(list[index.?], adapter) and indexOfClash(clashes, adapter.name) == null) {
                clashes = clashes ++ .{kosm.Output.AdapterClash{ .name = adapter.name, .first_package = packages[index.?], .second_package = source.package }};
            }
        }
    }
    const final_list = list[0..list.len].*;
    const final_clashes = clashes[0..clashes.len].*;
    return .{ .list = &final_list, .clashes = &final_clashes };
}

/// A frontend and the package declaring it, as the user spells it.
pub const DeclaredFrontend = struct {
    package: []const u8,
    frontend: kosm.Frontend,
};

/// Every public `kosm.Frontend` constant declared at the top of each module in `sources`. A
/// frontend reached twice (a re-export) counts once.
pub fn frontends(comptime sources: []const Target.AdapterSource) []const DeclaredFrontend {
    @setEvalBranchQuota(branch_quota);
    comptime var found: []const DeclaredFrontend = &.{};
    inline for (sources) |source| {
        inline for (@typeInfo(source.module).@"struct".decl_names) |name| {
            if (@TypeOf(@field(source.module, name)) == kosm.Frontend) {
                const frontend = @field(source.module, name);
                const known = for (found) |existing| {
                    if (std.meta.eql(existing.frontend, frontend)) break true;
                } else false;
                if (!known) found = found ++ .{DeclaredFrontend{ .package = source.package, .frontend = frontend }};
            }
        }
    }
    const final = found[0..found.len].*;
    return &final;
}

/// A module that may export an app, and its name as the user imports it.
pub const AppSource = struct {
    package: []const u8,
    module: type,
};

/// The prefix official packages share, which a kosmos without a base leaves out of its app
/// names (`kosm_kitty` gives `kitty`).
const official_prefix = "kosm_";

/// The field a kosmos without a base names `package`'s app by.
pub fn appName(comptime package: []const u8) []const u8 {
    if (std.mem.startsWith(u8, package, official_prefix) and package.len > official_prefix.len) return package[official_prefix.len..];
    return package;
}

/// Whether `Module` exports an app a theme alone builds: `App`, and `from(theme: kosm.Theme) App`.
fn buildsFromTheme(comptime Module: type) bool {
    if (!@hasDecl(Module, "App") or @TypeOf(Module.App) != type) return false;
    if (!isApp(Module.App) or !@hasDecl(Module, "from")) return false;
    return @TypeOf(Module.from) == fn (kosm.Theme) Module.App;
}

/// The tree of a kosmos without a base: one optional field per app in `sources` that a theme
/// alone builds, named by `appName`, each null (not applied) by default. Two packages giving the
/// same name are a compile error naming both.
pub fn Standalone(comptime sources: []const AppSource) type {
    @setEvalBranchQuota(branch_quota);
    comptime var names: []const []const u8 = &.{};
    comptime var packages: []const []const u8 = &.{};
    comptime var types: []const type = &.{};
    inline for (sources) |source| {
        if (comptime !buildsFromTheme(source.module)) continue;
        const name = comptime appName(source.package);
        inline for (names, packages) |existing, package| {
            if (comptime std.mem.eql(u8, existing, name))
                @compileError("packages '" ++ package ++ "' and '" ++ source.package ++ "' both give a kosmos without a base the app '" ++ name ++ "'; remove one of them");
        }
        names = names ++ .{name};
        packages = packages ++ .{source.package};
        types = types ++ .{?source.module.App};
    }
    comptime var attributes: [names.len]std.lang.Type.Struct.FieldAttributes = undefined;
    inline for (types, 0..) |Field, index| {
        const default: Field = null;
        attributes[index] = .{ .default_value_ptr = &default };
    }
    return @Struct(.auto, null, names, types[0..names.len], &attributes);
}

/// The module exporting each field's app in `Standalone(sources)`, in field order.
pub fn standaloneModules(comptime sources: []const AppSource) []const type {
    comptime var modules: []const type = &.{};
    inline for (sources) |source| {
        if (comptime buildsFromTheme(source.module)) modules = modules ++ .{source.module};
    }
    const final = modules[0..modules.len].*;
    return &final;
}

/// The package of each field's app in `Standalone(sources)`, in field order.
pub fn standalonePackages(comptime sources: []const AppSource) []const []const u8 {
    comptime var packages: []const []const u8 = &.{};
    inline for (sources) |source| {
        if (comptime buildsFromTheme(source.module)) packages = packages ++ .{source.package};
    }
    const final = packages[0..packages.len].*;
    return &final;
}

fn indexOfName(list: []const kosm.Adapter, name: []const u8) ?usize {
    for (list, 0..) |adapter, index| {
        if (std.mem.eql(u8, adapter.name, name)) return index;
    }
    return null;
}

fn indexOfClash(clashes: []const kosm.Output.AdapterClash, name: []const u8) ?usize {
    for (clashes, 0..) |clash, index| {
        if (std.mem.eql(u8, clash.name, name)) return index;
    }
    return null;
}

const testing = std.testing;

const TestApp = struct {
    size: u8 = 1,
    pub fn apply(self: TestApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }
};

const NotAnApp = struct {
    pub fn apply(self: NotAnApp, color: kosm.Color) kosm.Color {
        _ = self;
        return color;
    }
};

const test_kosmoi = struct {
    pub const Tree = struct { terminal: struct { kitty: ?TestApp }, other: u8 = 0 };
    pub const Params = struct { blur: bool = false };
    pub fn kosmos() Tree {
        return .{ .terminal = .{ .kitty = .{} } };
    }
    pub fn iced(params: Params) !Tree {
        _ = params;
        return .{ .terminal = .{ .kitty = null } };
    }
    pub fn helper(theme: kosm.Theme) Tree {
        _ = theme;
        return .{ .terminal = .{ .kitty = null } };
    }
    pub fn noApps() struct { modifier: NotAnApp } {
        return .{ .modifier = .{} };
    }
    pub const adapter: kosm.Adapter = .{ .name = "lines" };
    pub const cold = struct {
        pub fn kosmos() Tree {
            return .{ .terminal = .{ .kitty = .{} } };
        }
        pub fn deep() Tree {
            return .{ .terminal = .{ .kitty = null } };
        }
    };
    pub const warm = struct {
        pub fn mild() Tree {
            return .{ .terminal = .{ .kitty = null } };
        }
    };
    pub const imported = other_kosmoi;
};

const other_kosmoi = struct {
    pub fn kosmos() test_kosmoi.Tree {
        return .{ .terminal = .{ .kitty = .{} } };
    }
};

test "an app needs exactly apply(self, *Output) !void" {
    try testing.expect(isApp(TestApp));
    try testing.expect(!isApp(NotAnApp));
    try testing.expect(!isApp(kosm.Modifier));
    try testing.expect(!isApp(u8));
}

const ReloadingApp = struct {
    pub fn apply(self: ReloadingApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }
    pub fn reload(self: ReloadingApp, reloader: *kosm.Reloader) !void {
        _ = self;
        _ = reloader;
    }
};

test "an app reloads only when it declares reload" {
    try testing.expect(hasReload(ReloadingApp));
    try testing.expect(!hasReload(TestApp));
}

test "kosmoi are found by shape, and the rest say why not" {
    try testing.expect(notKosmosReason(test_kosmoi, "kosmos") == null);
    try testing.expect(notKosmosReason(test_kosmoi, "iced") == null);
    try testing.expectEqualStrings("its parameter must be a Params struct whose fields all have defaults", notKosmosReason(test_kosmoi, "helper").?);
    try testing.expectEqualStrings("it does not return a struct holding at least one app", notKosmosReason(test_kosmoi, "noApps").?);
    try testing.expectEqualStrings("it is not a function", notKosmosReason(test_kosmoi, "adapter").?);
    try testing.expectEqualStrings("there is no public declaration with that name", notKosmosReason(test_kosmoi, "missing").?);
    try testing.expectEqualStrings("frost, frost.iced, frost.cold, frost.cold.deep, frost.warm.mild", kosmosList(test_kosmoi, "frost"));
}

test "a module's trees are its public structs holding apps, not apps, namespaces or other structs" {
    const trees = comptime exportedTrees(test_kosmoi);
    try testing.expectEqual(1, trees.len);
    try testing.expect(trees[0] == test_kosmoi.Tree);
    try testing.expectEqual(0, comptime exportedTrees(struct {
        pub const App = TestApp;
        pub const Params = struct { blur: bool = false };
    }).len);
}

test "groups are public structs of the file holding kosmoi, found by dotted name" {
    try testing.expect(isGroup(test_kosmoi, "cold"));
    try testing.expect(!isGroup(test_kosmoi, "Tree"));
    try testing.expect(!isGroup(test_kosmoi, "imported"));
    try testing.expect(!isGroup(test_kosmoi, "Params"));
    try testing.expectEqualStrings("deep", comptime findKosmos(test_kosmoi, "cold.deep").?.function);
    try testing.expectEqualStrings("kosmos", comptime findKosmos(test_kosmoi, "cold").?.function);
    try testing.expect(comptime findKosmos(test_kosmoi, "kosmos").?.Namespace == test_kosmoi);
    try testing.expect(comptime findKosmos(test_kosmoi, "cold.missing") == null);
    try testing.expectEqualStrings("there is no public declaration with that name", notFoundReason(test_kosmoi, "cold.missing"));
    try testing.expectEqualStrings("'Tree' is not a group of kosmoi: a public struct declared in the file holding at least one kosmos", notFoundReason(test_kosmoi, "Tree.x"));
    try testing.expectEqualStrings("it is a group without a kosmos of its own; add `pub fn kosmos()` to it", notFoundReason(test_kosmoi, "warm"));
}

test "adapters are collected from every source" {
    const found = comptime adapters(&.{ .{ .package = "frost", .module = test_kosmoi }, .{ .package = "empty", .module = struct {} } });
    try testing.expectEqual(1, found.list.len);
    try testing.expectEqualStrings("lines", found.list[0].name);
    try testing.expectEqual(0, found.clashes.len);
}

const lines_adapter: kosm.Adapter = .{ .name = "lines", .extensions = &.{".lines"} };
const other_lines_adapter: kosm.Adapter = .{ .name = "lines", .extensions = &.{".text"} };

test "a re-exported adapter counts once and is no clash" {
    const original = struct {
        pub const lines = lines_adapter;
    };
    const reexporting = struct {
        pub const lines = original.lines;
        pub const alias = original.lines;
    };
    const found = comptime adapters(&.{ .{ .package = "kosm_lines", .module = original }, .{ .package = "my_lines", .module = reexporting } });
    try testing.expectEqual(1, found.list.len);
    try testing.expectEqual(0, found.clashes.len);
}

test "one name exported as two adapters clashes, naming both packages once" {
    const first = struct {
        pub const lines = lines_adapter;
    };
    const second = struct {
        pub const lines = other_lines_adapter;
    };
    const third = struct {
        pub const lines: kosm.Adapter = .{ .name = "lines", .extensions = &.{".third"} };
    };
    const found = comptime adapters(&.{ .{ .package = "kosm_lines", .module = first }, .{ .package = "my_lines", .module = second }, .{ .package = "more_lines", .module = third } });
    try testing.expectEqual(1, found.list.len);
    try testing.expectEqualStrings(".lines", found.list[0].extensions[0]);
    try testing.expectEqual(1, found.clashes.len);
    try testing.expectEqualStrings("lines", found.clashes[0].name);
    try testing.expectEqualStrings("kosm_lines", found.clashes[0].first_package);
    try testing.expectEqualStrings("my_lines", found.clashes[0].second_package);
}

test "one package exporting two adapters of one name clashes with itself" {
    const both = struct {
        pub const lines = lines_adapter;
        pub const other = other_lines_adapter;
    };
    const found = comptime adapters(&.{.{ .package = "kosm_lines", .module = both }});
    try testing.expectEqual(1, found.clashes.len);
    try testing.expectEqualStrings("kosm_lines", found.clashes[0].first_package);
    try testing.expectEqualStrings("kosm_lines", found.clashes[0].second_package);
}
