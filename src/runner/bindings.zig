//! The library a script calls Zig code through, built by reflection from the config's modules:
//! every public function whose parameters a script can give, every public value, and every
//! struct or union holding them, as namespaces; every Zig kosmos under `kosmoi`. Values a
//! call returns stay typed and reach the script as handles.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const kosmos_call = @import("kosmos_call.zig");
const lifetime = @import("lifetime.zig");
const Runtime = @import("Runtime.zig");
const completion_types = @import("completion_types.zig");

const Call = kosm.Frontend.Call;
const Function = kosm.Frontend.Function;
const Handle = kosm.Frontend.Handle;
const Loose = kosm.Loose;
const Namespace = kosm.Frontend.Namespace;

const branch_quota = 10_000_000;

/// How deep namespaces nest below a global (`kosm.Theme.Input` is 2), and how deep a type's
/// name is searched for.
const max_depth = 3;

/// How deep `isData` looks into a type; a type holding itself is taken for data beyond it.
const max_data_depth = 8;

/// A module whose public declarations become a global of the same name.
pub const Root = struct {
    name: []const u8,
    module: type,
};

/// The library of `roots` (the config's modules; `kosm` is added) and `kosmoi`.
pub fn Library(comptime roots: []const Root, comptime kosmoi: []const kosmos_call.ZigKosmos) type {
    return struct {
        const all_roots: []const Root = .{Root{ .name = "kosm", .module = kosm }} ++ roots;

        /// Every global: `kosm`, `kosmoi`, then each root.
        pub const globals: []const *const Namespace = blk: {
            @setEvalBranchQuota(branch_quota);
            var found: []const *const Namespace = &.{ &NamespaceOf(kosm, "kosm", 0).namespace, &KosmoiOf("kosmoi", "").namespace };
            for (roots) |root| found = found ++ .{&NamespaceOf(root.module, root.name, 0).namespace};
            const final = found[0..found.len].*;
            break :blk &final;
        };

        /// The library to hand a frontend, its calls running with `runtime`.
        pub fn library(runtime: *Runtime) kosm.Frontend.Library {
            return .{ .globals = globals, .state = runtime };
        }

        /// The table of `T`, a struct, union, array or list a handle holds.
        pub fn typeOf(comptime T: type) *const Handle.Type {
            return &TypeTable(T).table;
        }

        /// Describes every namespace but `kosmoi` for completion, and the methods of the records
        /// that have some, by the rules the library is bound by.
        pub fn describe(builder: *completion_types.Builder) completion_types.Error![]const kosm.Frontend.Completion.Namespace {
            @setEvalBranchQuota(branch_quota);
            var described: std.ArrayList(kosm.Frontend.Completion.Namespace) = .empty;
            inline for (all_roots) |root| try describeSpace(builder, &described, root.module, root.name, root.name, &.{}, 0);
            return described.items;
        }

        fn describeSpace(
            builder: *completion_types.Builder,
            described: *std.ArrayList(kosm.Frontend.Completion.Namespace),
            comptime Space: type,
            comptime name: []const u8,
            comptime module: []const u8,
            comptime path: []const []const u8,
            comptime depth: usize,
        ) completion_types.Error!void {
            const Completion = kosm.Frontend.Completion;
            const arena = builder.arena;
            var functions: std.ArrayList(Completion.Function) = .empty;
            var values: std.ArrayList(Completion.Field) = .empty;
            var methods: std.ArrayList(Completion.Function) = .empty;
            // Named by its declaration before its functions describe it under other names.
            const record: ?[]const u8 = if (path.len != 0 and @typeInfo(Space) == .@"struct") try builder.declaredRecord(Space, module, path) else null;
            // So are the types it declares, which a function before them may take (`*Output`).
            inline for (comptime declNames(Space)) |decl_name| {
                const decl = @field(Space, decl_name);
                if (@TypeOf(decl) == type and depth < max_depth and @typeInfo(decl) == .@"struct" and comptime isWalkable(decl) and NamespaceOf(decl, name ++ "." ++ decl_name, depth + 1).namespace.entries.len != 0) {
                    _ = try builder.declaredRecord(decl, module, path ++ .{decl_name});
                }
            }
            inline for (comptime declNames(Space)) |decl_name| {
                const decl = @field(Space, decl_name);
                const Declared = @TypeOf(decl);
                const full = name ++ "." ++ decl_name;
                const decl_path = path ++ .{decl_name};
                if (Declared == type) {
                    if (depth < max_depth and comptime isWalkable(decl) and NamespaceOf(decl, full, depth + 1).namespace.entries.len != 0) {
                        try describeSpace(builder, described, decl, full, module, decl_path, depth + 1);
                        try values.append(arena, .{ .name = decl_name, .type = .{ .namespace = full } });
                    }
                } else if (@typeInfo(Declared) == .@"fn") {
                    if (comptime !isKosmos(Space, decl_name) and !isRunByKosm(Space, decl_name) and isBindable(Declared)) {
                        const written = try builder.sources.declarationPath(module, decl_path);
                        const declaration = if (written) |found| try builder.sources.followAlias(found) else null;
                        const function = try builder.describeFunction(Declared, decl_name, full, declaration);
                        try functions.append(arena, function);
                        if (comptime takesSelf(Declared, Space)) try methods.append(arena, function);
                    }
                } else if (comptime isData(Declared, 0) and !isRunByKosm(Space, decl_name)) {
                    const declaration = try builder.sources.declarationPath(module, decl_path);
                    const expression = if (declaration) |found| found.value else null;
                    if (try builder.typeOf(Declared, full, expression, 0)) |value_type| {
                        try values.append(arena, .{ .name = decl_name, .doc = if (declaration) |found| found.doc else null, .type = value_type });
                    }
                }
            }
            const doc = if (path.len == 0)
                if (try builder.sources.module(module)) |root| try builder.sources.containerDoc(root) else null
            else if (try builder.sources.declarationPath(module, path)) |found| found.doc else null;
            try described.append(arena, .{ .name = name, .doc = doc, .functions = functions.items, .values = values.items });
            if (record) |record_name| builder.addMethods(record_name, methods.items);
        }

        fn NamespaceOf(comptime Space: type, comptime name: []const u8, comptime depth: usize) type {
            return struct {
                const namespace: Namespace = .{ .name = name, .entries = entriesOf(Space, name, depth) };
            };
        }

        fn entriesOf(comptime Space: type, comptime name: []const u8, comptime depth: usize) []const Namespace.Entry {
            @setEvalBranchQuota(branch_quota);
            comptime var entries: []const Namespace.Entry = &.{};
            inline for (comptime declNames(Space)) |decl_name| {
                const decl = @field(Space, decl_name);
                const Declared = @TypeOf(decl);
                const full = name ++ "." ++ decl_name;
                if (Declared == type) {
                    if (depth < max_depth and comptime isWalkable(decl)) {
                        // Kept when empty too, so a script names the type (`kosm.takes(kosm.Theme.Input, ...)`).
                        const child = &NamespaceOf(decl, full, depth + 1).namespace;
                        entries = entries ++ .{Namespace.Entry{ .name = decl_name, .kind = .{ .namespace = child } }};
                    }
                } else if (@typeInfo(Declared) == .@"fn") {
                    if (comptime !isKosmos(Space, decl_name) and !isRunByKosm(Space, decl_name) and isBindable(Declared)) {
                        entries = entries ++ .{Namespace.Entry{ .name = decl_name, .kind = .{ .function = bind(decl, decl_name, full) } }};
                    }
                } else if (comptime isData(Declared, 0) and !isRunByKosm(Space, decl_name)) {
                    entries = entries ++ .{Namespace.Entry{ .name = decl_name, .kind = .{ .constant = constant(Declared, decl, decl_name, full) } }};
                }
            }
            const final = entries[0..entries.len].*;
            return &final;
        }

        /// The namespace of the kosmoi named `prefix` and below (`kosmoi.personal`), callable
        /// when `prefix` is a kosmos itself.
        fn KosmoiOf(comptime name: []const u8, comptime prefix: []const u8) type {
            return struct {
                const namespace: Namespace = blk: {
                    @setEvalBranchQuota(branch_quota);
                    var entries: []const Namespace.Entry = &.{};
                    var seen: []const []const u8 = &.{};
                    for (kosmoi) |entry| {
                        const rest = if (prefix.len == 0) entry.name else if (std.mem.startsWith(u8, entry.name, prefix ++ ".")) entry.name[prefix.len + 1 ..] else continue;
                        const segment = rest[0 .. std.mem.findScalar(u8, rest, '.') orelse rest.len];
                        if (isListed(seen, segment)) continue;
                        seen = seen ++ .{segment};
                        const child = if (prefix.len == 0) segment else prefix ++ "." ++ segment;
                        const full = name ++ "." ++ segment;
                        if (hasVariants(child)) {
                            entries = entries ++ .{Namespace.Entry{ .name = segment, .kind = .{ .namespace = &KosmoiOf(full, child).namespace } }};
                        } else {
                            entries = entries ++ .{Namespace.Entry{ .name = segment, .kind = .{ .function = bindKosmos(kosmosNamed(child).?, segment, full) } }};
                        }
                    }
                    const own: ?Function = if (prefix.len == 0) null else if (kosmosNamed(prefix)) |entry| bindKosmos(entry, name, name) else null;
                    const final = entries[0..entries.len].*;
                    break :blk .{ .name = name, .call = own, .entries = &final };
                };
            };
        }

        fn hasVariants(comptime name: []const u8) bool {
            for (kosmoi) |entry| {
                if (std.mem.startsWith(u8, entry.name, name ++ ".")) return true;
            }
            return false;
        }

        fn kosmosNamed(comptime name: []const u8) ?kosmos_call.ZigKosmos {
            for (kosmoi) |entry| {
                if (std.mem.eql(u8, entry.name, name)) return entry;
            }
            return null;
        }

        /// A function calling the Zig kosmos `entry`, with its `Params` from an optional table,
        /// and returning its tree.
        fn bindKosmos(comptime entry: kosmos_call.ZigKosmos, comptime short: []const u8, comptime full: []const u8) Function {
            const kosmos = @field(entry.Namespace, entry.function);
            const Tree = discovery.Payload(@typeInfo(@TypeOf(kosmos)).@"fn".return_type.?);
            const Wrapper = struct {
                fn call(given: *Call, arguments: []const Loose) Call.Error!Loose {
                    if (arguments.len > 1) return given.fail("{s} takes a table of its parameters, or nothing, got {d} arguments", .{ full, arguments.len });
                    const runtime: *Runtime = @ptrCast(@alignCast(given.state orelse return given.fail("{s} cannot be called here", .{full})));
                    var diagnostics: kosm.Diagnostics = .{ .kosmos = entry.name };
                    var stack: lifetime.Stack = undefined;
                    const layers: []const kosmos_call.Layer = if (arguments.len == 0) &.{} else &.{.{ .values = arguments[0], .folder = runtime.scripts_folder }};
                    const depth = runtime.building.depth();
                    defer runtime.building.restore(depth);
                    runtime.building.enter(runtime.arena, entry.name, &diagnostics) catch |err| return reported(given, err, full, &diagnostics);
                    const scripts_folder = runtime.scripts_folder;
                    // Scripts the kosmos builds on point it at their own folders while they load.
                    defer runtime.scripts_folder = scripts_folder;
                    var tree = kosmos_call.callKosmos(kosmos, .{ .arguments = &.{}, .layers = layers, .kosmoi = runtime.kosmoi }, &diagnostics, &stack, runtime.loading(entry.folder, &diagnostics)) catch |err| return reported(given, err, full, &diagnostics);
                    kosmos_call.refuseDeadLists(given.arena, tree, &.{ .below(@intFromPtr(&tree)), stack }, &diagnostics) catch |err| return reported(given, err, full, &diagnostics);
                    return owned(Tree, given, tree);
                }
            };
            return .{ .name = short, .call = Wrapper.call };
        }

        fn reported(given: *Call, err: anyerror, comptime full: []const u8, diagnostics: *kosm.Diagnostics) Call.Error {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (err == error.Reported) return given.fail("{s}: {s}", .{ full, diagnostics.message() });
            return given.fail("{s}: {s}", .{ full, @errorName(err) });
        }

        /// A function calling `function`, each argument read into its parameter's type, on a
        /// stack of its own.
        fn bind(comptime function: anytype, comptime short: []const u8, comptime full: []const u8) Function {
            const info = @typeInfo(@TypeOf(function)).@"fn";
            const Returned = info.return_type.?;
            const Result = discovery.Payload(Returned);
            const Wrapper = struct {
                fn call(given: *Call, arguments: []const Loose) Call.Error!Loose {
                    if (arguments.len != info.param_types.len) return given.fail("{s} takes {d} argument{s}, got {d}", .{ full, info.param_types.len, if (info.param_types.len == 1) "" else "s", arguments.len });
                    var tuple: std.meta.ArgsTuple(@TypeOf(function)) = undefined;
                    inline for (info.param_types, 0..) |Parameter, index| {
                        tuple[index] = try argument(Parameter.?, given, arguments[index], full, index + 1);
                    }
                    var returned: Returned = undefined;
                    kosm.failure.clear();
                    var diagnostics: kosm.Diagnostics = .{};
                    const stack = kosmos_call.callOnKosmosStack(function, tuple, &returned, &diagnostics) catch
                        return given.fail("{s}: {s}", .{ full, diagnostics.message() });
                    const result: Result = if (@typeInfo(Returned) == .error_union) returned catch |err| {
                        if (@as(anyerror, err) == error.KosmosFailed) {
                            if (kosm.failure.message()) |message| return given.fail("{s}: {s}", .{ full, message });
                        }
                        if (comptime serviceMessage(info.param_types)) |Service| {
                            const message = switch (Service) {
                                kosm.Output => tuple[0].diagnostics.message(),
                                kosm.Output.Selection => tuple[0].output.diagnostics.message(),
                                else => tuple[0].failure(),
                            };
                            if (message.len != 0) return given.fail("{s}: {s}", .{ full, message });
                        }
                        return given.fail("{s} failed: {s}", .{ full, @errorName(err) });
                    } else returned;
                    // An app's `from` cannot fail, so a script's failure in it is only recorded.
                    if (kosm.failure.message()) |message| return given.fail("{s}: {s}", .{ full, message });
                    // A service lives in kosm's own allocator, never on a stack.
                    if (comptime isService(Result)) {
                        const kept = try given.arena.create(Result);
                        kept.* = result;
                        return handleOf(Result, kept);
                    }
                    if (try lifetime.findDeadList(given.arena, result, &.{stack})) |path|
                        return given.fail("{s}: what it returns at {s} points into a function that has returned, so it is garbage; it must keep run-time lists with kosm.keep", .{ full, path });
                    return owned(Result, given, result);
                }
            };
            return .{ .name = short, .call = Wrapper.call };
        }

        /// A function giving a fresh copy of the declared value `value`.
        fn constant(comptime T: type, comptime value: T, comptime short: []const u8, comptime full: []const u8) Function {
            const Wrapper = struct {
                fn call(given: *Call, arguments: []const Loose) Call.Error!Loose {
                    if (arguments.len != 0) return given.fail("{s} is a value, not a function", .{full});
                    return owned(T, given, value);
                }
            };
            return .{ .name = short, .call = Wrapper.call };
        }

        /// `loose` as a `Parameter`: a pointer parameter takes the value of a handle itself, so
        /// a method changing it changes the script's value; others are built like a field.
        fn argument(comptime Parameter: type, given: *Call, loose: Loose, comptime full: []const u8, position: usize) Call.Error!Parameter {
            const parameter = @typeInfo(Parameter);
            if (parameter == .pointer and parameter.pointer.size == .one) {
                const Pointee = parameter.pointer.child;
                if (loose.value == .handle) {
                    if (loose.value.handle.as(Pointee)) |pointer| return pointer;
                }
                return given.fail("{s}: argument {d}: expected a {s}, got {s}", .{ full, position, nameOf(Pointee), try describeGiven(given.arena, loose) });
            }
            var diagnostics: kosm.Diagnostics = .{};
            const label = try given.arena.print("argument {d}", .{position});
            return kosm.assignment.build(Parameter, given.arena, loose, &diagnostics, label) catch |err| switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidAssignment => given.fail("{s}: {s}", .{ full, diagnostics.message() }),
            };
        }

        /// `value` kept in the arena with its lists, as a script holds it.
        fn owned(comptime T: type, given: *Call, value: T) Call.Error!Loose {
            if (T == void) return .{ .value = .null };
            const kept = try given.arena.create(T);
            kept.* = try kosm.assignment.copy.deep(T, given.arena, value);
            return read(T, given, kept);
        }

        /// What `pointer` holds, as a script sees it: scalars as themselves, enums by name,
        /// structs, unions and lists as handles into it.
        fn read(comptime T: type, given: *Call, pointer: *T) Call.Error!Loose {
            if (T == []const u8) return .{ .value = .{ .string = pointer.* } };
            switch (@typeInfo(T)) {
                .bool => return .{ .value = .{ .boolean = pointer.* } },
                .int => return .{ .value = .{ .integer = std.math.cast(i64, pointer.*) orelse return given.fail("{d} is too large for a script", .{pointer.*}) } },
                .float => return .{ .value = .{ .float = @floatCast(pointer.*) } },
                .@"enum" => return .{ .value = .{ .string = std.enums.tagName(T, pointer.*) orelse return given.fail("a {s} without a name cannot be read from a script", .{nameOf(T)}) } },
                .optional => |optional| {
                    if (pointer.*) |*present| return read(optional.child, given, present);
                    return .{ .value = .null };
                },
                .@"struct" => |info| if (!info.is_tuple) return handleOf(T, pointer),
                .@"union" => |info| if (info.tag_type != null) return handleOf(T, pointer),
                .array => return handleOf(T, pointer),
                .pointer => |info| switch (info.size) {
                    .slice => return handleOf(T, pointer),
                    .one => if (comptime isData(info.child, 0) and @typeInfo(info.child) != .@"fn") return read(info.child, given, @constCast(pointer.*)),
                    else => {},
                },
                else => {},
            }
            return given.fail("a {s} cannot be read from a script", .{@typeName(T)});
        }

        fn handleOf(comptime T: type, pointer: *T) Loose {
            return .{ .value = .{ .handle = .{ .pointer = @ptrCast(pointer), .type = typeOf(T) } } };
        }

        fn TypeTable(comptime T: type) type {
            return struct {
                const table: Handle.Type = .{
                    .id = Handle.id(T),
                    .name = nameOf(T),
                    .fields = if (isService(T)) &.{} else fieldNames(T),
                    .list = isList(T),
                    .methods = methodsOf(T),
                    .get = get,
                    .set = set,
                    .length = length,
                };

                fn get(given: *Call, pointer: *anyopaque, key: Handle.Key) Call.Error!Loose {
                    if (comptime isService(T)) return serviceField(given, key);
                    const value: *T = @ptrCast(@alignCast(pointer));
                    switch (@typeInfo(T)) {
                        .@"struct" => |info| {
                            const name = try fieldKey(given, key);
                            inline for (info.field_names, info.field_types, info.field_attrs) |field_name, Field, attributes| {
                                if (!attributes.@"comptime" and std.mem.eql(u8, field_name, name)) {
                                    return read(Field, given, &@field(value.*, field_name)) catch |err| fieldFailed(given, err, field_name);
                                }
                            }
                            return noField(T, given, name);
                        },
                        .@"union" => |info| {
                            const name = try fieldKey(given, key);
                            inline for (info.field_names, info.field_types) |tag_name, Payload| {
                                if (std.mem.eql(u8, tag_name, name)) {
                                    if (std.meta.activeTag(value.*) != @field(info.tag_type.?, tag_name)) return .{ .value = .null };
                                    if (Payload == void) return .{ .value = .{ .boolean = true } };
                                    return read(Payload, given, &@field(value.*, tag_name));
                                }
                            }
                            return noTag(T, given, name);
                        },
                        else => {
                            const items = itemsOf(value);
                            const index = try itemKey(given, key, items.len);
                            return read(@TypeOf(items[0]), given, &items[index]);
                        },
                    }
                }

                fn set(given: *Call, pointer: *anyopaque, key: Handle.Key, loose: Loose) Call.Error!void {
                    if (comptime isService(T)) return serviceField(given, key);
                    const value: *T = @ptrCast(@alignCast(pointer));
                    if (comptime isReadFromText(T)) return setPart(given, value, try fieldKey(given, key), loose);
                    var diagnostics: kosm.Diagnostics = .{};
                    const result = switch (@typeInfo(T)) {
                        .@"struct", .@"union" => blk: {
                            const name = try fieldKey(given, key);
                            const entries = try given.arena.dupe(Loose.Entry, &.{.{ .key = name, .value = loose }});
                            break :blk kosm.assignment.assignNamed(T, given.arena, value, .{ .value = .{ .table = entries } }, &diagnostics, nameOf(T));
                        },
                        else => blk: {
                            const items = itemsOf(value);
                            const index = try itemKey(given, key, items.len);
                            const label = try given.arena.print("item {d}", .{index + 1});
                            break :blk kosm.assignment.assignNamed(@TypeOf(items[0]), given.arena, &items[index], loose, &diagnostics, label);
                        },
                    };
                    result catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        error.InvalidAssignment => return given.fail("{s}", .{diagnostics.message()}),
                    };
                }

                /// Sets one field (or the tag of a union) of a value otherwise given as text, such
                /// as a color's lightness, which assigning a table to the whole value cannot.
                fn setPart(given: *Call, value: *T, name: []const u8, loose: Loose) Call.Error!void {
                    var diagnostics: kosm.Diagnostics = .{};
                    const result = switch (@typeInfo(T)) {
                        .@"struct" => |info| inline for (info.field_names, info.field_types, info.field_attrs) |field_name, Field, attributes| {
                            if (!attributes.@"comptime" and std.mem.eql(u8, field_name, name)) {
                                break kosm.assignment.assignNamed(Field, given.arena, &@field(value.*, field_name), loose, &diagnostics, field_name);
                            }
                        } else return noField(T, given, name),
                        .@"union" => |info| inline for (info.field_names, info.field_types) |tag_name, Payload| {
                            if (std.mem.eql(u8, tag_name, name)) {
                                break if (kosm.assignment.build(Payload, given.arena, loose, &diagnostics, tag_name)) |payload| {
                                    value.* = @unionInit(T, tag_name, payload);
                                } else |err| err;
                            }
                        } else return noTag(T, given, name),
                        else => comptime unreachable,
                    };
                    result catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        error.InvalidAssignment => return given.fail("{s}", .{diagnostics.message()}),
                    };
                }

                fn length(pointer: *anyopaque) usize {
                    if (comptime !isList(T)) return 0;
                    const value: *T = @ptrCast(@alignCast(pointer));
                    return itemsOf(value).len;
                }

                fn serviceField(given: *Call, key: Handle.Key) Call.Error {
                    return switch (key) {
                        .field => |name| given.fail("{s} has no '{s}'; it gives only methods: {s}", .{ nameOf(T), name, comptime methodList(T) }),
                        .item => given.fail("{s} has no items; it gives only methods: {s}", .{ nameOf(T), comptime methodList(T) }),
                    };
                }

                fn fieldKey(given: *Call, key: Handle.Key) Call.Error![]const u8 {
                    return switch (key) {
                        .field => |name| name,
                        .item => given.fail("{s} has fields, not items", .{nameOf(T)}),
                    };
                }

                fn itemKey(given: *Call, key: Handle.Key, count: usize) Call.Error!usize {
                    return switch (key) {
                        .item => |index| if (index < count) index else given.fail("item {d} is past the end of a list of {d}", .{ index + 1, count }),
                        .field => |name| given.fail("a list has items, not a field '{s}'", .{name}),
                    };
                }

                fn fieldFailed(given: *Call, err: Call.Error, comptime field_name: []const u8) Call.Error {
                    if (err == error.CallFailed) return given.fail("{s}.{s}: {s}", .{ nameOf(T), field_name, given.message.? });
                    return err;
                }
            };
        }

        /// The items of an array or list `value` points to, changeable in place: every list a
        /// handle reaches lives in the run's arena.
        fn itemsOf(value: anytype) ItemsOf(@TypeOf(value.*)) {
            const T = @TypeOf(value.*);
            if (@typeInfo(T) == .array) return value;
            return @constCast(value.*);
        }

        fn ItemsOf(comptime T: type) type {
            return switch (@typeInfo(T)) {
                .array => |array| *[array.len]array.child,
                .pointer => |pointer| []pointer.child,
                else => @compileError("not a list: " ++ @typeName(T)),
            };
        }

        /// The names of `T`'s methods, comma-separated.
        fn methodList(comptime T: type) []const u8 {
            comptime var names: []const u8 = "";
            inline for (comptime methodsOf(T), 0..) |method, index| names = names ++ (if (index == 0) "" else ", ") ++ method.name;
            return names;
        }

        /// The functions declared in `T` taking a `T` (or a pointer to one) first.
        fn methodsOf(comptime T: type) []const Function {
            @setEvalBranchQuota(branch_quota);
            if (comptime !hasDecls(T)) return &.{};
            comptime var methods: []const Function = &.{};
            inline for (comptime declNames(T)) |decl_name| {
                const decl = @field(T, decl_name);
                const Declared = @TypeOf(decl);
                if (@typeInfo(Declared) == .@"fn" and comptime isBindable(Declared) and takesSelf(Declared, T) and !isRunByKosm(T, decl_name)) {
                    methods = methods ++ .{bind(decl, decl_name, nameOf(T) ++ "." ++ decl_name)};
                }
            }
            const final = methods[0..methods.len].*;
            return &final;
        }

        /// "has no field", suggesting the fields close to `name`, or else listing them all.
        fn noField(comptime T: type, given: *Call, name: []const u8) Call.Error {
            const fallback = "its fields are " ++ comptime kosm.assignment.text.fieldList(T);
            return given.fail("{s} has no field '{s}'; {f}", .{ nameOf(T), name, kosm.suggestion.hint(name, comptime kosm.assignment.text.fieldNames(T), fallback) });
        }

        /// "has no tag", suggesting the tags close to `name`, or else listing them all.
        fn noTag(comptime T: type, given: *Call, name: []const u8) Call.Error {
            const fallback = "its tags are " ++ comptime tagList(T);
            return given.fail("{s} has no tag '{s}'; {f}", .{ nameOf(T), name, kosm.suggestion.hint(name, comptime std.meta.fieldNames(T), fallback) });
        }

        /// The name of `T` as a script reaches it (`kosm.Theme.Input`), or its Zig name.
        fn nameOf(comptime T: type) []const u8 {
            @setEvalBranchQuota(branch_quota);
            inline for (all_roots) |root| {
                if (comptime findName(root.module, root.name, T, 0)) |name| return name;
            }
            return @typeName(T);
        }

        fn findName(comptime Space: type, comptime prefix: []const u8, comptime T: type, comptime depth: usize) ?[]const u8 {
            if (depth >= max_depth) return null;
            inline for (comptime declNames(Space)) |decl_name| {
                const decl = @field(Space, decl_name);
                if (@TypeOf(decl) == type and decl == T) return prefix ++ "." ++ decl_name;
            }
            inline for (comptime declNames(Space)) |decl_name| {
                const decl = @field(Space, decl_name);
                if (@TypeOf(decl) == type and comptime isWalkable(decl)) {
                    if (comptime findName(decl, prefix ++ "." ++ decl_name, T, depth + 1)) |name| return name;
                }
            }
            return null;
        }

        /// Whether `Space`, a root, declares `name` as a Zig kosmos, which `kosmoi` holds instead.
        fn isKosmos(comptime Space: type, comptime name: []const u8) bool {
            inline for (roots) |root| {
                if (root.module == Space) {
                    for (discovery.declaredKosmoi(Space)) |declared| {
                        if (declared.Namespace == Space and std.mem.eql(u8, declared.function, name)) return true;
                    }
                }
            }
            return false;
        }
    };
}

