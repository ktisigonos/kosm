//! kitty's "Advanced" options. Field names are kitty's option names (D27).

const values = @import("../values.zig");

/// The shell program to execute. null: kitty's default, `.`.
shell: ?[]const u8 = null,
/// The terminal based text editor (such as `vim` or `nano`) to use when editing the kitty config file or similar tasks. null: kitty's default, `.`.
editor: ?[]const u8 = null,
/// Close the window when the child process (usually the shell) exits. null: kitty's default, `no`.
close_on_child_death: ?bool = null,
/// Allow other programs to control kitty using passwords. Each item is written as its own line.
remote_control_password: []const values.RemoteControlPassword = &.{},
/// Allow other programs to control kitty. null: kitty's default, `no`.
allow_remote_control: ?enum { password, socket_only, socket, no, yes } = null,
/// Listen to the specified socket for remote control connections. null: kitty's default, `none`.
listen_on: ?[]const u8 = null,
/// Specify the environment variables to be set in all child processes. Each item is written as its own line.
env: []const values.Env = &.{},
/// Space separated list of custom shader pipeline names. null: kitty's default.
custom_shaders: ?[]const []const u8 = null,
/// Specify rules to filter out notifications sent by applications running in kitty. Each item is written as its own line.
filter_notification: []const []const u8 = &.{},
/// Path to python file which will be loaded for `watchers`. Each item is written as its own line.
watcher: []const []const u8 = &.{},
/// Control where kitty finds the programs to run. Each item is written as its own line.
exe_search_path: []const []const u8 = &.{},
/// The interval to periodically check if an update to kitty is available (in hours). null: kitty's default, `24`.
update_check_interval: ?f64 = null,
/// Automatically reload configuration files when they are changed. null: kitty's default, `0.1`.
auto_reload_config: ?f64 = null,
/// Path to a session file to use for all kitty instances. null: kitty's default, `none`.
startup_session: ?[]const u8 = null,
/// Save kitty's windows as a session on logout and restore them on the next start. null: kitty's default, `no`.
restore_session_after_logout: ?bool = null,
/// Allow programs running in kitty to read and write from the clipboard. null: kitty's default.
clipboard_control: ?values.ClipboardControl = null,
/// The maximum size (in MB) of data from programs running in kitty that will be stored for writing to the system clipboard. null: kitty's default, `512`.
clipboard_max_size: ?f64 = null,
/// The password that can be supplied to the `file transfer kitten` to skip the transfer confirmation prompt. null: kitty's default.
file_transfer_confirmation_bypass: ?[]const u8 = null,
/// Process `hyperlink` escape sequences (OSC 8). null: kitty's default, `yes`.
allow_hyperlinks: ?enum { yes, no, ask } = null,
/// Enable shell integration on supported shells. null: kitty's default, `enabled`.
shell_integration: ?values.ShellIntegration = null,
/// Control whether programs running in the terminal can request new windows to be created. null: kitty's default, `ask`.
allow_cloning: ?enum { yes, no, ask } = null,
/// Control what shell code is sourced when running `clone-in-kitty` in the newly cloned window. null: kitty's default, `venv,conda,env_var,path`.
clone_source_strategies: ?values.CloneSourceStrategies = null,
/// Show a desktop notification when a long-running command finishes (needs `shell_integration`). null: kitty's default, `never`.
notify_on_cmd_finish: ?values.NotifyOnCmdFinish = null,
/// The value of the `TERM` environment variable to set. null: kitty's default, `xterm-kitty`.
term: ?[]const u8 = null,
/// The value of the `TERMINFO` environment variable to set. null: kitty's default, `path`.
terminfo_type: ?enum { path, direct, none } = null,
/// Forward STDOUT and STDERR of the kitty process to child processes. null: kitty's default, `no`.
forward_stdio: ?bool = null,
/// Specify entries for various menus in kitty. Each item is written as its own line.
menu_map: []const values.MenuMap = &.{},

/// Options kitty allows more than once: each item is its own line.
pub const repeated = [_][]const u8{ "remote_control_password", "env", "filter_notification", "watcher", "exe_search_path", "menu_map" };
