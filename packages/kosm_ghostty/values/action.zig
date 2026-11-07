//! ghostty's keybind actions (`ghostty +list-actions`), shared by `keybind` and
//! `command-palette-entry`.

const std = @import("std");
const Joined = @import("../Joined.zig");
const ResizeSplit = @import("ResizeSplit.zig");
const WriteFile = @import("WriteFile.zig");

/// What a keybind or command palette entry does. Names and parameters are ghostty's;
/// `raw` writes an action kosm doesn't know yet, as ghostty spells it (`some_action:argument`).
pub const Action = union(enum) {
    /// Do nothing and swallow the key.
    ignore,
    /// Remove the binding, so the key reaches the program.
    unbind,
    /// Send a CSI sequence, without its `ESC [` header (`0m`).
    csi: []const u8,
    /// Send an ESC sequence (`d`).
    esc: []const u8,
    /// Send text; kosm writes it as the Zig string literal ghostty expects, so `"\x15"` sends Ctrl-U.
    text: []const u8,
    /// Send data depending on cursor key mode, in ghostty's own syntax.
    cursor_key: []const u8,
    /// Reset the terminal.
    reset,
    /// Copy the selection to the clipboard in a format.
    copy_to_clipboard: enum { plain, vt, html, mixed },
    /// Paste the default clipboard.
    paste_from_clipboard,
    /// Paste the selection clipboard.
    paste_from_selection,
    /// Copy the URL under the cursor.
    copy_url_to_clipboard,
    /// Copy the terminal title.
    copy_title_to_clipboard,
    /// Grow the font by this many points.
    increase_font_size: f64,
    /// Shrink the font by this many points.
    decrease_font_size: f64,
    /// Go back to the configured font size.
    reset_font_size,
    /// Set the font size in points.
    set_font_size: f64,
    /// Search for this text; empty cancels the search.
    search: []const u8,
    /// Search for the selected text.
    search_selection,
    /// Go to the previous or next search result.
    navigate_search: enum { previous, next },
    /// Open the search UI.
    start_search,
    /// End the search and hide its UI.
    end_search,
    /// Clear the screen and the scrollback.
    clear_screen,
    /// Select all text on the screen.
    select_all,
    /// Scroll to the top.
    scroll_to_top,
    /// Scroll to the bottom.
    scroll_to_bottom,
    /// Scroll to the selection.
    scroll_to_selection,
    /// Scroll to this row, 0 being the first.
    scroll_to_row: u32,
    /// Scroll up one page.
    scroll_page_up,
    /// Scroll down one page.
    scroll_page_down,
    /// Scroll by this many pages; negative scrolls up.
    scroll_page_fractional: f64,
    /// Scroll by this many lines; negative scrolls up.
    scroll_page_lines: i32,
    /// Grow or shrink the selection.
    adjust_selection: enum { left, right, up, down, page_up, page_down, home, end, beginning_of_line, end_of_line },
    /// Jump by this many prompts; negative goes back. Needs shell integration.
    jump_to_prompt: i32,
    /// Write the scrollback to a temporary file and use it.
    write_scrollback_file: WriteFile,
    /// Write the screen to a temporary file and use it.
    write_screen_file: WriteFile,
    /// Write the selection to a temporary file and use it.
    write_selection_file: WriteFile,
    /// Open a new window.
    new_window,
    /// Open a new tab.
    new_tab,
    /// Go to the previous tab.
    previous_tab,
    /// Go to the next tab.
    next_tab,
    /// Go to the last tab.
    last_tab,
    /// Go to this tab, counting from 1.
    goto_tab: u32,
    /// Move the tab by this many places, wrapping around.
    move_tab: i32,
    /// Move the tab to a new window.
    move_tab_to_new_window,
    /// Toggle the tab overview (GTK).
    toggle_tab_overview,
    /// Ask for a new title for the focused surface.
    prompt_surface_title,
    /// Ask for a new title for the tab.
    prompt_tab_title,
    /// Ask for a new title for the window (Linux).
    prompt_window_title,
    /// Set the focused surface's title.
    set_surface_title: []const u8,
    /// Set the tab's title; empty clears it.
    set_tab_title: []const u8,
    /// Set the window's title (Linux).
    set_window_title: []const u8,
    /// Open a split; `auto` splits along the longer side.
    new_split: enum { right, down, left, up, auto },
    /// Focus a split by direction or creation order.
    goto_split: enum { up, down, left, right, previous, next },
    /// Focus the previous or next window.
    goto_window: enum { previous, next },
    /// Zoom in or out of the split.
    toggle_split_zoom,
    /// Toggle read-only mode for the surface.
    toggle_readonly,
    /// Move the split's edge.
    resize_split: ResizeSplit,
    /// Make every split of the window the same size.
    equalize_splits,
    /// Give the window its default size (macOS).
    reset_window_size,
    /// Show, hide or toggle the terminal inspector.
    inspector: enum { toggle, show, hide },
    /// Show the GTK inspector.
    show_gtk_inspector,
    /// Show the on-screen keyboard (GTK).
    show_on_screen_keyboard,
    /// Open the config in the OS's editor, or in `$EDITOR` in a new window (GTK).
    open_config: enum { os_open, new_window },
    /// Reload the configuration.
    reload_config,
    /// Close the focused surface.
    close_surface,
    /// Close this tab, every other one, or every one to its right.
    close_tab: enum { this, other, right },
    /// Close the window.
    close_window,
    /// Deprecated by ghostty and without effect; use `close_window` with `all`.
    close_all_windows,
    /// Maximize or unmaximize the window.
    toggle_maximize,
    /// Enter or leave fullscreen.
    toggle_fullscreen,
    /// Toggle window decorations (Linux).
    toggle_window_decorations,
    /// Toggle keeping the window above others (macOS).
    toggle_window_float_on_top,
    /// Toggle secure input (macOS).
    toggle_secure_input,
    /// Toggle mouse reporting to programs.
    toggle_mouse_reporting,
    /// Toggle the command palette.
    toggle_command_palette,
    /// Toggle the quick terminal.
    toggle_quick_terminal,
    /// Show or hide every window (macOS).
    toggle_visibility,
    /// Toggle between the configured background opacity and opaque (macOS).
    toggle_background_opacity,
    /// Check for updates (macOS).
    check_for_updates,
    /// Undo the last undoable action, such as closing a tab (macOS).
    undo,
    /// Redo the last undone action (macOS).
    redo,
    /// End the key sequence, sending the keys before this one to the program.
    end_key_sequence,
    /// Activate a key table until it is deactivated.
    activate_key_table: []const u8,
    /// Activate a key table for one binding.
    activate_key_table_once: []const u8,
    /// Deactivate the innermost key table.
    deactivate_key_table,
    /// Deactivate every key table.
    deactivate_all_key_tables,
    /// Quit ghostty.
    quit,
    /// Crash ghostty on purpose, to test crash reporting.
    crash: enum { main, io, render },
    /// Any action as ghostty spells it, written as is.
    raw: []const u8,

    /// How the action's text is embedded: as is on a `keybind` line, or inside a quoted Zig string.
    pub const Embedding = enum { line, quoted };

    /// Writes the action the way ghostty spells it, numbers in the file's format.
    pub fn write(action: Action, joined: *Joined, embedding: Embedding) Joined.Error!void {
        switch (action) {
            .raw => |text| try writeText(joined, text, embedding),
            .text => |text| {
                var escaped: std.Io.Writer.Allocating = .init(joined.allocator);
                try std.zig.stringEscape(text, &escaped.writer);
                try writeText(joined, "text:", embedding);
                try writeText(joined, escaped.written(), embedding);
            },
            inline else => |parameter, tag| {
                try writeText(joined, @tagName(tag), embedding);
                try writeParameter(joined, parameter, embedding);
            },
        }
    }
};

fn writeParameter(joined: *Joined, parameter: anytype, embedding: Action.Embedding) Joined.Error!void {
    const Parameter = @TypeOf(parameter);
    if (Parameter == void) return;
    try joined.writer().writeByte(':');
    if (Parameter == []const u8) return writeText(joined, parameter, embedding);
    if (Parameter == ResizeSplit) return joined.writer().print("{t},{d}", .{ parameter.direction, parameter.pixels });
    if (Parameter == WriteFile) {
        try joined.writer().print("{t}", .{parameter.action});
        if (parameter.format) |format| try joined.writer().print(",{t}", .{format});
        return;
    }
    switch (@typeInfo(Parameter)) {
        .float => try joined.float(parameter),
        .int => try joined.writer().print("{d}", .{parameter}),
        .@"enum" => try joined.writer().writeAll(@tagName(parameter)),
        else => @compileError("kosm_ghostty: an action parameter of type " ++ @typeName(Parameter) ++ " has no spelling"),
    }
}

fn writeText(joined: *Joined, text: []const u8, embedding: Action.Embedding) Joined.Error!void {
    switch (embedding) {
        .line => try joined.writer().writeAll(text),
        .quoted => try std.zig.stringEscape(text, joined.writer()),
    }
}
