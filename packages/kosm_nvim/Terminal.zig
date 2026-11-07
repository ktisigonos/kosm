//! The terminal palette under the names your nvim config reads.

const kosm = @import("kosm");

/// null: not written. `from`: the palette's black.
black: ?kosm.Color = null,
/// null: not written. `from`: the wheel's red.
red: ?kosm.Color = null,
/// null: not written. `from`: the wheel's green.
green: ?kosm.Color = null,
/// null: not written. `from`: the wheel's yellow.
yellow: ?kosm.Color = null,
/// null: not written. `from`: the wheel's blue.
blue: ?kosm.Color = null,
/// null: not written. `from`: the wheel's magenta.
magenta: ?kosm.Color = null,
/// null: not written. `from`: the wheel's cyan.
cyan: ?kosm.Color = null,
/// null: not written. `from`: the palette's white.
white: ?kosm.Color = null,
/// null: not written. `from`: `lightness.bright` of `black`.
br_black: ?kosm.Color = null,
/// null: not written. `from`: `lightness.bright` of `red`.
br_red: ?kosm.Color = null,
/// null: not written. `from`: `lightness.bright` of `green`.
br_green: ?kosm.Color = null,
/// null: not written. `from`: `lightness.bright` of `yellow`.
br_yellow: ?kosm.Color = null,
/// null: not written. `from`: `lightness.bright` of `blue`.
br_blue: ?kosm.Color = null,
/// null: not written. `from`: `lightness.bright` of `magenta`.
br_magenta: ?kosm.Color = null,
/// null: not written. `from`: `lightness.bright` of `cyan`.
br_cyan: ?kosm.Color = null,
/// null: not written. `from`: `lightness.bright` of `white`.
br_white: ?kosm.Color = null,