/// Whether a script can call a function of type `F`: not generic, every parameter a value a
/// script gives (or a pointer to a struct or union, or to a service, for a handle), returning
/// such a value.
pub fn isBindable(comptime F: type) bool {
    const info = @typeInfo(F).@"fn";
    if (info.is_generic or info.attrs.varargs or info.attrs.@"callconv" != .auto) return false;
    const Returned = info.return_type orelse return false;
    const Result = discovery.Payload(Returned);
    if (Result != void and !isData(Result, 0) and !isService(Result)) return false;
    for (info.param_types) |maybe| {
        const Parameter = maybe orelse return false;
        const parameter = @typeInfo(Parameter);
        if (parameter == .pointer and parameter.pointer.size == .one) {
            if (isService(parameter.pointer.child)) continue;
            const pointee = @typeInfo(parameter.pointer.child);
            if ((pointee != .@"struct" and pointee != .@"union") or !isData(parameter.pointer.child, 0)) return false;
        } else if (!isData(Parameter, 0)) return false;
    }
    return true;
}

/// Whether `name` is a declaration of `T` that only kosm uses: an app's `apply` and `reload`,
/// and the `script` of an app, modifier, palette style, variation family, package kosmos or
/// package's exports written through a frontend.
fn isRunByKosm(comptime T: type, comptime name: []const u8) bool {
    if (std.mem.eql(u8, name, "script") and (isColorScript(@TypeOf(@field(T, name))) or @TypeOf(@field(T, name)) == kosm.Frontend.ScriptKosmos or @TypeOf(@field(T, name)) == kosm.Frontend.ScriptExports)) return true;
    if (!kosm.app.is(T)) return false;
    if (std.mem.eql(u8, name, "script")) return @TypeOf(@field(T, name)) == kosm.Frontend.ScriptApp;
    return std.mem.eql(u8, name, "apply") or std.mem.eql(u8, name, "reload");
}

