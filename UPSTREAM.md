# Upstream bugs

Bugs found in dependencies, to report to their projects. Group them under `## <package> (<owner>/<repo>)`, each with a repro and the workaround in use. Tick an item once it is reported or fixed upstream.

## darkreader (darkreader/darkreader)

- [ ] `DarkReader.enable(theme)` on a page where it is already enabled keeps the old colors: enable with `darkSchemeBackgroundColor: "#102030"`, then enable again with `"#aa0000"`; the page stays `#102030` (npm package 4.9.135, no fixes passed). Workaround in `kosm_firefox`: `DarkReader.disable()` before every `enable`.

## beautyline (garuda-linux/themes-and-settings/artwork/beautyline on GitLab)

- [ ] 23 symlinks point into the author's home (`actions/scalable/dialog-transform.svg` -> `/home/troupal/Images/BeautyLine/actions/scalable/transform-scale.svg`, at commit `07e3736`), so they are broken on every install. Find them with `find . -type l -lname '/home/*'`. Workaround: none; `kosm_icons` keeps them as broken links, as an installed BeautyLine has them.

## vicinae (vicinaehq/vicinae)

- [ ] The icon theme picker lists themes by their `Name=` and saves that as `icon_theme`, but `QIcon::setThemeName` looks themes up by folder name: a theme in `~/.local/share/icons/kosm` with `Name=Everforest` is listed as "Everforest", and picking it sets `"icon_theme": "Everforest"`, which finds nothing (v0.30.0, `IconThemeDatabase::scan` in `src/server/src/internal/icon-theme-db/icon-theme-db.cpp`). The list is also scanned once per server, so themes added later are missing until a restart. Workaround in `kosm_vicinae`: `icon_theme` is set to the folder name in the settings, and the server is restarted after an apply.
- [ ] A running server never shows an icon theme's changed files: setting the same `icon_theme` again does nothing (Qt's `QIconLoader` keeps the theme it read, and vicinae's image cache keys icons by theme name), so a theme regenerated under the same name needs `vicinae server --replace` (v0.30.0). Workaround in `kosm_vicinae`: the restart after an apply.
