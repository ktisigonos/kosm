# Upstream bugs

Bugs found in dependencies, to report to their projects. Group them under `## <package> (<owner>/<repo>)`, each with a repro and the workaround in use. Tick an item once it is reported or fixed upstream.

## darkreader (darkreader/darkreader)

- [ ] `DarkReader.enable(theme)` on a page where it is already enabled keeps the old colors: enable with `darkSchemeBackgroundColor: "#102030"`, then enable again with `"#aa0000"`; the page stays `#102030` (npm package 4.9.135, no fixes passed). Workaround in `kosm_firefox`: `DarkReader.disable()` before every `enable`.

## beautyline (garuda-linux/themes-and-settings/artwork/beautyline on GitLab)

- [ ] 23 symlinks point into the author's home (`actions/scalable/dialog-transform.svg` -> `/home/troupal/Images/BeautyLine/actions/scalable/transform-scale.svg`, at commit `07e3736`), so they are broken on every install. Find them with `find . -type l -lname '/home/*'`. Workaround: none; `kosm_icons` keeps them as broken links, as an installed BeautyLine has them.