/// Whether `T` is the `script` type of a modifier, palette style or variation family written
/// through a frontend.
fn isColorScript(comptime T: type) bool {
    return T == kosm.Frontend.ScriptModifier or T == kosm.Frontend.ScriptStyle or T == kosm.Frontend.ScriptFamily;
}

/// Values a script holds only to call their methods (an app's output, the files it edits, its
/// reloader): kosm's own writers, which hold an allocator or `Io` and so are no data.
pub fn isService(comptime T: type) bool {
    return T == kosm.Output or T == kosm.Output.Selection or T == kosm.Reloader;
}

/// The service a function taking one first records its failures in, or null.
fn serviceMessage(comptime parameters: []const ?type) ?type {
    if (parameters.len == 0) return null;
    const First = parameters[0] orelse return null;
    if (@typeInfo(First) != .pointer or @typeInfo(First).pointer.size != .one) return null;
    const Service = @typeInfo(First).pointer.child;
    return if (isService(Service)) Service else null;
}

/// Whether `F`'s first parameter is `T`, `*T` or `*const T`.
fn takesSelf(comptime F: type, comptime T: type) bool {
    const parameters = @typeInfo(F).@"fn".param_types;
    if (parameters.len == 0) return false;
    const First = parameters[0].?;
    return First == T or First == *T or First == *const T;
}

