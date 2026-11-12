# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

- **13a. Kosm's packages in their own repositories**
  - Do: the code is done and each package is a repository beside kosm (`~/Projects/Zig/ktisigonos/kosm_<name>`), pinning kosm and its adapter packages by url. What is left is the human's: create a repository per package on the forge and push kosm and each package (`REVIEW.md` has the commands), `kosm_glsl` included.
  - Do: when `kosm_json` next pins kosm, drop its tests of clip warnings (`context.clipped`, the `outside sRGB` warning).
  - Done when: `zig build test -Dnetwork` passes: a config `kosm init` makes from the real repositories diffs the starting kosmos for kitty, ghostty, Hyprland, Zen and nvim.

- **13l. CS2's fonts.conf** (waits on the human)
  - Do: the game's `fonts.conf` is stock again (Ricer's "Custom fonts" section is gone, likely restored by Steam) and `kosm_counter_strike_2` writes `42-repl-global.conf`, which that file says still applies. Left: the human checks the font in game; if it shows, delete this step, otherwise the human describes the cleanup still needed.
  - Done when: the human has seen the font in game, or the described cleanup is tested without touching the game's real files.

- **13m. Kosm's own GTK and KDE themes** (waits on the human)
  - Do: `kosm_gtk` (libadwaita's color variables in GTK 4's gtk.css, `@define-color` names for adw-gtk3 in GTK 3's) and `kosm_kde` (a `.colors` scheme and a kdeglobals block) are done and in Krystallos. Left: the human checks them in real apps (`REVIEW.md` says how), Decided: GTK 3 apps move from Oomox to adw-gtk3; `kosm_gtk`'s README lists `adw-gtk-theme` (Arch package) as an optional dependency for GTK 3 (its GTK 3 colors need it), and re-pin the base and the config afterwards.
  - Done when: the human has seen libadwaita, adw-gtk3 and KDE apps take the colors.

- **13n. Blender theme** (waits on the human)
  - Do: `kosm_blender` is done and in Krystallos; the preset loads in a headless Blender 5.2 with every color applied. Left: the human picks it in Blender and checks it looks right.
  - Done when: the human has seen the theme in Blender.

- **13p. Drop qt6ct and qt5ct** `ASK`
  - Do: nwg-look is replaced (`kosm_gtk` writes GTK's settings files and sets gsettings) and Kvantum is not installed. Left: the human uninstalls nwg-look and deletes `~/.config/Kvantum`; then decide qt6ct/qt5ct: `QT_QPA_PLATFORMTHEME=kde` (plasma-integration, installed) reads colors, fonts, icons, style and single-click from kdeglobals, which `kosm_kde` would gain fields for; the tooltip qss is lost, and Qt 5 apps need `plasma5-integration` or keep qt5ct.
  - Do: Krystallos' Hyprland app sets the `GTK_THEME` environment variable (or leaves it unset) instead of the hand-written `defs.lua`.
  - Do: the human's Flatpak overrides (`flatpak override --user --show`, and the system-wide one) still set `QT_QPA_PLATFORMTHEME=qt6ct`, `QT_STYLE_OVERRIDE=breeze` and Kvantum access; settle them with qt6ct/qt5ct.
  - Done when: the human has agreed whether qt6ct and qt5ct go, and their settings come from kosm instead.

- **13q. Live reload for Qt and KDE apps** `ASK`
  - Do: find out whether running Qt/KDE apps can pick up new colors without a restart (e.g. KDE's `kdeglobals` change notification over D-Bus, `plasma-apply-colorscheme`, qt5ct/qt6ct watching their files), and whether it works outside Plasma on Hyprland. `kosm_kde` and `kosm_qtct` are the packages it affects: they write `kdeglobals`, `kosm.colors` and the qtct color files. Propose a reloader for them if one works.
  - Done when: the human has a short answer on what reloads and how, and has chosen whether `kosm_kde` and `kosm_qtct` gain a reloader.

- **13r. Icons generated from the palette** `ASK` `PLAN FIRST`
  - Do: an app (`kosm_icons`) that generates an icon theme from the theme's colors, so icons follow the kosmos like everything else. The official base set is a minimalistic SVG icon theme, recolored; the human picks which one (license must allow modified copies). Propose how the recoloring works (which SVG colors map to which palette colors), where the theme is written (`~/.local/share/icons/<name>`), and any dependency, then wire its name into `kosm_gtk`'s `gtk_icon_theme_name` and `kosm_kde`'s icons.
  - Done when: the human has picked the icon set and seen apps use the generated theme in the kosmos' colors.

- **13s. Cursors generated from the palette** `ASK` `PLAN FIRST`
  - Do: an app (`kosm_cursor`) that builds a cursor theme (XCursor, and hyprcursor) in the theme's colors. Default: Bibata Modern Ice's SVG sources recolored (fill, outline, shadow from the palette). Later maybe a cursor of kosm's own. Make it easy for users to rice their own cursors: their own SVGs, colors and size as plain fields. Propose how SVGs become cursors (rendering and the XCursor/hyprcursor formats, written ourselves or a dependency), where the theme is written, and how `kosm_gtk`'s cursor settings and Hyprland's `XCURSOR_*`/`HYPRCURSOR_*` pick it up.
  - Done when: the human has seen the generated cursor in GTK, Qt and Hyprland, in the kosmos' colors.

- **13u. Flatpak GTK apps** (waits on the human)
  - Do: Flatpak apps still load the old theme: the human's Flatpak overrides set `GTK_THEME` (`oomox-Ricer` per user, `Nordic-darker-v40` system-wide), so libadwaita Flatpaks (Blanket) get Oomox drawn over them and plain GTK 4 ones (Nicotine+) draw Oomox. Without it, Flatpaks take the theme name kosm sets in gsettings, but see themes only in `~/.local/share/themes` (not `/usr/share/themes`), so plain GTK 4 Flatpaks need adw-gtk3 there; with it they follow kosm's colors (checked off-screen with a plain GTK 4 window). Setting `GTK_THEME=adw-gtk3-dark` instead would also force adw-gtk3's copy of libadwaita's stylesheet over every libadwaita app's own. Left: the human unsets `GTK_THEME` (`flatpak override --user --unset-env=GTK_THEME`) and makes adw-gtk3 visible to Flatpaks (a copy in `~/.local/share/themes`, which pacman does not update); then decide whether `kosm_gtk` keeps that copy current or unsets the override itself, after an apply.
  - Done when: Nicotine+ and Blanket take kosm's colors like native GTK apps.

- **13v. Blender theme on start and live** (waits on the human)
  - Do: `kosm_blender` writes the preset and a startup script (`startup_script`, `scripts/startup/kosm.py`) into every Blender version that has run (`~/.config/blender/<version>`, found by the files in its `config` folder); the script loads the preset when Blender starts and checks its modification time every `reload_interval` (0.25 s, one file status call) to reload it after an apply, then redraws every area. Checked in a headless Blender 5.2: the script registers its timer, loads the preset, and reloads a changed one. Left: the human applies, restarts Blender and sees the kosm theme without picking it, then applies a change with Blender open and sees it recolor.
  - Done when: the human has seen both in a real Blender.

- **13w. Commet theme** `ASK`
  - Do: find out how Commet (commet.chat, a Matrix client) reads its colors (a theme or config file, its format, live reload) and propose `kosm_commet` from it, with its fields and the Krystallos values.
  - Done when: the human has agreed on the app, and Commet takes the kosmos' colors.

- **14c. Looks and shared values in the base** `PLAN FIRST`
  - Do: `kosm_base.Look` (theme, fonts, shared values, an optional tweak of `Base`) and `kosm_base.Values`: the settings several official apps share (border size, rounding, rounding power, gaps, padding, shadow, cursor, icon theme, keyboard layouts), each read by every app having it. `from(look, apps)` replaces `from(theme, fonts, apps)` and runs the tweak last. The default look is literal (pure black, white and hues, rounding 0); personal settings (shaders, keyboard layouts, editor) are null. Propose the field list first.
  - Do: the starting kosmos `kosm init` makes uses the new `from`.
  - Done when: tests show a value of `Values` reaching every app having that setting, the tweak running after `from`, and a user base holding `Base` beside an added app taking the look's accent.

- **14d. Krystallos as a look** `ASK`
  - Do: in the human's config, on the human's request: Krystallos exports a `kosm_base.Look` (its palette, roles, fonts, values, and a tweak with only its app-specific changes); `colors.zig` becomes roles; its personal settings move out to 14f.
  - Done when: a kosmos of Krystallos' look plus 14f's personal settings diffs the same as today's Krystallos.

- **14e. Everforest look** `ASK`
  - Do: in the human's config, on the human's request: an Everforest look (its published palette, green accent), proving a second look needs only values.
  - Done when: a kosmos switching Krystallos' look for Everforest's diffs every app in Everforest's colors.

- **14f. The human's personal kosmos** `ASK`
  - Do: in the human's config, on the human's request: a kosmos using Krystallos' look on the official base (or a base of the human's own), setting only the personal settings (Ghostty shader, keyboard layouts, editor, Steam library, Hyprland's layout).
  - Done when: it diffs the same as today's Krystallos.
