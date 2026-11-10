# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

- **13a. Kosm's packages in their own repositories**
  - Do: the code is done and each package is a repository beside kosm (`~/Projects/Zig/kosm_<name>`), pinning kosm and its adapter packages by url. What is left is the human's: create a repository per package on the forge and push kosm and each package (`REVIEW.md` has the commands).
  - Done when: `zig build test -Dnetwork` passes: a config `kosm init` makes from the real repositories diffs the starting kosmos for kitty, ghostty, Hyprland, Zen and nvim.

- **13i. Browser extensions and Zen mods** `PLAN FIRST`
  - Do: apps for Firefox extensions and Zen mods the human uses: Dark Reader (theme colors), Stylus (user styles, mainly the font) and the Zen mod Zen Zero (the browser's background). The plan finds where each keeps its settings (extension storage in the profile, a mod's prefs or CSS) and how kosm can write them, and says if one can't be written safely.
  - Done when: each app writes its settings in a temp profile, and a profile missing the extension or mod is skipped or fails as the plan decides.

- **13j. `kosm_fontconfig`** `PLAN FIRST`
  - Do: a fontconfig app setting the families `sans-serif`, `serif` and `monospace` prefer, each a list of fonts in fallback order (so a kosmos' fallback fonts reach every program using fontconfig, kitty included). It writes its own file the user's config reads (`~/.config/fontconfig/conf.d/`) rather than `fonts.conf`. The plan settles `generate` with an XML adapter (hand-written or a grammar, hard rule 5) against a `template`, and whether more fontconfig settings (hinting, antialiasing) are fields now.
  - Done when: tests show the generated file in fontconfig's format with each family's fallbacks in order, and a family left null not written.

- **13k. Apps for the rest of Ricer's list, on existing adapters** `PLAN FIRST`
  - Do: apps for programs whose formats kosm already reads: oh-my-posh and tuios (JSON), Vicinae (TOML), Dunst, qt5ct/qt6ct colors and foot (INI), Equibop's QuickCSS for Material Discord and AdwSteamGtk (CSS). The plan orders them and says which `generate` a file the program includes and which edit the program's own file.
  - Done when: each app writes Krystallos' colors and fonts in a temp directory, and Krystallos rices them with `--diff` against the human's files.

- **13l. Apps needing new formats** `PLAN FIRST` `ASK`
  - Do: hyprtoolkit and hyprmouse (hyprlang), the Zen logo (SVG), Counter-Strike 1.6's `TrackerScheme.res` (Valve KeyValues) and CS2's panorama `fonts.conf` and `42-repl-global.conf` (fontconfig XML, shared with 13j). The plan proposes an adapter, a template or a `block` for each (a grammar is a dependency).
  - Do: CS2's fonts also need the cleanup Ricer's setup did by hand (removing the game's other font fields); the human describes the exact commands, and the plan says whether they run as the app's `reload` or as edits kosm makes itself.
  - Done when: each app writes its file in a temp directory, and the CS2 cleanup is tested without touching the game's real files.

- **13m. Kosm's own GTK and KDE themes** `PLAN FIRST` `ASK`
  - Do: generate a GTK theme (GTK 3 and 4 CSS, replacing Oomox) and KDE colors (`kdeglobals` and a `.colors` scheme) from the theme, so no outside theme tool is needed. The plan scopes what a minimal theme must cover and where it is installed.
  - Done when: the generated themes load in a temp `XDG_DATA_HOME` (checked by the human) and are tested for each color they set.

- **13n. Blender theme** `PLAN FIRST`
  - Do: a Blender app writing a theme preset (Blender's XML theme format) from the theme.
  - Done when: the preset is generated in a temp directory and loads in Blender (checked by the human).

- **13o. The base kosmos** `PLAN FIRST` `ASK`
  - Do: one official kosmos holding every officially supported app with sane defaults, that a user's kosmos builds on: set its palette and fonts, override single values, add or drop apps. The plan proposes how a kosmos builds on another (a function taking the theme and returning the base's apps, as variants do), where it ships (with kosm or as a package, 13a) and how it relates to the starting kosmos `kosm init` writes. Krystallos becomes a kosmos on top of it.
  - Done when: a kosmos holding only a palette and two overrides rices every supported app through the base, and Krystallos is rewritten on top of it with the same `--diff` output.