/// Whether a value of `T` is plain data a script may hold: no allocator, writer or other
/// opaque pointer inside it. Function pointers are kept, though a script cannot read them.
pub fn isData(comptime T: type, comptime depth: usize) bool {
    @setEvalBranchQuota(branch_quota);
    if (depth > max_data_depth) return true;
    return switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum", .void => true,
        .optional => |optional| isData(optional.child, depth + 1),
        .array => |array| isData(array.child, depth + 1),
        .@"struct" => |info| !info.is_tuple and inline for (info.field_types, info.field_attrs) |Field, attributes| {
            if (!attributes.@"comptime" and !isData(Field, depth + 1)) break false;
        } else true,
        .@"union" => |info| info.tag_type != null and inline for (info.field_types) |Field| {
            if (!isData(Field, depth + 1)) break false;
        } else true,
        .pointer => |pointer| switch (pointer.size) {
            .slice => isData(pointer.child, depth + 1),
            .one => @typeInfo(pointer.child) == .@"fn" or (@typeInfo(pointer.child) != .@"opaque" and isData(pointer.child, depth + 1)),
            .many, .c => false,
        },
        else => false,
    };
}

/// Whether `T` is a struct or union with fields, whose declarations become a namespace; a
/// file of functions alone (a module like `kosm.diff`) is left out.
fn isWalkable(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| !info.is_tuple and info.field_names.len != 0,
        .@"union" => |info| info.field_names.len != 0,
        else => false,
    };
}

