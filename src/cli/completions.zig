//! `kosm completions <shell>`: prints the shell's completion script. Each script only asks
//! `kosm complete` what to offer, so what completes lives in one place.

const std = @import("std");

/// The shells kosm completes in.
pub const Shell = enum {
    fish,
    bash,
    zsh,

    /// The script the shell loads; its header says where to install it.
    pub fn script(shell: Shell) []const u8 {
        return switch (shell) {
            .fish => @embedFile("completions/kosm.fish"),
            .bash => @embedFile("completions/kosm.bash"),
            .zsh => @embedFile("completions/kosm.zsh"),
        };
    }
};

test "every shell's script asks kosm complete for the words typed so far" {
    inline for (comptime std.enums.values(Shell)) |shell| {
        const script = shell.script();
        try std.testing.expect(std.mem.find(u8, script, "kosm complete -- ") != null);
        try std.testing.expect(std.mem.find(u8, script, "kosm completions " ++ @tagName(shell)) != null);
        try std.testing.expect(std.mem.find(u8, script, "--config") != null);
    }
}
