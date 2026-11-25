//! The commands kosm takes, with their arguments and flags: the usage `kosm help` prints, the
//! help of one command, what the shell completes, and the closest commands to a misspelled one.

const std = @import("std");
const suggestion = @import("kosm_suggestion");

/// A flag a command takes.
pub const Flag = struct {
    name: []const u8,
    /// What follows it (`dir`), or empty when nothing does.
    value: []const u8 = "",
    meaning: []const u8,
};

/// A command kosm takes.
pub const Command = struct {
    name: []const u8,
    /// What follows the name in the usage.
    arguments: []const u8,
    summary: []const u8,
    flags: []const Flag = &.{},
    /// Lines printed after the flags in the command's help.
    notes: []const []const u8 = &.{},
};

pub const config_flag: Flag = .{ .name = "--config", .value = "dir", .meaning = "the config project's directory" };
pub const language_flag: Flag = .{ .name = "--language", .value = "<frontend>", .meaning = "the frontend to write it in; Zig without it" };
pub const default_flag: Flag = .{ .name = "--default", .meaning = "use the installed sources again" };
pub const list_flags = [_]Flag{
    .{ .name = "--kosmoi", .meaning = "list only kosmoi" },
    .{ .name = "--apps", .meaning = "list only apps" },
    .{ .name = "--adapters", .meaning = "list only adapters" },
    .{ .name = "--frontends", .meaning = "list only frontends" },
    .{ .name = "--packages", .meaning = "list only packages" },
};
pub const apply_flags = [_]Flag{
    .{ .name = "--diff", .meaning = "print what would change and write nothing" },
    .{ .name = "--reload", .meaning = "reload every app, also those whose files did not change" },
    .{ .name = "--set", .value = "path=value", .meaning = "set one value of the kosmos" },
    config_flag,
};
const colors_flags = [_]Flag{ apply_flags[2], config_flag };
pub const build_flags = [_]Flag{
    .{ .name = "--except", .meaning = "build every kosmos but the ones named after it" },
    .{ .name = "--all", .meaning = "build every kosmos in kosmoi/, whatever kosm.zon says" },
};
const parameters_note = "A kosmos takes the parameters it declares as --<param> value.";

/// Every command, in the order the usage lists them.
pub const commands = [_]Command{
    .{ .name = "init", .arguments = "[--config dir]", .summary = "create what a config project is missing", .flags = &.{config_flag} },
    .{ .name = "new", .arguments = "kosmos|app|adapter|frontend|modifier|style|family|package <name> [--language <frontend>] [--config dir]", .summary = "scaffold a kosmos, app, adapter, frontend, color script or package", .flags = &.{ language_flag, config_flag } },
    .{ .name = "apply", .arguments = "<kosmos>[.<group>]...[.<variant>] [--<param> value]... [--set path=value]... [--diff] [--reload] [--config dir]", .summary = "apply a kosmos", .flags = &apply_flags, .notes = &.{parameters_note} },
    .{ .name = "list", .arguments = "[<kosmos> | --kosmoi | --apps | --adapters | --frontends | --packages ...] [--config dir]", .summary = "list kosmoi and packages", .flags = &(list_flags ++ [_]Flag{config_flag}) },
    .{ .name = "colors", .arguments = "<kosmos>[.<group>]...[.<variant>] [--<param> value]... [--set path=value]... [--config dir]", .summary = "show the colors a kosmos wears", .flags = &colors_flags, .notes = &.{parameters_note} },
    .{ .name = "current", .arguments = "", .summary = "print the last apply as a command" },
    .{ .name = "source", .arguments = "[<dir> | --default]", .summary = "choose the kosm sources builds use", .flags = &.{default_flag} },
    .{ .name = "add", .arguments = "<url>[#ref] [--config dir]", .summary = "install a package from a url", .flags = &.{config_flag} },
    .{ .name = "remove", .arguments = "<name> [--config dir]", .summary = "remove a package", .flags = &.{config_flag} },
    .{ .name = "update", .arguments = "[name] [--config dir]", .summary = "fetch packages again", .flags = &.{config_flag} },
    .{ .name = "clean", .arguments = "[--config dir]", .summary = "delete caches and unused package versions", .flags = &.{config_flag} },
    .{ .name = "build", .arguments = "[<kosmos>... | --except <kosmos>... | --all] [--config dir]", .summary = "compile every kosmos, so applies start at once", .flags = &(build_flags ++ [_]Flag{config_flag}) },
    .{ .name = "completions", .arguments = "fish|bash|zsh", .summary = "print a shell's completion script" },
    .{ .name = "relay", .arguments = "<file>", .summary = "forward a file to a browser extension" },
    .{ .name = "help", .arguments = "[<command>]", .summary = "show how to use kosm or one command" },
};

/// The command named `name`, or null when kosm has none.
pub fn find(name: []const u8) ?*const Command {
    for (&commands) |*command| {
        if (std.mem.eql(u8, command.name, name)) return command;
    }
    return null;
}