fn hasDecls(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => true,
        else => false,
    };
}

fn declNames(comptime T: type) []const [:0]const u8 {
    return switch (@typeInfo(T)) {
        inline .@"struct", .@"union", .@"enum", .@"opaque" => |info| info.decl_names,
        else => &.{},
    };
}

/// Whether `T` is a struct or union kosm reads from text as a whole (a color), so a table
/// given for it is no assignment of its fields.
fn isReadFromText(comptime T: type) bool {
    const container = @typeInfo(T) == .@"struct" or @typeInfo(T) == .@"union";
    return container and kosm.assignment.text.isParseable(T);
}

fn isList(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .array => true,
        .pointer => |pointer| pointer.size == .slice,
        else => false,
    };
}

fn fieldNames(comptime T: type) []const []const u8 {
    const names: []const [:0]const u8 = switch (@typeInfo(T)) {
        .@"struct" => |info| blk: {
            var kept: []const [:0]const u8 = &.{};
            for (info.field_names, info.field_attrs) |name, attributes| {
                if (!attributes.@"comptime") kept = kept ++ .{name};
            }
            break :blk kept;
        },
        .@"union" => |info| info.field_names,
        else => &.{},
    };
    var plain: [names.len][]const u8 = undefined;
    for (names, 0..) |name, index| plain[index] = name;
    const final = plain;
    return &final;
}

