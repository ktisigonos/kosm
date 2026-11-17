# Upstream bugs

Bugs found in dependencies, to report to their projects. Group them under `## <package> (<owner>/<repo>)`, each with a repro and the workaround in use. Tick an item once it is reported or fixed upstream.

## darkreader (darkreader/darkreader)

- [ ] `DarkReader.enable(theme)` on a page where it is already enabled keeps the old colors: enable with `darkSchemeBackgroundColor: "#102030"`, then enable again with `"#aa0000"`; the page stays `#102030` (npm package 4.9.135, no fixes passed). Workaround in `kosm_firefox`: `DarkReader.disable()` before every `enable`.

## beautyline (garuda-linux/themes-and-settings/artwork/beautyline on GitLab)

- [ ] 23 symlinks point into the author's home (`actions/scalable/dialog-transform.svg` -> `/home/troupal/Images/BeautyLine/actions/scalable/transform-scale.svg`, at commit `07e3736`), so they are broken on every install. Find them with `find . -type l -lname '/home/*'`. Workaround: none; `kosm_icons` keeps them as broken links, as an installed BeautyLine has them.

## vicinae (vicinaehq/vicinae)

- [ ] The icon theme picker lists themes by their `Name=` and saves that as `icon_theme`, but `QIcon::setThemeName` looks themes up by folder name: a theme in `~/.local/share/icons/kosm` with `Name=Everforest` is listed as "Everforest", and picking it sets `"icon_theme": "Everforest"`, which finds nothing (v0.30.0, `IconThemeDatabase::scan` in `src/server/src/internal/icon-theme-db/icon-theme-db.cpp`). The list is also scanned once per server, so themes added later are missing until a restart. Workaround in `kosm_vicinae`: `icon_theme` is set to the folder name in the settings, and the server is restarted after an apply.
- [ ] A running server never shows an icon theme's changed files: setting the same `icon_theme` again does nothing (Qt's `QIconLoader` keeps the theme it read, and vicinae's image cache keys icons by theme name), so a theme regenerated under the same name needs `vicinae server --replace` (v0.30.0). Workaround in `kosm_vicinae`: the restart after an apply.

## commet (commetchat/commet)

- [ ] A custom theme keeps the base theme's colors wherever Flutter derives them from the color scheme: `ThemeJsonConverter.fromJson` (`tiamat/lib/config/style/theme_json_converter.dart`) returns `defaultTheme.copyWith(colorScheme: ...)`, which swaps the scheme but leaves what `ThemeBase.theme(scheme)` computed from the old one: `canvasColor`, `iconTheme`, `dividerTheme`, `dividerColor`, the slider's track and the bottom sheet's background. With `"base": "dark"` and `"surface": "#ff041c26"`, space icons whose image has transparent corners still show Dark's `#2b2e31` behind them (an `ImageButton` with no `backgroundColor` paints `canvasColor`), at commit `5a87e83`. Fix: build the theme with `ThemeBase.theme(colorScheme)` and then apply the extensions. Workaround: none; a theme file cannot set these.

## dunst (dunst-project/dunst)

- [ ] `monitor = "DP-1"` logs `WARNING: 'DP-1': No digits found.` although naming a monitor is documented and works: `string_parse_maybe_int` (`src/option_parser.c`) tries the value as a number through `safe_string_to_int`, which warns, before keeping it as a name (v1.13.2). Workaround: none; the README says the warning is harmless.

## firefox (Bugzilla, Core: Graphics: WebRender)

- [ ] A `mask-image` on the chrome element holding the pages (Zen's `#tabbrowser-tabpanels`) is not applied to page elements with a `backdrop-filter`: they draw inside the masked-out area while the rest of the page is cut (Firefox 159.0.1 in Zen 1.24.1b, Linux Wayland, WebRender compositor blocklisted; seen on karasu.live and YouTube). Removing every `backdrop-filter` from the page fixes it; `clip-path: shape(...)` fails the same way, `clip-path: inset(...)` does not. A single-process test page (mask with a hole over a blurred div) does not reproduce it, so it seems to need the page in a content process. Not reduced further yet. Workaround: none; `kosm_zen` documents it on `CompactSidebar.Fill.xray`, and `.solid` avoids it.
