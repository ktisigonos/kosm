# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

- **13a. Kosm's packages in their own repositories**
  - Do: the code is done and each package is a repository beside kosm (`~/Projects/Zig/ktisigonos/kosm_<name>`), pinning kosm and its adapter packages by url. What is left is the human's: create a repository per package on the forge and push kosm and each package (`REVIEW.md` has the commands).
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

- **13r. Customizable shaders** `PLAN FIRST`
  - Do: a kosmos can set the values a shader exposes, so its colors follow the theme. Example: ghostty's `custom-shader` runs `cursor_warp.glsl` (ghostty-cursor-shaders), whose `TRAIL_COLOR` (a `vec4` near the top of the file) cannot be set from kosm today, so the trail can't be made to match the cursor. Decided: kosm edits a shader's values in place through a GLSL adapter on the tree-sitter-glsl grammar, in a package of its own (not `kosm_ghostty`), so Hyprland's and other programs' shaders can use it too. First get the grammar approved as a dependency, then plan the package (names, which shaders and values).
  - Done when: a kosmos sets the trail color of `cursor_warp.glsl` and `--diff` shows only that value changing; the edit is tested on a copy of the shader in a temporary directory.