fn tagList(comptime T: type) []const u8 {
    var list: []const u8 = "";
    for (@typeInfo(T).@"union".field_names) |name| list = list ++ (if (list.len == 0) "" else ", ") ++ name;
    return list;
}

fn isListed(list: []const []const u8, name: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, name)) return true;
    }
    return false;
}

/// What a script gave, for "expected ..., got ...".
fn describeGiven(arena: std.mem.Allocator, loose: Loose) std.mem.Allocator.Error![]const u8 {
    return switch (loose.value) {
        .table => "a table",
        .list => "a list",
        .string, .text => "a string",
        .integer => "an integer",
        .float => "a number",
        .boolean => "a boolean",
        .null => "null",
        .handle => |handle| try arena.print("a {s}", .{handle.type.name}),
        .function => "a function",
    };
}

const testing = std.testing;

const test_package = struct {
    pub const Layout = struct { layout: []const u8, variant: ?[]const u8 = null };
    pub const Style = union(enum) { plain, size: u16 };

    pub const App = struct {
        size: u8 = 0,
        background: ?kosm.Color = null,
        layouts: []const Layout = &.{},
        style: Style = .plain,
        accent: kosm.ColorChoice = .{ .hue = .cyan },

        pub fn apply(self: App, output: *kosm.Output) !void {
            _ = .{ self, output };
        }

        pub fn grown(self: App, by: u8) App {
            var copy = self;
            copy.size += by;
            return copy;
        }

        pub fn grow(self: *App, by: u8) void {
            self.size += by;
        }
    };

    pub fn from(theme: kosm.Theme) App {
        return .{ .background = theme.roles.background };
    }

    pub const default: App = .{ .size = 3, .layouts = &.{.{ .layout = "us" }} };

    /// Shaped like the module kosm generates for a modifier written through a frontend.
    pub const Tint = struct {
        amount: f64 = 1,

        pub const script: kosm.Frontend.ScriptModifier = .{ .frontend = "test", .path = "colors/tint.lua" };

        pub fn apply(self: Tint, color: kosm.Color) kosm.Color {
            return script.apply(Tint, self, color);
        }
    };

    pub fn withAllocator(allocator: std.mem.Allocator) void {
        _ = allocator;
    }

    pub fn generic(comptime T: type) T {
        return undefined;
    }

    pub fn failing(what: []const u8) !App {
        return kosm.fail("no {s} today", .{what});
    }

    pub fn deadList(name: []const u8) App {
        var layouts = [_]Layout{.{ .layout = name }};
        return .{ .layouts = &layouts };
    }
};

const TestLibrary = Library(&.{.{ .name = "test_package", .module = test_package }}, &.{});

