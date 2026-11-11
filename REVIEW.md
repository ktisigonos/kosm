# Review list

Decisions an agent took while the human was away (2026-11-10 onwards), one line each, newest
step last. Overturn any of them: say which, and it is changed in a follow-up commit. Delete
this file once everything in it is reviewed.

## Where things are

- Every package is a repository of its own beside kosm: `~/Projects/Zig/kosm_<name>`, branch
  `master`, `origin` set to `https://git.nnstdios.com/nnra6864/kosm_<name>`. None is pushed, and
  kosm itself is not pushed either.
- Packages pin kosm and each other by commit and hash. An unpushed commit builds because its
  archive was fetched into Zig's cache first (`doc/ZIG_NOTES.md`), so never amend or rebase a
  commit another manifest pins.
- To publish: create one empty repository per package on the forge, then `git push origin master`
  in kosm and `git push -u origin master` in each package directory. After that
  `zig build test -Dnetwork` in kosm checks a config made by the real `kosm init`. Every
  package directory to push, 32 with kosm: `ls -d ~/Projects/Zig/kosm*`. A loop doing it:
  `for d in ~/Projects/Zig/kosm*; do git -C "$d" push -u origin master; done`.

## 13a. Packages in their own repositories

- The split branches (`git subtree split`) were cloned into the sibling repositories and then
  deleted from kosm's repository; each package got a `.gitignore` for Zig's caches.
- An app's package exports the adapter it writes with as `<name>_adapter` (`lua_adapter`,
  `css_adapter`, `userjs_adapter`).
- `kosm init` writes Kyanos only together with a new manifest, since an existing manifest may
  lack the official packages it imports.
- `zig build test -Dnetwork` is a test that needs the network and the pushed repositories; it is
  skipped otherwise.

## Your config project

- `~/.config/kosm/build.zig.zon` and `packages.zon` now list kosm and the 11 packages, pinned to
  the local commits (your `kosm` is this repository's build, which no longer ships packages, so
  Krystallos did not build). Checked with `kosm apply krystallos --diff` only. The old files are
  not kept; `git diff` in your dotfiles shows the change.
- Zig's own cache (`~/.cache/zig`) was given each pinned package, so the config builds before
  anything is pushed.

## 13b. Keyboard layouts

- The core type is `kosm.Keyboard`: `layouts` (each `.layout` and an optional `.variant`), `model`,
  `options`, `rules`. It builds XKB's comma lists, the one form Hyprland, sway, `setxkbmap`, the
  `XKB_DEFAULT_*` variables and KDE's `kxkbrc` all take. GNOME's `layout+variant` spelling is left
  until an app needs it.
- `kosm_hyprland` gets one field, `keyboard`, filling `input.kb_*` where they are null. No
  variant at all writes no `kb_variant`.
- A name with a comma or a space, or an empty layout or option, fails the apply.
- Found on the way: a package built on its own ended up with two copies of kosm once it pinned a
  newer kosm than its adapter package. The one-copy rule now covers a package's own build too
  (`build/unify.zig`), so bumping one pin never forces bumping every package.

## 13c. Showing a kosmos' colors

- The command is `kosm colors <kosmos>`. It prints every public `kosm.Palette` constant at the
  top of the kosmos' file (root.zig for a directory kosmos), the way adapters are found; a kosmos
  declaring none gets an error saying so. Krystallos keeps its palette in `values.zig`, so its
  root.zig needs `pub const palette = values.palette;` to be shown.
- It shows black, white, gray and the 12 hues, with `mixed` after each one the palette does not
  set. Variations are not shown: they need a theme, which a kosmos builds inside its functions.
- Blocks are background-colored spaces (truecolor), drawn only when kosm's stdout is a terminal.

## 13d. Shell completions

- `kosm completions fish|bash|zsh` prints a script; its header says where to install it. Each
  script only calls a hidden `kosm complete -- <words>`, which prints the candidates, so what
  completes is decided in one place and tested in Zig.
