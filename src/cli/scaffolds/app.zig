//! The scaffold_name app, made by `kosm new app scaffold_name`. A kosmos uses it with
//! `const scaffold_name = @import("scaffold_name");` and a field
//! `scaffold_name: scaffold_name.App` set to `scaffold_name.from(theme)`.

const kosm = @import("kosm");

/// Every setting of the program, as plain fields a kosmos can assign. `from` fills those that
/// come from the theme; the rest have defaults.
pub const App = struct {
    /// The file kosm writes. Default: `~/.config/scaffold_name/colors.conf`.
    file: []const u8 = "~/.config/scaffold_name/colors.conf",
    /// How values are spelled, e.g. `.color = .hex_upper`. Default: kosm's own.
    format: kosm.Format = .{},
    /// Text. Default: white, black in light mode.
    foreground: kosm.Color,
    /// Background. Default: black, white in light mode.
    background: kosm.Color,
    /// The accent. Default: cyan.
    accent: kosm.Color,

    /// Writes the file. An app never reads or writes files itself, it only calls `output`;
    /// kosm writes everything at the end, all or nothing.
    pub fn apply(self: App, output: *kosm.Output) !void {
        try output.template(self, .{ .file = self.file, .text = template, .format = self.format });
    }

    // To reload the program after an apply, add:
    // pub fn reload(self: App, reloader: *kosm.Reloader) !void {
    //     try reloader.run(&.{ "pkill", "-USR1", "-x", "scaffold_name" });
    // }
};

/// `kosm.<field>` is replaced by that field of `App`. A longer template belongs in
/// `templates/`, read with `@embedFile("templates/colors.conf")`.
const template =
    \\foreground = kosm.foreground
    \\background = kosm.background
    \\accent = kosm.accent
    \\
;

/// The app's defaults, derived from the theme.
pub fn from(theme: kosm.Theme) App {
    const palette = theme.palette;
    return .{
        .foreground = if (theme.mode == .dark) palette.white else palette.black,
        .background = if (theme.mode == .dark) palette.black else palette.white,
        .accent = palette.cyan,
    };
}