/// Calls the way a frontend does, failing the test with the call's message.
const Script = struct {
    arena: std.heap.ArenaAllocator,
    call: Call = undefined,

    fn init(script: *Script) void {
        script.* = .{ .arena = .init(testing.allocator) };
        script.call = TestLibrary.library(undefined).call(script.arena.allocator());
        script.call.state = null;
    }

    fn deinit(script: *Script) void {
        script.arena.deinit();
    }

    fn global(script: *Script, name: []const u8) !*const Namespace {
        _ = script;
        for (TestLibrary.globals) |namespace| {
            if (std.mem.eql(u8, namespace.name, name)) return namespace;
        }
        return error.TestMissingGlobal;
    }

    /// The entry at `path` below the global `path[0]`.
    fn entry(script: *Script, path: []const []const u8) !Namespace.Entry.Kind {
        var namespace = try script.global(path[0]);
        for (path[1..], 1..) |name, index| {
            const found = namespace.find(name) orelse return error.TestMissingEntry;
            if (index == path.len - 1) return found.kind;
            namespace = found.kind.namespace;
        }
        return error.TestMissingEntry;
    }

    fn callAt(script: *Script, path: []const []const u8, arguments: []const Loose) !Loose {
        const function = switch (try script.entry(path)) {
            .function, .constant => |function| function,
            .namespace => return error.TestNotAFunction,
        };
        return script.run(function, arguments);
    }

    fn run(script: *Script, function: Function, arguments: []const Loose) !Loose {
        script.call.message = null;
        return function.call(&script.call, arguments);
    }

    fn expectFailure(script: *Script, result: anytype, expected: []const u8) !void {
        try testing.expectError(error.CallFailed, result);
        try testing.expectEqualStrings(expected, script.call.message.?);
    }

    fn get(script: *Script, loose: Loose, key: Handle.Key) !Loose {
        const handle = loose.value.handle;
        return handle.type.get(&script.call, handle.pointer, key);
    }

    fn set(script: *Script, loose: Loose, key: Handle.Key, value: Loose.Kind) !void {
        const handle = loose.value.handle;
        return handle.type.set(&script.call, handle.pointer, key, .{ .value = value });
    }

    fn theme(script: *Script) !Loose {
        const palette: []const Loose.Entry = &.{ .{ .key = "black", .value = .{ .value = .{ .string = "#101010" } } }, .{ .key = "white", .value = .{ .value = .{ .string = "#f0f0f0" } } } };
        const input: []const Loose.Entry = &.{ .{ .key = "palette", .value = .{ .value = .{ .table = palette } } }, .{ .key = "mode", .value = .{ .value = .{ .string = "dark" } } } };
        return script.callAt(&.{ "kosm", "Theme", "from" }, &.{.{ .value = .{ .table = input } }});
    }
};

test "functions, values and types a script can use are bound; the rest are left out" {
    var script: Script = undefined;
    script.init();
    defer script.deinit();
    try testing.expectEqualStrings("kosm", TestLibrary.globals[0].name);
    try testing.expectEqualStrings("kosmoi", TestLibrary.globals[1].name);
    const package = try script.global("test_package");
    try testing.expect(package.find("from") != null);
    try testing.expect(package.find("default").?.kind == .constant);
    try testing.expect(package.find("withAllocator") == null);
    try testing.expect(package.find("generic") == null);
    const app = package.find("App").?.kind.namespace;
    try testing.expectEqualStrings("test_package.App", app.name);
    try testing.expect(app.find("grown") != null);
    try testing.expect(app.find("apply") == null);
    const tint = package.find("Tint").?.kind.namespace;
    try testing.expect(tint.find("script") == null);
    const app_type = TestLibrary.typeOf(test_package.App);
    try testing.expectEqualStrings("test_package.App", app_type.name);
    try testing.expect(app_type.method("grow") != null);
    try testing.expectEqualStrings("kosm.Theme.Input", TestLibrary.typeOf(kosm.Theme.Input).name);
}

test "a value built by calls is a handle whose fields read and set like the Zig value's" {
    var script: Script = undefined;
    script.init();
    defer script.deinit();
    const theme = try script.theme();
    try testing.expectEqualStrings("kosm.Theme", theme.value.handle.type.name);
    const app = try script.callAt(&.{ "test_package", "from" }, &.{theme});
    const background = try script.get(app, .{ .field = "background" });
    try testing.expectEqualStrings("kosm.Color", background.value.handle.type.name);
    try testing.expectEqualStrings("#101010", background.value.handle.as(kosm.Color).?.hex().slice());

    try script.set(app, .{ .field = "size" }, .{ .integer = 7 });
    try testing.expectEqual(7, (try script.get(app, .{ .field = "size" })).value.integer);
    try script.set(app, .{ .field = "background" }, .{ .string = "#ff0000" });
    try testing.expectEqualStrings("#ff0000", app.value.handle.as(test_package.App).?.background.?.hex().slice());
    try script.expectFailure(script.set(app, .{ .field = "size" }, .{ .string = "big" }), "size: expected an integer that fits u8, got the string 'big'");
    try script.expectFailure(script.get(app, .{ .field = "sise" }), "test_package.App has no field 'sise'; did you mean 'size'?");
    try script.expectFailure(script.get(app, .{ .field = "opacity" }), "test_package.App has no field 'opacity'; its fields are size, background, layouts, style, accent");
    try testing.expectEqualStrings("plain", (try script.get(app, .{ .field = "style" })).value.handle.type.fields[0]);
    try testing.expectEqual(true, (try script.get(try script.get(app, .{ .field = "style" }), .{ .field = "plain" })).value.boolean);
    try testing.expectEqual(.null, std.meta.activeTag((try script.get(try script.get(app, .{ .field = "style" }), .{ .field = "size" })).value));
}

