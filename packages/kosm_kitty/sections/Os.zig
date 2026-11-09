//! kitty's "OS specific tweaks" options. Field names are kitty's option names.

const values = @import("../values.zig");

/// The color of the kitty window's titlebar on Wayland systems with client side window decorations such as GNOME. null: kitty's default, `system`.
wayland_titlebar_color: ?values.TitlebarColor = null,
/// The color of the kitty window's titlebar on macOS. null: kitty's default, `system`.
macos_titlebar_color: ?values.MacosTitlebarColor = null,
/// Use the `Option` key as an `Alt` key on macOS. null: kitty's default, `no`.
macos_option_as_alt: ?enum { no, left, right, both } = null,
/// Hide kitty from running tasks on macOS (Cmd+Tab and the Dock). null: kitty's default, `no`.
macos_hide_from_tasks: ?bool = null,
/// Have kitty quit when all the top-level windows are closed on macOS. null: kitty's default, `no`.
macos_quit_when_last_window_closed: ?bool = null,
/// Disable this if you want kitty top-level OS windows to not be resizable on macOS. null: kitty's default, `yes`.
macos_window_resizable: ?bool = null,
/// Draw an extra border around the font with the given width, to increase legibility at small font sizes on macOS. null: kitty's default, `0`.
macos_thicken_font: ?f64 = null,
/// Use the macOS traditional full-screen transition, that is faster, but less pretty. null: kitty's default, `no`.
macos_traditional_fullscreen: ?bool = null,
/// When using `macos_traditional_fullscreen`, ignore the safe area insets on displays such as MacBook screens with a notch. null: kitty's default, `no`.
macos_fullscreen_ignore_safe_area_insets: ?bool = null,
/// Place macOS desktop panels in the physical screen frame instead of the visible one. null: kitty's default, `no`.
macos_use_physical_screen_frame: ?bool = null,
/// Set the macOS NSWindow level for newly created panel OS windows such as with the `panel kitten`. null: kitty's default, `unset`.
macos_ns_window_layer: ?[]const u8 = null,
/// Control where the window title is displayed on macOS. null: kitty's default, `all`.
macos_show_window_title_in: ?enum { all, menubar, none, window } = null,
/// The maximum number of characters from the window title to show in the macOS global menu bar. null: kitty's default, `0`.
macos_menubar_title_max_length: ?u32 = null,
/// Use a custom mouse cursor for macOS that is easier to see on both light and dark backgrounds. null: kitty's default, `no`.
macos_custom_beam_cursor: ?bool = null,
/// The colorspace in which to interpret terminal colors. null: kitty's default, `srgb`.
macos_colorspace: ?enum { srgb, default, displayp3 } = null,
/// Choose between Wayland and X11 backends. null: kitty's default, `auto`.
linux_display_server: ?enum { auto, wayland, x11 } = null,
/// Enable Input Method Extension on Wayland. null: kitty's default, `yes`.
wayland_enable_ime: ?bool = null,
