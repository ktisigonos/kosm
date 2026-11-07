//! Turns a tree-sitter syntax tree into the `Adapter.Node` tree kosm matches paths against,
//! following a `Spec`. Lives only while one file is parsed.

const Builder = @This();

const std = @import("std");
const c = @import("tree_sitter_api");
const Adapter = @import("../Adapter.zig");
const Spec = @import("Spec.zig");
const Node = Adapter.Node;

allocator: std.mem.Allocator,
spec: Spec,
source: []const u8,
context: *Adapter.Context,

/// Deeper nesting is refused rather than risking the stack.
const max_depth = 256;

/// Parses `source` with `language`: its one table or list, or else a table of its top-level keys.
/// Nodes point into `source`.
pub fn parse(allocator: std.mem.Allocator, language: *const c.TSLanguage, spec: Spec, source: []const u8, context: *Adapter.Context) Adapter.ParseError!Node {
    if (source.len > std.math.maxInt(u32)) return context.invalidSyntax("the file is larger than tree-sitter reads (4 GiB)", .{});
    const ts_parser = c.ts_parser_new() orelse return error.OutOfMemory;
    defer c.ts_parser_delete(ts_parser);
    if (!c.ts_parser_set_language(ts_parser, language))
        return context.invalidSyntax("the adapter's grammar was generated for another tree-sitter version", .{});
    const tree = c.ts_parser_parse_string(ts_parser, null, source.ptr, @intCast(source.len)) orelse return error.OutOfMemory;
    defer c.ts_tree_delete(tree);

    const root = c.ts_tree_root_node(tree);
    if (c.ts_node_has_error(root)) {
        const point = c.ts_node_start_point(firstError(root));
        return context.invalidSyntax("line {d}, column {d}: syntax error; kosm edits only files that parse", .{ point.row + 1, point.column + 1 });
    }
    var builder: Builder = .{ .allocator = allocator, .spec = spec, .source = source, .context = context };
    if (builder.soleValue(root)) |value| return builder.valueNode(value, 0);
    return .{ .key = null, .kind = .table, .position = 0, .value = .{ .start = 0, .end = source.len }, .children = try builder.tableEntries(root, 0) };
}

/// The table or list that is a file's whole content (a JSON object or array), if any.
fn soleValue(builder: *const Builder, root: c.TSNode) ?c.TSNode {
    var found: ?c.TSNode = null;
    var cursor = c.ts_tree_cursor_new(root);
    defer c.ts_tree_cursor_delete(&cursor);
    if (!c.ts_tree_cursor_goto_first_child(&cursor)) return null;
    while (true) {
        const child = c.ts_tree_cursor_current_node(&cursor);
        if (isEntry(child)) {
            if (found != null) return null;
            found = child;
        }
        if (!c.ts_tree_cursor_goto_next_sibling(&cursor)) break;
    }
    const value = found orelse return null;
    const kind = nodeType(value);
    if (contains(builder.spec.nest, kind) or contains(builder.spec.list, kind)) return value;
    return null;
}

/// The deepest node starting the first error, so the reported position is the real one.
fn firstError(node: c.TSNode) c.TSNode {
    if (c.ts_node_is_error(node) or c.ts_node_is_missing(node)) return node;
    var cursor = c.ts_tree_cursor_new(node);
    defer c.ts_tree_cursor_delete(&cursor);
    if (!c.ts_tree_cursor_goto_first_child(&cursor)) return node;
    while (true) {
        const child = c.ts_tree_cursor_current_node(&cursor);
        if (c.ts_node_has_error(child) or c.ts_node_is_missing(child)) return firstError(child);
        if (!c.ts_tree_cursor_goto_next_sibling(&cursor)) return node;
    }
}

/// The pairs inside `container`, including those of a keyless nested table (a file's top object).
fn tableEntries(builder: *Builder, container: c.TSNode, depth: usize) Adapter.ParseError![]const Node {
    var entries: std.ArrayList(Node) = .empty;
    var cursor = c.ts_tree_cursor_new(container);
    defer c.ts_tree_cursor_delete(&cursor);
    if (!c.ts_tree_cursor_goto_first_child(&cursor)) return &.{};
    while (true) {
        const child = c.ts_tree_cursor_current_node(&cursor);
        if (isEntry(child)) try builder.appendEntries(&entries, child, depth);
        if (!c.ts_tree_cursor_goto_next_sibling(&cursor)) break;
    }
    return entries.items;
}