- Kosmos names come from the config's lister, and a kosmos' `--param` flags and `--set` paths
  from its runner, asked through the environment variable `KOSM_COMPLETIONS` (the interface
  number went from 1 to 2). The first Tab on a kosmos builds its runner, so it can take seconds.
- After `--config` the shell completes directories itself; a parameter's value is not completed.
- Checked by hand: `bash -n` and `fish -n` accept their scripts, and `kosm complete` answers for
  Krystallos. zsh is not installed here, so its script has never run. Tests cover commands,
  packages and a config that does not build; kosmos names and params are covered by the
  runner's unit tests, not yet by an end-to-end test through a built config.

## 13e. One background opacity for every app

- It lives on the theme: `theme.background_alpha` (0..1, default 1), assigned after
  `kosm.Theme.from`. The palette's black was not used: in light mode the background is white, and
  a translucent black would also be a translucent foreground.
- `theme.asBackground(color)` scales a color's alpha by it; each app's `from` calls it on the
  color it picks as its background, so a palette black that already carries alpha still works.
- kitty and ghostty needed no new field: their `background_opacity` already follows the
  background's alpha. Zen's `background` (and the `button` raised from it) carries the alpha.
  `kosm_nvim.transparent` is the one new derived switch: null turns into `true` when `base00`
  is not opaque.
- Hyprland gets nothing: its `misc.background_color` is the color behind every window.
- Changed in 13i: Zen's page background pref (`browser.display.background_color`) takes the
  alpha too, as Krystallos already set it by hand.
- Kyanos still sets its alpha by hand; the starting kosmos is replaced in 13o.

## 13f. Curves, easings and Hyprland animations

