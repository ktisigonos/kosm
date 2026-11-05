//! Finds kosmoi (D17), apps (D18, D53) and adapters (D39) by reflection, all at compile time.

const std = @import("std");
const kosm = @import("kosm");

/// Nested app trees and big package roots need far more than the default 1000 branches.
pub const branch_quota = 100_000;

/// Whether `T` is an app: a struct with exactly `pub fn apply(self: T, output: *kosm.Output) !void` (D53).
/// `Modifier.apply(Color) Color` does not count.
pub fn isApp(comptime T: type) bool {
    @setEvalBranchQuota(branch_quota);
    if (@typeInfo(T) != .@"struct" or !@hasDecl(T, "apply")) return false;
    const function = switch (@typeInfo(@TypeOf(T.apply))) {
        .@"fn" => |function| function,
        else => return false,
    };
    if (function.is_generic or function.param_types.len != 2) return false;
    if (function.param_types[0] != T or function.param_types[1] != *kosm.Output) return false;
    const Return = function.return_type orelse return false;
    return switch (@typeInfo(Return)) {
        .error_union => |error_union| error_union.payload == void,
        else => false,
    };
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

/// Why `File.name` is not a kosmos (D17), or null when it is one.
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

/// The public kosmos functions in `File`, comma-separated, as `kosm apply` spells them
/// (`frost, frost.iced`), or "none".
pub fn kosmosList(comptime File: type, comptime file_name: []const u8) []const u8 {
    @setEvalBranchQuota(branch_quota);
    comptime var list: []const u8 = "";
    inline for (@typeInfo(File).@"struct".decl_names) |name| {
        if (comptime notKosmosReason(File, name) == null) {
            const spelled = if (comptime std.mem.eql(u8, name, "kosmos")) file_name else file_name ++ "." ++ name;
            list = list ++ (if (list.len == 0) "" else ", ") ++ spelled;
        }
    }
    return if (list.len == 0) "none" else list;
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

/// Every public `kosm.Adapter` constant declared at the top of each module in `sources`.
pub fn adapters(comptime sources: []const type) []const kosm.Adapter {
    @setEvalBranchQuota(branch_quota);
    comptime var found: []const kosm.Adapter = &.{};
    inline for (sources) |Source| {
        inline for (@typeInfo(Source).@"struct".decl_names) |name| {
            if (@TypeOf(@field(Source, name)) == kosm.Adapter) found = found ++ .{@field(Source, name)};
        }
    }
    const final = found[0..found.len].*;
    return &final;
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
};

test "an app needs exactly apply(self, *Output) !void" {
    try testing.expect(isApp(TestApp));
    try testing.expect(!isApp(NotAnApp));
    try testing.expect(!isApp(kosm.Modifier));
    try testing.expect(!isApp(u8));
}

test "kosmoi are found by shape, and the rest say why not" {
    try testing.expect(notKosmosReason(test_kosmoi, "kosmos") == null);
    try testing.expect(notKosmosReason(test_kosmoi, "iced") == null);
    try testing.expectEqualStrings("its parameter must be a Params struct whose fields all have defaults", notKosmosReason(test_kosmoi, "helper").?);
    try testing.expectEqualStrings("it does not return a struct holding at least one app", notKosmosReason(test_kosmoi, "noApps").?);
    try testing.expectEqualStrings("it is not a function", notKosmosReason(test_kosmoi, "adapter").?);
    try testing.expectEqualStrings("there is no public declaration with that name", notKosmosReason(test_kosmoi, "missing").?);
    try testing.expectEqualStrings("frost, frost.iced", kosmosList(test_kosmoi, "frost"));
}

test "adapters are collected from every source" {
    const found = comptime adapters(&.{ test_kosmoi, struct {} });
    try testing.expectEqual(1, found.len);
    try testing.expectEqualStrings("lines", found[0].name);
}