/// The keys `child` adds to the table holding it: a pair, assignments, or the entries of a
/// keyless nested table or a transparent node.
fn appendEntries(builder: *Builder, entries: *std.ArrayList(Node), child: c.TSNode, depth: usize) Adapter.ParseError!void {
    const kind = nodeType(child);
    if (std.mem.eql(u8, kind, builder.spec.pair)) {
        if (try builder.pairNode(child, depth)) |node| try entries.append(builder.allocator, node);
        return;
    }
    if (builder.spec.assign) |assign| {
        if (std.mem.eql(u8, kind, assign.node)) return builder.appendAssignments(entries, child, assign, depth);
    }
    if (contains(builder.spec.nest, kind) or contains(builder.spec.transparent, kind))
        try entries.appendSlice(builder.allocator, try builder.tableEntries(child, try builder.deeper(child, depth)));
}

/// One entry per target of `statement` whose keys are known, paired with values by position.
fn appendAssignments(builder: *Builder, entries: *std.ArrayList(Node), statement: c.TSNode, assign: Spec.Assign, depth: usize) Adapter.ParseError!void {
    const target_list = childOfType(statement, assign.targets) orelse return;
    const value_list = childOfType(statement, assign.values) orelse return;
    const targets = try builder.fieldChildren(target_list, assign.target);
    const values = try builder.fieldChildren(value_list, assign.value);
    const count = @min(targets.len, values.len);
    for (targets[0..count], values[0..count]) |target, value| {
        if (try builder.assignedNode(target, value, assign, depth)) |node| try entries.append(builder.allocator, node);
    }
}

/// `value` under the keys `target` spells, so `M.blur.enabled = true` is the table `M` holding
/// the table `blur` holding `enabled`. The outer tables have no bytes of their own.
fn assignedNode(builder: *Builder, target: c.TSNode, value: c.TSNode, assign: Spec.Assign, depth: usize) Adapter.ParseError!?Node {
    var keys: std.ArrayList([]const u8) = .empty;
    var current = target;
    while (!std.mem.eql(u8, nodeType(current), assign.name)) {
        if (!std.mem.eql(u8, nodeType(current), assign.index.node)) return null;
        const key = fieldNode(current, assign.index.key) orelse return null;
        try keys.append(builder.allocator, builder.keyText(key));
        current = fieldNode(current, assign.index.table) orelse return null;
    }
    try keys.append(builder.allocator, builder.keyText(current));

    var inner_depth = depth;
    for (keys.items[1..]) |_| inner_depth = try builder.deeper(target, inner_depth);
    const position = c.ts_node_start_byte(target);
    var node = try builder.valueNode(value, inner_depth);
    node.key = keys.items[0];
    node.position = position;
    for (keys.items[1..]) |key| {
        // A literal assigned to `node` would write its fields before `dupe` reads `node`.
        const children = try builder.allocator.dupe(Node, &.{node});
        node = .{ .key = key, .kind = .table, .position = position, .value = null, .children = children };
    }
    return node;
}

fn pairNode(builder: *Builder, pair: c.TSNode, depth: usize) Adapter.ParseError!?Node {
    const key = fieldNode(pair, builder.spec.key) orelse return null;
    const value = fieldNode(pair, builder.spec.value) orelse return null;
    var node = try builder.valueNode(value, depth);
    node.key = builder.keyText(key);
    node.position = c.ts_node_start_byte(pair);
    return node;
}

fn valueNode(builder: *Builder, value: c.TSNode, depth: usize) Adapter.ParseError!Node {
    const kind = nodeType(value);
    const range: Adapter.Range = .{ .start = c.ts_node_start_byte(value), .end = c.ts_node_end_byte(value) };
    var node: Node = .{ .key = null, .kind = .scalar, .position = range.start, .value = range };
    if (contains(builder.spec.nest, kind) and contains(builder.spec.list, kind)) {
        node.children = try builder.mixedEntries(value, try builder.deeper(value, depth));
        node.kind = if (allKeyless(node.children)) .list else .table;
    } else if (contains(builder.spec.nest, kind)) {
        node.kind = .table;
        node.children = try builder.tableEntries(value, try builder.deeper(value, depth));
    } else if (contains(builder.spec.list, kind)) {
        node.kind = .list;
        node.children = try builder.listElements(value, try builder.deeper(value, depth));
    }
    return node;
}