- Core: `kosm.Curve` is a union of `.bezier` (`x1, y1, x2, y2`, as CSS's `cubic-bezier`) and
  `.spring` (`mass` 1, `stiffness`, `damping`). The easings are declarations on it, so a kosmos
  writes `.ease_out_expo`: CSS's `linear`, `ease`, `ease_in`, `ease_out`, `ease_in_out`, and
  `ease_in_*`, `ease_out_*`, `ease_in_out_*` for sine, quad, cubic, quart, quint, expo, circ and
  back. Elastic and bounce have no bezier, so they are left out.
- `kosm_hyprland` gets two fields named after Hyprland's calls: `curve` (named curves) and
  `animation` (one entry per leaf). `animation` sits next to the existing `animations` section
  (`animations.enabled`); say if you want other names.
- An animation names its curve by string, as Hyprland does; the app writes it under `bezier` or
  `spring` by what the curve is. `default` is Hyprland's own bezier and needs no definition.
- The generated module's shape: the calls first, then `return { ... }` as before, so the block
  `hl.config(require("kosm"))` and reading single values from the module still work. A new
  `hyprland` adapter in the package writes it, using the `lua` adapter for values.
- Leaves are an enum in Zig spelling (32 leaves, `fade_glow` included); `Hyprland
  --verify-config` accepted every one and the generated module. That flag is a way to check
  generated Hyprland config without touching the running session.
- Hyprland reads a spring's `damping` and also the misspelling `dampening` your curves.lua
  uses; kosm writes `damping`.
- With the `.edit` target, set curves or animations fail the apply: kosm never adds calls.

## 13g. Hyprland environment variables

- The field is `env`: a list of `.{ .name, .value }`, both text, written as `hl.env` calls in
  the order given, at the top of the generated module.
- The theme does not know cursor or toolkit themes, so the derived ones come from four new
  fields of the app: `cursor_theme` (`HYPRCURSOR_THEME`, `XCURSOR_THEME`), `cursor_size`
  (`HYPRCURSOR_SIZE`, `XCURSOR_SIZE`), `gtk_theme` (`GTK_THEME`) and `qt_platform_theme`
  (`QT_QPA_PLATFORMTHEME`). They are written before `env`, and not at all when `env` sets the
  same name.
- A name given twice in `env` fails naming it and both values; so do an empty name and one
  holding `=`. With the `.edit` target any variable fails the apply.

## 13h. Hyprland plugins

- The field is `plugin`: a list of `.{ .name, .settings }`, the settings by path below the
  plugin, like `extra`'s. The generated module wraps each plugin in
  `if hl.plugin.<name> ~= nil then hl.config({ plugin = { <name> = { ... } } }) end`, before
  the returned table. `extra`'s docs no longer use a plugin as their example.
- With the `.edit` target they are set at `plugin.<name>.<path>`. For that, `kosm_lua` paths
  now see into `if` and `do` blocks (they run as the file loads); a value set in several
  branches matches several times and needs `setAll` or `setNth`. Function bodies stay hidden.
- A plugin given twice, a name `hl.plugin` can't spell, and an `extra` reaching into a plugin
  that `plugin` holds all fail the apply.
- hyprglass is configured through `hl.plugin.hyprglass.config(...)` and `.layer(...)` calls of
  its own, not through `hl.config`, so this field does not cover it.

## 13i. Browser extensions and Zen mods

- Where the settings live: Dark Reader and Stylus keep theirs in the profile's extension
  storage (`storage-sync-v2.sqlite` and IndexedDB), which only the running browser can write
  safely. Zen mods keep theirs as ordinary about:config prefs.
- Dark Reader: a new package, `kosm_darkreader`. It edits a settings file Dark Reader exported
  (as Ricer did with `DarkReaderSettings.json`), changing only the set values, and you import
  the file by hand after an apply. A missing export fails the apply, saying how to make one. It
  is in `kosm init`'s list of official packages.
- Stylus: no app. Its styles can't be written safely, and its export holds CSS inside JSON
  strings, so a font can't be set by path. The goal of your global `Font` style is met without
  the extension: `prefs.browser.display.use_document_fonts = .never` in `kosm_zen` shows every
  page in your fontconfig fonts (step 13j sets those).
- "Zen Zero": your profile has no mod of that name. I took it to be the installed Transparent
  Zen mod (`mod.sameerasw.*` prefs: `zen_bg_color_enabled`, `zen_transparency_color`), now
  typed prefs of `kosm_zen`. Tell me if Zen Zero is something else.
- A page background that is not opaque (the theme's `background_alpha` below 1) now derives,
  wherever they are null: `browser.tabs.allow_transparent_browser`,
  `zen.widget.linux.transparency`, the mod's two prefs, and `#rrggbbaa` as the profile's color
  format. A profile without the mod simply ignores the mod's prefs, so nothing is skipped.

## 13j. `kosm_fontconfig`

- Two new packages, both in `kosm init`'s official list: `kosm_xml`, a hand-written `xml`
  adapter (no grammar) that writes whole files through `generate`, and `kosm_fontconfig`, the
  app. `generate` with an adapter beat a template: templates can't loop over a list of fonts,
  and the XML adapter is reused by 13l (CS2's fontconfig files) and 13n (Blender's theme).
- `kosm_xml` maps a value tree to XML: a table's entries become child elements, a list
  repeats its element, a key starting with `@` is an attribute, a root key starting with `!`
  a declaration (`!DOCTYPE`). It cannot edit XML files yet, and an element can't hold both
  text and children; neither is needed so far.
- The app writes `~/.config/fontconfig/conf.d/50-kosm.conf` whole (fontconfig only reads
  `conf.d` files starting with a digit). Fields `sans_serif`, `serif`, `monospace`, each a
  list in fallback order, null not written; a family with an empty list fails. `from` sets
  nothing, since `kosm.Theme` holds no fonts.
- `binding` (default `.strong`) is a field I added: checked with `fc-match` in a temp
  `XDG_CONFIG_HOME`, fontconfig's default weak binding let this system's Noto rules pass over
  the listed fonts, while `binding="strong"` made the first installed listed font win. Your
  current `fonts.conf` (from Ricer) uses weak; with one Maple Mono for every family it never
  showed.
- Hinting and antialiasing are not fields: nothing in Ricer or your config sets them, and
  the system's `10-hinting-slight.conf` and `10-yes-antialias.conf` already do.
- Krystallos does not use the app yet; that comes with the base kosmos (13o). Your
  `fonts.conf` can then drop its aliases.

## 13k. Apps for the rest of Ricer's list

Eight new packages, all in `kosm init`'s official list. The rule I followed: a theme file the
program picks by name is generated whole as `kosm` (Ricer called it `Ricer`); a program that
includes or drops in extra files gets a file of kosm's own; the program's own config is only
edited, by path, to select that theme or set the font. Each package has a README with its
fields.

- `kosm_foot`: generates `~/.config/foot/kosm.ini` (fonts in fallback order, `[colors-dark]`,
  `[colors-light]`, extras). You add `include=~/.config/foot/kosm.ini` as foot.ini's first line
  and delete its fonts and colors. Checked with `foot --check-config`. foot has no reload.
- `kosm_dunst`: generates the drop-in `~/.config/dunst/dunstrc.d/50-kosm.conf` (font, the three
  urgency sections' colors, extras) and runs `dunstctl reload`. Dunst reads drop-ins with no
  setup, after dunstrc. Your dunstrc sets colors in `[global]`; delete them there.
- `kosm_tuios`: generates `~/.config/tuios/themes/kosm.json` and sets `appearance.theme` in
  `config.toml`. Ricer's `accent_bright` is not a key tuios knows (checked in its binary), so
  it is not a field. Checked with `tuios --preview-theme` in a temp config.
- `kosm_vicinae`: generates `~/.local/share/vicinae/themes/kosm.toml` from every section of
  `vicinae theme template`, writing only set colors, and sets `theme.dark.name` (or light) and
  the font in `settings.json`. Vicinae's 8-digit colors are Qt's `#AARRGGBB`, so the app writes
  6 digits only.
- `kosm_qtct`: one app for qt5ct and qt6ct: generates `colors/kosm.conf` for each (21 roles,
  plus Qt 6.6's accent for qt6ct) and sets `color_scheme_path` and `custom_palette` in each
  config. Fonts are left out: qt5ct and qt6ct store serialized QFonts their own window writes.
- `kosm_ohmyposh`: replaces the `palette` object of a prompt config (JSON or TOML) with named
  colors, which segments use as `p:<name>` (checked with `oh-my-posh print` in a temp dir).
  Your prompt layout stays yours. **Krystallos does not use it yet**: your `Ricer.json` has
  no `palette` and still has Ricer's colors inlined, and the edit fails without one. Converting
  it (`"palette": {}` and `p:` colors) is yours to do; then add it to Krystallos.
- `kosm_equibop`: a `/* kosm:begin kosm */` block of `--kosm-*` custom properties at the end
  of QuickCSS. Your Material Discord CSS then uses `var(--kosm-background)` and so on; until
  you change it, the block changes nothing visible.
- `kosm_adwsteamgtk`: a block of `--adw-*-rgb` variables (`r, g, b !important`, as the color
  themes write them) in `~/.config/AdwSteamGtk/custom.css`; a color's alpha goes to the `-a`
  variable where Adwaita has one. You re-install from AdwSteamGtk with Custom CSS on. Ricer
  instead wrote a color theme into AdwSteamGtk's cache, which an update wipes.
- `kosm_json` now has `serialize` (pretty-printed), for the tuios theme.
- Found while checking Krystallos: `kosm_hyprland`'s manifest left `adapter.zig` out of
  `paths`, so the fetched package didn't build. Fixed; every package's `paths` now covers its
  files.
- Krystallos (in `~/.config/kosm`, not committed anywhere) has one file per new app, and the
  config is re-pinned to every package's newest commit; `kosm apply krystallos --diff` runs and
  shows each new file and the selecting edits. The diff also holds changes from earlier steps
  you haven't applied (Zen's transparency prefs and `kosm.css`, nvim's `kosm.lua`).
- A kosm API gotcha found here: an `edit` path given as a runtime `[:0]const u8` (what
  `@tagName` returns) was a compile error. Fixed in kosm itself afterwards: sentinel-terminated
  text is path text now, alone or inside a tuple.

## 13l. Apps needing new formats (all but CS2's fonts.conf)

- hyprtoolkit and hyprmouse: no hyprlang adapter. Both files are flat `key = value` lines, so
  each package exports a `kosm_ini` dialect (`rgba(rrggbbaa)` for hyprtoolkit, `#rrggbb` for
  hyprmouse). `kosm_hyprtoolkit` generates `~/.config/hypr/hyprtoolkit.conf`, the file
  hyprtoolkit apps read; `kosm_hyprmouse` edits the keys already in `hyprmouse.conf` (it is
  hyprmouse's file, and hyprmouse is not installed here, so it was only tested on its shipped
  config).
- The Zen logo (SVG): a `template` in `kosm_zen` (`Logo.zig`, `logo.svg`), written to
  `~/.config/ZenBrowser/ZenLogo.svg`. No SVG adapter.
- Counter-Strike 1.6: a new adapter package, `kosm_keyvalues`, hand-written (~140 lines), no
  grammar. It edits `.res` and `.vdf` (quoted or bare tokens, blocks, `//` comments, `[$...]`
  conditionals, `#base` / `#include`), writes every value quoted, colors `r g b a`. It has no
  `serialize`: Valve's files are edited in place. `kosm_cs16` sets the 25 `Scheme.Colors`
  (snake_case fields, `control_bg` for `ControlBG`) and every font's `name`. Steam's default
  library is the default `file`; Krystallos points it at `~/Data/SteamLibrary`.
- Counter-Strike 2: `kosm_cs2` generates `42-repl-global.conf` (the game's global replacements,
  in `core/panorama/fonts/conf.d`) with `kosm_xml`: per replaced family a `font` rule
  (`assign`) and a `pattern` rule (`prepend`, strong), as Ricer's file had. Checked with
  `fc-match` in a temp config: Arial resolved to Maple Mono. **Not done: `fonts.conf`.** Your
  current one has the guide's "Custom fonts" section at the end (Ricer's template). Kosm can't
  edit XML in place yet (`kosm_xml` only writes whole files), and the cleanup is yours to
  describe, so 13l stays in TODO for that part. Since fonts.conf's own comment says the
  42-repl-global replacements still apply, the generated file alone may be enough; worth
  trying in game before deciding.
- `kosm init` lists the five new packages (`kosm_cs16`, `kosm_cs2`, `kosm_hyprmouse`,
  `kosm_hyprtoolkit`, `kosm_keyvalues`).
- Krystallos has `hyprtoolkit.zig`, `hyprmouse.zig`, `cs16.zig`, `cs2.zig` and a
  `steam_library` value; `--diff` exits 0. Differences from Ricer's output you will see:
  hyprtoolkit's accents are now cyan instead of bright white, `icon_theme = Ricer` is written
  bare (hyprlang has no quoted strings, so the quotes were part of the name before), CS 1.6's
  `ListBG` is opaque (it was alpha 0) and its dim text is grayer (the theme's emphasis steps).

## 13m. GTK and KDE colors (decided without a plan from you)

- No generated GTK theme. A full GTK 3 theme is thousands of lines of CSS, and Oomox's is a
  vendored copy of one. Instead `kosm_gtk` writes the colors the toolkits already draw with:
  - GTK 4: a block at the end of `~/.config/gtk-4.0/gtk.css` with libadwaita 1.10's color
    variables (`:root { --window-bg-color: ...; }`), the 51 it defines (read from its compiled
    stylesheet). Every libadwaita app follows them. Your gtk.css today is Oomox's 3000-line
    copy; the block goes after it and wins.
  - GTK 3: a block in `~/.config/gtk-3.0/gtk.css` of `@define-color window_bg_color ...` lines,
    written by a small `gtk3` adapter inside the package. **Only adw-gtk3 follows these**
    (the `adw-gtk-theme` package, theme `adw-gtk3-dark`); your Oomox GTK 3 theme ignores them.
    Switching GTK 3 apps to adw-gtk3 is your call (`gtk-theme-name` in settings.ini; kosm does
    not touch settings.ini).
  - Both forms parse without errors in GTK 4.24 and 3.24 (checked with a CssProvider).
- `kosm_kde` generates `~/.local/share/color-schemes/kosm.colors` (all eight sets, `[WM]`,
  `r,g,b`) and writes the same colors plus `[General] ColorScheme=kosm` as a block at the end
  of `~/.config/kdeglobals`, since KDE apps outside Plasma read kdeglobals, not the scheme.
  KConfig takes a key's last value (checked with `kreadconfig6`), so the block overrides
  Ricer's values above it. A KDE settings page saving kdeglobals drops the markers but keeps
  the values; the next apply then appends a fresh block.
- How to check: apply, then open a libadwaita app (Nautilus, Settings), a GTK 3 app with
  adw-gtk3, and a KDE app (Dolphin, Kate).
- Both are in Krystallos (`gtk.from(theme)`, `kde.from(theme)` straight from the package) and
  in `kosm init`'s list.

## 13n. Blender

- `kosm_blender` generates `~/.config/blender/5.2/scripts/presets/interface_theme/kosm.xml`
  with `kosm_xml`: the interface colors, 21 widget kinds, 18 editors' generic colors and the
  shared regions (Blender 5's layout). Blender resets the theme before loading a preset, so
  everything else is its default. Blender only loads presets whose element types are on its
  whitelist, so the types are Blender's own.
- Checked in a headless Blender 5.2 with a temp home and `--factory-startup`: the preset runs
  and the colors land (panel, widgets, properties, the 3D view's single color, channels).
- The version folder (`5.2`) is in the default `file`; a Blender update means changing it.
- In Krystallos and `kosm init`'s list.

## 13o. The base kosmos (decided without a plan from you)

- It ships as a package, `kosm_base`, not with kosm: core may not know apps, and it is an
  ordinary package like anyone's (DESIGN.md now says so). `kosm init` lists it.
- `base.from(theme, fonts)` returns `Base`: one optional field per official app (22), each the
  package's `from(theme)` plus the fonts. `fonts` is `.{ .families, .size }` and comptime, so
  the base can build foot's font list and Hyprland's Pango string without memory. A kosmos
  returns the `Base` after plain assignments (`apps.kitty.?.fonts.font_size = 14`), drops an app
  with `apps.cs2 = null`, and adds its own apps by returning `struct { base: base.Base, ... }`.
  Variants stay a function call: call the base kosmos' function, assign the tweaks.
- The base keeps every app on. Apps that edit a program's own file fail when it is missing
  (naming app and file), so a user without the program sets it to null. The alternative,
  leaving those apps off in the base, would make "every supported app" untrue; your call.
- The test in `kosm_base` gives a temp home the files edit-based apps need, then applies a
  kosmos of a palette and two overrides: all 21 apps plan their files.
- The starting kosmos `kosm init` writes (`kosmoi/kyanos.zig`) is now that: a palette, the
  base, two overrides, and the eight apps that need their program set to null.
- Krystallos is rewritten on the base: `root.zig` returns `base.Base`, each app file is a
  `tweak(app, ...)` of the base's app, and `fontconfig.zig`, `qtct.zig`, `cs16.zig`, `cs2.zig`,
  `hyprmouse.zig` are gone (the base covers them; the Steam paths and hyprmouse's opacity are
  three lines in root.zig). Hyprland is still built whole by `hyprland.zig`. Dark Reader and
  oh-my-posh are null, as before. `--diff` gives the same 26 files with the same bytes, only
  in the base's (alphabetical) order. The old files are in your dotfiles' git history.
- Equibop's tweak starts over from `from` with the translucent theme, as before, keeping the
  base's font.
