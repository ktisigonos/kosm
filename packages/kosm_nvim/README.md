# kosm_nvim

Neovim for kosm: a base16 palette written to `~/.config/nvim/lua/theme.lua`, which returns it as
a Lua table. Load it from your own nvim config (D57), for example with a base16 colorscheme
plugin:

```lua
local theme = require('theme')
```

The file is a Lua module returning one flat table (`theme.base00`, `theme.br_white`), written
through the `lua` adapter of `kosm_lua`. Null values are not written.

A minimal config can skip `from` (D100): `kosm_nvim.App{}` writes an empty module
(`return {}`), so assign only what you want (`.{ .base16 = .{ .base0D = kosm.hex("2d8699") } }`).

## Fields

Every color is null by default; the column says what `from(theme)` sets.

| Field | Default |
|---|---|
| `file` | `~/.config/nvim/lua/theme.lua` |
| `format` | `.{}`: the Lua adapter's `true`/`false`, then `#rrggbb` and 6 float decimals (D70) |
| `transparent` | null: not written |
| `base16.base00` | black, white in light mode (background) |
| `base16.base01` | `surface.raised` of `base00` |
| `base16.base02` | `state.selected` of `base00` |
| `base16.base03` | `emphasis.muted` of `base05` (comments) |
| `base16.base04` | `emphasis.muted` of `base05` |
| `base16.base05` | white, black in light mode (foreground) |
| `base16.base06` | `emphasis.strong` of `base05` |
| `base16.base07` | `lightness.bright` of `base05` |
| `base16.base08` | red |
| `base16.base09` | orange |
| `base16.base0A` | yellow |
| `base16.base0B` | green |
| `base16.base0C` | cyan |
| `base16.base0D` | blue |
| `base16.base0E` | purple |
| `base16.base0F` | pink |
| `terminal.black` ... `terminal.white` | the palette's black, white and the wheel's hues |
| `terminal.br_black` ... `terminal.br_white` | `lightness.bright` of each |
