# kosm_zen

Zen Browser for kosm: its theme colors as CSS custom properties, and its about:config prefs in
every profile's `user.js` (D94). Needs `kosm_css` and `kosm_userjs` installed, which write the
files.

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
| `format` | | `.{}`: the CSS adapter's `#rrggbbaa`, then 6 float decimals (D70) |
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
| `profile` | | `Profile.from(theme)`; null writes no prefs, only the CSS |

## Prefs

Zen reads a profile's `user.js` at startup, so a pref kosm writes takes effect the next time Zen
starts. `profile` writes its prefs to every profile directory under `~/.zen` (every one holding a
`prefs.js`) inside a block, keeping any prefs of your own in the file:

```js
user_pref("browser.startup.page", 3);
// kosm:begin zen
user_pref("zen.theme.accent-color", "#268078");
...
// kosm:end
```

A missing or empty `user.js` is created holding only the block. `target = .generate` makes kosm
own the whole file instead.

To give some profiles other prefs, put a second `kosm_zen.Profile` in your kosmos' tree and
narrow the first one. Two profile sets that reach the same profile fail the apply.

```zig
result.zen.profile.?.exclude = &.{"~/.zen/*.work"};
result.zen_work = kosm_zen.Profile.from(theme);
result.zen_work.profiles = "~/.zen/*.work";
result.zen_work.prefs.zen.view.window.scheme = .light;
```

On a machine without Zen, set `profile = null` (a profile glob matching nothing fails the apply).

### `Profile` fields

| Field | Default |
|---|---|
| `profiles` | `~/.zen/*`: a glob of profile directories; only ones holding a `prefs.js` count |
| `exclude` | none: globs of profile directories to leave out |
| `target` | `.block` (`default_target`); `.generate` owns the whole `user.js` |
| `format` | `.{}`: the `userjs` adapter's `#rrggbb` (D70) |
| `prefs` | below |

### `prefs` fields

Named like about:config: `prefs.zen.theme.accent_color` is `zen.theme.accent-color`. A null pref
is not written, so Zen's own value stays.

| Field | Pref | Default |
|---|---|---|
| `zen.theme.accent_color` | `zen.theme.accent-color` | cyan |
| `zen.theme.content_element_separation` | `zen.theme.content-element-separation` (px) | null (Zen: 8) |
| `zen.theme.border_radius` | `zen.theme.border-radius` (px, -1: the platform's) | null (Zen: -1) |
| `zen.theme.hide_tab_throbber` | `zen.theme.hide-tab-throbber` | null (Zen: true) |
| `zen.theme.use_system_colors` | `zen.theme.use-system-colors` | null (Zen: false) |
| `zen.view.window.scheme` | `zen.view.window.scheme` (`.dark`, `.light`, `.auto`) | the theme's mode |
| `zen.view.compact.enable_at_startup` | `zen.view.compact.enable-at-startup` | null (Zen: false) |
| `zen.view.compact.hide_tabbar` | `zen.view.compact.hide-tabbar` | null (Zen: true) |
| `zen.view.compact.hide_toolbar` | `zen.view.compact.hide-toolbar` | null (Zen: false) |
| `zen.view.grey_out_inactive_windows` | `zen.view.grey-out-inactive-windows` | null (Zen: true) |
| `zen.view.use_single_toolbar` | `zen.view.use-single-toolbar` | null (Zen: true) |
| `zen.view.show_newtab_button_top` | `zen.view.show-newtab-button-top` | null (Zen: true) |
| `zen.view.sidebar_expanded` | `zen.view.sidebar-expanded` | null (Zen: true) |
| `zen.widget.linux.transparency` | `zen.widget.linux.transparency` | null (Zen: false) |
| `browser.display.background_color` | `browser.display.background_color` | black, white in light mode |
| `browser.display.foreground_color` | `browser.display.foreground_color` | white, black in light mode |
| `browser.tabs.allow_transparent_browser` | `browser.tabs.allow_transparent_browser` | null (Firefox: false) |
| `toolkit.legacy_user_profile_customizations.stylesheets` | `toolkit.legacyUserProfileCustomizations.stylesheets` | true, which the CSS needs |
