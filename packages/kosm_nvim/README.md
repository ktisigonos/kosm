# kosm_nvim

Neovim for kosm: a base16 palette written to `~/.config/nvim/lua/theme.lua`, which returns it as
a Lua table. Load it from your own nvim config (D57), for example with a base16 colorscheme
plugin:

```lua
local theme = require('theme')
```

## Fields

| Field | Default |
|---|---|
| `file` | `~/.config/nvim/lua/theme.lua` |
| `format` | `.{ .color = .hex }` (`#rrggbb`); booleans `true`/`false`, 6 float decimals (D70) |
| `transparent` | false |
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