test "one field of a color, or a color choice's tag, is set like any struct's" {
    var script: Script = undefined;
    script.init();
    defer script.deinit();
    const app = try script.callAt(&.{ "test_package", "from" }, &.{try script.theme()});
    const background = try script.get(app, .{ .field = "background" });
    try script.set(background, .{ .field = "lightness" }, .{ .float = 0.5 });
    try script.set(background, .{ .field = "alpha" }, .{ .integer = 1 });
    try testing.expectEqual(0.5, background.value.handle.as(kosm.Color).?.lightness);
    try script.expectFailure(script.set(background, .{ .field = "lightness" }, .{ .string = "dark" }), "lightness: expected a number, got the string 'dark'");
    try script.expectFailure(script.set(background, .{ .field = "brightness" }, .{ .float = 1 }), "kosm.Color has no field 'brightness'; did you mean 'lightness'?");
    try script.expectFailure(script.set(background, .{ .field = "red" }, .{ .float = 1 }), "kosm.Color has no field 'red'; its fields are lightness, chroma, hue, alpha");

    const accent = try script.get(app, .{ .field = "accent" });
    try script.set(accent, .{ .field = "hue" }, .{ .string = "sky" });
    try testing.expectEqual(kosm.Palette.Hue.sky, app.value.handle.as(test_package.App).?.accent.hue);
    try script.set(accent, .{ .field = "color" }, .{ .string = "#ff0000" });
    try testing.expectEqualStrings("#ff0000", app.value.handle.as(test_package.App).?.accent.color.hex().slice());
    try script.expectFailure(script.set(accent, .{ .field = "shade" }, .{ .string = "sky" }), "kosm.ColorChoice has no tag 'shade'; its tags are color, hue");
    try script.expectFailure(script.set(accent, .{ .field = "hu" }, .{ .string = "sky" }), "kosm.ColorChoice has no tag 'hu'; did you mean 'hue'?");
}

test "methods take the handle first; one taking a pointer changes the script's value" {
    var script: Script = undefined;
    script.init();
    defer script.deinit();
    const app = try script.callAt(&.{ "test_package", "default" }, &.{});
    const app_type = app.value.handle.type;
    const grown = try script.run(app_type.method("grown").?, &.{ app, .{ .value = .{ .integer = 2 } } });
    try testing.expectEqual(5, grown.value.handle.as(test_package.App).?.size);
    try testing.expectEqual(3, app.value.handle.as(test_package.App).?.size);
    _ = try script.run(app_type.method("grow").?, &.{ app, .{ .value = .{ .integer = 1 } } });
    try testing.expectEqual(4, app.value.handle.as(test_package.App).?.size);
    try script.expectFailure(script.run(app_type.method("grow").?, &.{ .{ .value = .{ .integer = 1 } }, .{ .value = .{ .integer = 1 } } }), "test_package.App.grow: argument 1: expected a test_package.App, got an integer");
    try script.expectFailure(script.run(app_type.method("grow").?, &.{app}), "test_package.App.grow takes 2 arguments, got 1");
}

test "a declared value is a fresh copy each time, whose lists change apart from the declaration" {
    var script: Script = undefined;
    script.init();
    defer script.deinit();
    const first = try script.callAt(&.{ "test_package", "default" }, &.{});
    const layouts = try script.get(first, .{ .field = "layouts" });
    try testing.expectEqual(1, layouts.value.handle.type.length(layouts.value.handle.pointer));
    try script.set(try script.get(layouts, .{ .item = 0 }), .{ .field = "layout" }, .{ .string = "rs" });
    try testing.expectEqualStrings("rs", first.value.handle.as(test_package.App).?.layouts[0].layout);
    const second = try script.callAt(&.{ "test_package", "default" }, &.{});
    try testing.expectEqualStrings("us", second.value.handle.as(test_package.App).?.layouts[0].layout);
    try testing.expectEqualStrings("us", test_package.default.layouts[0].layout);
    try script.expectFailure(script.get(layouts, .{ .item = 1 }), "item 2 is past the end of a list of 1");
    try script.set(layouts, .{ .item = 0 }, .{ .table = &.{.{ .key = "layout", .value = .{ .value = .{ .string = "de" } } }} });
    try testing.expectEqualStrings("de", first.value.handle.as(test_package.App).?.layouts[0].layout);
}

test "a handle given as an argument or a field's value is copied" {
    var script: Script = undefined;
    script.init();
    defer script.deinit();
    const app = try script.callAt(&.{ "test_package", "default" }, &.{});
    const other = try script.callAt(&.{ "test_package", "from" }, &.{try script.theme()});
    try script.set(app, .{ .field = "background" }, .{ .handle = (try script.get(other, .{ .field = "background" })).value.handle });
    try script.set(other, .{ .field = "background" }, .{ .string = "#00ff00" });
    try testing.expectEqualStrings("#101010", app.value.handle.as(test_package.App).?.background.?.hex().slice());
}

test "a failing function, or one returning a list from its own stack, fails with its message" {
    var script: Script = undefined;
    script.init();
    defer script.deinit();
    try script.expectFailure(script.callAt(&.{ "test_package", "failing" }, &.{.{ .value = .{ .string = "luck" } }}), "test_package.failing: no luck today");
    try script.expectFailure(script.callAt(&.{ "test_package", "deadList" }, &.{.{ .value = .{ .string = "us" } }}), "test_package.deadList: what it returns at layouts points into a function that has returned, so it is garbage; it must keep run-time lists with kosm.keep");
    try script.expectFailure(script.callAt(&.{ "kosm", "Theme", "from" }, &.{.{ .value = .{ .integer = 1 } }}), "kosm.Theme.from: argument 1: expected a table of its fields (palette, mode, roles, code, diff, traits), got the integer 1");
}

test "completion describes the namespaces, their functions and values, and records' methods" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var sources: @import("Sources.zig") = .{ .arena = arena, .io = testing.io, .modules = &.{} };
    var builder: completion_types.Builder = .{ .arena = arena, .sources = &sources };
    const namespaces = try TestLibrary.describe(&builder);
    const package = for (namespaces) |namespace| {
        if (std.mem.eql(u8, namespace.name, "test_package")) break namespace;
    } else return error.TestMissingNamespace;
    const from = for (package.functions) |function| {
        if (std.mem.eql(u8, function.name, "from")) break function;
    } else return error.TestMissingFunction;
    try testing.expectEqualStrings("argument1", from.parameters[0].name);
    try testing.expectEqualStrings("test_package.App", from.result.?.record);
    try testing.expectEqualStrings("test_package.App", package.values[0].type.?.namespace);
    const completion: kosm.Frontend.Completion = .{ .records = builder.records.items, .kosmoi = &.{}, .standalone = "", .theme = "" };
    const app = completion.find("test_package.App").?;
    try testing.expectEqual(2, app.methods.len);
    try testing.expectEqualStrings("grown", app.methods[0].name);
    // Named by its declaration though a function declared before it takes one.
    const output = completion.find("kosm.Output").?;
    try testing.expect(for (output.methods) |method| {
        if (std.mem.eql(u8, method.name, "generateValue")) break true;
    } else false);
}
