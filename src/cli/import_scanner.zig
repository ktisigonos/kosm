//! Finds the names a Zig file imports, for the walk that finds which local packages a
//! kosmos reaches. Shared by the command line and the config project's build, so both walk the same way.

const std = @import("std");

/// Appends the text of every `@import("...")` in `source`, allocated in `arena`. A literal that
/// does not parse is skipped: the compiler reports it.
pub fn appendImports(arena: std.mem.Allocator, source: [:0]const u8, imports: *std.ArrayList([]const u8)) std.mem.Allocator.Error!void {
    var tokenizer: std.zig.Tokenizer = .init(source);
    var previous: [2]std.zig.Token = undefined;
    var count: usize = 0;
    while (true) : (count += 1) {
        const token = tokenizer.next();
        if (token.tag == .eof) return;
        defer previous = .{ previous[1], token };
        if (count < 2 or token.tag != .string_literal or previous[1].tag != .l_paren or previous[0].tag != .builtin) continue;
        if (!std.mem.eql(u8, source[previous[0].loc.start..previous[0].loc.end], "@import")) continue;
        const text = std.zig.string_literal.parseAlloc(arena, source[token.loc.start..token.loc.end]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        try imports.append(arena, text);
    }
}
