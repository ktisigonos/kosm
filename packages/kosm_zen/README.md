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
| `foreground` | `--kosm-foreground` | null; `from`: white, black in light mode |
| `accent` | `--kosm-accent` | null; `from`: cyan |
| `background` | `--kosm-background` | null; `from`: black, white in light mode |
| `button` | `--kosm-button` | null; `from`: `surface.raised` of `background` |
| `button_hovered` | `--kosm-button-hovered` | null: `hovered` of `button` when both are set |
| `border` | `--kosm-border` | null; `from`: cyan |
| `containers.blue` | `--kosm-containers-blue` | null; `from`: the wheel's blue |
| `containers.turquoise` | `--kosm-containers-turquoise` | null; `from`: the wheel's cyan |
| `containers.green` | `--kosm-containers-green` | null; `from`: the wheel's green |
| `containers.yellow` | `--kosm-containers-yellow` | null; `from`: the wheel's yellow |
| `containers.orange` | `--kosm-containers-orange` | null; `from`: the wheel's orange |
| `containers.red` | `--kosm-containers-red` | null; `from`: the wheel's red |
| `containers.pink` | `--kosm-containers-pink` | null; `from`: the wheel's pink |
| `containers.purple` | `--kosm-containers-purple` | null; `from`: the wheel's purple |
| `hovered` | | null: nothing derived; `from`: the theme's `state.hovered` |
| `profile` | | null: no prefs, only the CSS; `from`: `Profile.from(theme)` |
| `extra` | | `&.{}`: custom properties the app doesn't cover, by path (D99) |

A null color is not written. A minimal config can skip `from` (D100): `kosm_zen.App{}` writes a
`kosm.css` with an empty `:root` and no prefs, so assign only what you want
(`.{ .accent = kosm.hex("268078") }`).

`extra` writes other custom properties after the app's own (D99), the path's keys joined by `-`:
`.{ .path = "kosm.tab.radius", .value = .{ .raw = "8px" } }` is `--kosm-tab-radius`. An extra
whose path equals, contains or lies inside a set color's or another extra's fails the apply naming
both.

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
| `prefs` | `.{}`, below; with no pref set, the profile writes nothing and needs no Zen |
| `extra` | `&.{}`: prefs the app doesn't cover, by their whole about:config name (D99) |

`extra` writes prefs `prefs` doesn't cover, after its own, each named by its whole about:config
name (no quotes needed): `.{ .path = "zen.urlbar.behavior", .value = .{ .string = "float" } }`.
Prefs never nest, so only a name written twice, by `prefs` or another extra, fails the apply.

### `prefs` fields

Named like about:config: `prefs.zen.theme.accent_color` is `zen.theme.accent-color`. A null pref
is not written, so Zen's own value stays. A pref that also has prefs below it is a group, and
its own value is the group's `value` field: `prefs.zen.theme.gradient.value` is
`zen.theme.gradient` (D102).

| Field | Pref | Default |
|---|---|---|
| `zen.theme.accent_color` | `zen.theme.accent-color` | cyan |
| `zen.theme.gradient.value` | `zen.theme.gradient` | null (Zen: true) |
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
