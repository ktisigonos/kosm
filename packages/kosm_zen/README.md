# kosm_zen

Zen Browser for kosm: its theme colors as CSS custom properties. Needs `kosm_css` installed,
which writes the file.

The app writes `~/.config/ZenBrowser/kosm.css`. Make your `userChrome.css` and
`userContent.css` use it once (D57): `@import` it first, then use the properties wherever a
color goes:

```css
@import url("kosm.css");

:root {
  --zen-primary-color: var(--kosm-foreground) !important;
  --toolbar-bgcolor: var(--kosm-button) !important;
}
.identity-color-blue {
  --identity-tab-color: var(--kosm-containers-blue) !important;
}
```

## Fields

| Field | Property | Default |
|---|---|---|
| `file` | | `~/.config/ZenBrowser/kosm.css` |
| `color_format` | | null: `#rrggbbaa` |
| `foreground` | `--kosm-foreground` | white, black in light mode |
| `accent` | `--kosm-accent` | cyan |
| `background` | `--kosm-background` | black, white in light mode |
| `button` | `--kosm-button` | `surface.raised` of `background` |
| `button_hovered` | `--kosm-button-hovered` | null: `hovered` of `button` |
| `border` | `--kosm-border` | cyan |
| `containers.blue` | `--kosm-containers-blue` | the wheel's blue |
| `containers.turquoise` | `--kosm-containers-turquoise` | the wheel's cyan |
| `containers.green` | `--kosm-containers-green` | the wheel's green |
| `containers.yellow` | `--kosm-containers-yellow` | the wheel's yellow |
| `containers.orange` | `--kosm-containers-orange` | the wheel's orange |
| `containers.red` | `--kosm-containers-red` | the wheel's red |
| `containers.pink` | `--kosm-containers-pink` | the wheel's pink |
| `containers.purple` | `--kosm-containers-purple` | the wheel's purple |
| `hovered` | | the theme's `state.hovered` |