/// Every command's usage line, then `kosm --version`.
pub fn writeUsage(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (commands, 0..) |command, index| {
        try writer.writeAll(if (index == 0) "usage: " else "       ");
        try writeUsageLine(writer, command);
    }
    try writer.writeAll("       kosm --version\n");
}

/// `kosm help`: the usage, and how to read one command's.
pub fn writeOverview(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writeUsage(writer);
    try writer.writeAll("\nkosm help <command> shows what one command does and the flags it takes.\n");
}

/// `kosm help <command>`: its usage, what it does, its flags and notes.
pub fn writeCommand(writer: *std.Io.Writer, command: Command) std.Io.Writer.Error!void {
    try writer.writeAll("usage: ");
    try writeUsageLine(writer, command);
    try writer.print("\n{s}\n", .{command.summary});
    if (command.flags.len != 0) {
        var width: usize = 0;
        for (command.flags) |flag| width = @max(width, flagWidth(flag));
        try writer.writeAll("\n");
        for (command.flags) |flag| {
            try writer.print("  {s}", .{flag.name});
            if (flag.value.len != 0) try writer.print(" {s}", .{flag.value});
            try writer.splatByteAll(' ', width - flagWidth(flag) + 2);
            try writer.print("{s}\n", .{flag.meaning});
        }
    }
    if (command.notes.len != 0) try writer.writeAll("\n");
    for (command.notes) |note| try writer.print("{s}\n", .{note});
}

/// `unknown command 'updae'; did you mean 'update'?`, or the way to the usage when no command
/// is close; one line, without a leading `error: `.
pub fn writeUnknown(writer: *std.Io.Writer, name: []const u8) std.Io.Writer.Error!void {
    var names: [commands.len][]const u8 = undefined;
    for (commands, &names) |command, *slot| slot.* = command.name;
    try writer.print("unknown command '{s}'; {f}\n", .{ name, suggestion.hint(name, &names, "kosm help lists the commands") });
}

fn writeUsageLine(writer: *std.Io.Writer, command: Command) std.Io.Writer.Error!void {
    try writer.print("kosm {s}", .{command.name});
    if (command.arguments.len != 0) try writer.print(" {s}", .{command.arguments});
    try writer.writeAll("\n");
}

fn flagWidth(flag: Flag) usize {
    return flag.name.len + if (flag.value.len == 0) 0 else flag.value.len + 1;
}

const testing = std.testing;

fn testUnknown(name: []const u8) ![]u8 {
    var written: std.Io.Writer.Allocating = .init(testing.allocator);
    defer written.deinit();
    try writeUnknown(&written.writer, name);
    return written.toOwnedSlice();
}

test "a misspelled command suggests the closest ones" {
    const update = try testUnknown("updae");
    defer testing.allocator.free(update);
    try testing.expectEqualStrings("unknown command 'updae'; did you mean 'update'?\n", update);
    const apply = try testUnknown("appy");
    defer testing.allocator.free(apply);
    try testing.expectEqualStrings("unknown command 'appy'; did you mean 'apply'?\n", apply);
}

test "a command close to none names kosm help" {
    const far = try testUnknown("frobnicate");
    defer testing.allocator.free(far);
    try testing.expectEqualStrings("unknown command 'frobnicate'; kosm help lists the commands\n", far);
    const flag = try testUnknown("-x");
    defer testing.allocator.free(flag);
    try testing.expectEqualStrings("unknown command '-x'; kosm help lists the commands\n", flag);
}

test "a command's help lines its flags up after its usage and summary" {
    var written: std.Io.Writer.Allocating = .init(testing.allocator);
    defer written.deinit();
    try writeCommand(&written.writer, find("colors").?.*);
    try testing.expectEqualStrings(
        \\usage: kosm colors <kosmos>[.<group>]...[.<variant>] [--<param> value]... [--set path=value]... [--config dir]
        \\
        \\show the colors a kosmos wears
        \\
        \\  --set path=value  set one value of the kosmos
        \\  --config dir      the config project's directory
        \\
        \\A kosmos takes the parameters it declares as --<param> value.
        \\
    , written.written());
}

test "a command without flags shows its usage and summary alone" {
    var written: std.Io.Writer.Allocating = .init(testing.allocator);
    defer written.deinit();
    try writeCommand(&written.writer, find("current").?.*);
    try testing.expectEqualStrings("usage: kosm current\n\nprint the last apply as a command\n", written.written());
}

test "the usage lists every command, then --version" {
    var written: std.Io.Writer.Allocating = .init(testing.allocator);
    defer written.deinit();
    try writeUsage(&written.writer);
    try testing.expectStringStartsWith(written.written(), "usage: kosm init [--config dir]\n       kosm new ");
    try testing.expectStringEndsWith(written.written(), "       kosm help [<command>]\n       kosm --version\n");
}
