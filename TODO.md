# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

- **13a. Kosm's packages in their own repositories**
  - Do: the code is done and each package is a repository beside kosm (`~/Projects/Zig/ktisigonos/kosm_<name>`), pinning kosm and its adapter packages by url. What is left is the human's: create a repository per package on the forge and push kosm and each package (`REVIEW.md` has the commands).
  - Done when: `zig build test -Dnetwork` passes: a config `kosm init` makes from the real repositories diffs the starting kosmos for kitty, ghostty, Hyprland, Zen and nvim.

- **13l. CS2's fonts.conf** `ASK`
  - Do: CS2's panorama `fonts.conf` keeps the "Custom fonts" section Ricer's template added; the human describes the exact cleanup (which of the game's font fields to remove, or none now that `kosm_counter_strike_2` writes `42-repl-global.conf`), and the plan says whether it runs as the app's `reload` or as edits kosm makes itself (which needs an XML parser for `kosm_xml`).
  - Done when: the cleanup is tested without touching the game's real files.

- **13m. Kosm's own GTK and KDE themes** (waits on the human)
  - Do: `kosm_gtk` (libadwaita's color variables in GTK 4's gtk.css, `@define-color` names for adw-gtk3 in GTK 3's) and `kosm_kde` (a `.colors` scheme and a kdeglobals block) are done and in Krystallos. Left: the human checks them in real apps (`REVIEW.md` says how), Decided: GTK 3 apps move from Oomox to adw-gtk3; `kosm_gtk`'s README lists `adw-gtk-theme` (Arch package) as an optional dependency for GTK 3 (its GTK 3 colors need it), and re-pin the base and the config afterwards.
  - Done when: the human has seen libadwaita, adw-gtk3 and KDE apps take the colors.

- **13n. Blender theme** (waits on the human)
  - Do: `kosm_blender` is done and in Krystallos; the preset loads in a headless Blender 5.2 with every color applied. Left: the human picks it in Blender and checks it looks right.
  - Done when: the human has seen the theme in Blender.

- **13q. The kosmos' name in apps** (plan agreed with the human)
  - Do: core: `Theme.name: ?[]const u8 = null`, the name programs show ("Krystallos"); null takes the name kosm applies the kosmos under (`krystallos`, `krystallos.dark`). `Theme.files: Files = .shared`, a global switch: `.shared` writes `kosm.<ext>` for every kosmos, `.per_kosmos` writes `<kosmos name>.<ext>` (always the lowercase name kosm applies it under, never the display name). `Output.kosmos`, set by the runner, plus helpers on Output: the display name, and filling a `{name}` placeholder in an app's file path from the switch.
  - Do: apps whose files a program picks by name implement it: KDE (`{name}.colors`, the scheme's `Name`, kdeglobals' `ColorScheme`), Blender (`{name}.xml`), Vicinae (`themes/{name}.toml`, its `name`, the selection in settings.json), tuios (`themes/{name}.json`, `id`, `display_name`, the selection in config.toml), qt5ct/qt6ct (`colors/{name}.conf`, `color_scheme_path`). Files a program must include stay `kosm` whatever the switch (Hyprland's kosm.lua, kitty, ghostty, Zen, nvim, the GTK, Equibop and AdwSteamGtk blocks).
  - Do: Krystallos sets `theme.name = "Krystallos"`; DESIGN.md gets one line on the name and the switch; READMEs of the five apps say what the switch does; re-pin kosm, the five apps, the base and `~/.config/kosm` (bottom-up; `REVIEW.md` "Where things are" says how pins work).
  - Done when: tests show each of the five apps writing `kosm.*` with `.shared` and `<kosmos>.*` with `.per_kosmos`, the display name from `Theme.name` and the fallback to the kosmos name, and Krystallos' `--diff` changes only those names.