/// The entries of a node that is both a table and a list (D90), in file order: pairs with a key,
/// and the values of pairs without one as keyless elements.
fn mixedEntries(builder: *Builder, container: c.TSNode, depth: usize) Adapter.ParseError![]const Node {
    var entries: std.ArrayList(Node) = .empty;
    var cursor = c.ts_tree_cursor_new(container);
    defer c.ts_tree_cursor_delete(&cursor);
    if (!c.ts_tree_cursor_goto_first_child(&cursor)) return &.{};
    while (true) {
        const child = c.ts_tree_cursor_current_node(&cursor);
        if (isEntry(child)) {
            if (std.mem.eql(u8, nodeType(child), builder.spec.pair) and fieldNode(child, builder.spec.key) == null) {
                if (fieldNode(child, builder.spec.value)) |value| {
                    var element = try builder.valueNode(value, depth);
                    element.position = c.ts_node_start_byte(child);
                    try entries.append(builder.allocator, element);
                }
            } else {
                try builder.appendEntries(&entries, child, depth);
            }
        }
        if (!c.ts_tree_cursor_goto_next_sibling(&cursor)) break;
    }
    return entries.items;
}

fn allKeyless(entries: []const Node) bool {
    for (entries) |entry| {
        if (entry.key != null) return false;
    }
    return true;
}

fn listElements(builder: *Builder, list: c.TSNode, depth: usize) Adapter.ParseError![]const Node {
    var elements: std.ArrayList(Node) = .empty;
    var cursor = c.ts_tree_cursor_new(list);
    defer c.ts_tree_cursor_delete(&cursor);
    if (!c.ts_tree_cursor_goto_first_child(&cursor)) return &.{};
    while (true) {
        const child = c.ts_tree_cursor_current_node(&cursor);
        if (isEntry(child)) try elements.append(builder.allocator, try builder.valueNode(child, depth));
        if (!c.ts_tree_cursor_goto_next_sibling(&cursor)) break;
    }
    return elements.items;
}

fn keyText(builder: *const Builder, key: c.TSNode) []const u8 {
    const text = builder.source[c.ts_node_start_byte(key)..c.ts_node_end_byte(key)];
    if (contains(builder.spec.quoted_key, nodeType(key)) and text.len >= 2) return text[1 .. text.len - 1];
    return text;
}

fn deeper(builder: *Builder, node: c.TSNode, depth: usize) Adapter.ParseError!usize {
    if (depth == max_depth) {
        const point = c.ts_node_start_point(node);
        return builder.context.invalidSyntax("line {d}: values nest deeper than {d} levels", .{ point.row + 1, max_depth });
    }
    return depth + 1;
}

/// Named nodes that are not comments or other extras.
fn isEntry(node: c.TSNode) bool {
    return c.ts_node_is_named(node) and !c.ts_node_is_extra(node);
}

fn nodeType(node: c.TSNode) []const u8 {
    return std.mem.span(c.ts_node_type(node));
}

fn fieldNode(node: c.TSNode, field: []const u8) ?c.TSNode {
    const child = c.ts_node_child_by_field_name(node, field.ptr, @intCast(field.len));
    if (c.ts_node_is_null(child)) return null;
    return child;
}

/// The first named child of `node` with type `kind`.
fn childOfType(node: c.TSNode, kind: []const u8) ?c.TSNode {
    var cursor = c.ts_tree_cursor_new(node);
    defer c.ts_tree_cursor_delete(&cursor);
    if (!c.ts_tree_cursor_goto_first_child(&cursor)) return null;
    while (true) {
        const child = c.ts_tree_cursor_current_node(&cursor);
        if (c.ts_node_is_named(child) and std.mem.eql(u8, nodeType(child), kind)) return child;
        if (!c.ts_tree_cursor_goto_next_sibling(&cursor)) return null;
    }
}

/// Every child of `node` in `field`, in file order.
fn fieldChildren(builder: *Builder, node: c.TSNode, field: []const u8) Adapter.ParseError![]const c.TSNode {
    var found: std.ArrayList(c.TSNode) = .empty;
    var cursor = c.ts_tree_cursor_new(node);
    defer c.ts_tree_cursor_delete(&cursor);
    if (!c.ts_tree_cursor_goto_first_child(&cursor)) return &.{};
    while (true) {
        const name = c.ts_tree_cursor_current_field_name(&cursor);
        if (name != null and std.mem.eql(u8, std.mem.span(name), field))
            try found.append(builder.allocator, c.ts_tree_cursor_current_node(&cursor));
        if (!c.ts_tree_cursor_goto_next_sibling(&cursor)) break;
    }
    return found.items;
}

fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}
