# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

- **13a. Kosm's packages in their own repositories**
  - Do: the code is done and each package is a repository beside kosm (`~/Projects/Zig/ktisigonos/kosm_<name>`), pinning kosm and its adapter packages by url. What is left is the human's: create a repository per package on the forge and push kosm and each package (`REVIEW.md` has the commands), `kosm_glsl` included.
  - Do: when `kosm_kitty` and `kosm_json` next pin kosm, drop their tests of clip warnings (`context.clipped`, the `outside sRGB` warning), and the "so a clipped color warns" line in kitty's and ghostty's `Joined.zig`.
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

- **13p. Drop nwg-look, maybe qt6ct and Kvantum** `ASK`
  - Do: list what nwg-look, qt6ct/qt5ct and Kvantum still set on the human's system (GTK theme, icons, cursor, fonts in `settings.ini` and gsettings; Qt's style, palette, fonts and icons) and which of it `kosm_gtk` and `kosm_kde` could write themselves, so those tools are no longer needed. Name what cannot be replaced (e.g. a Qt style plugin, or gsettings not being a file) and propose the change before building it.
  - Done when: the human has agreed which tools go, and their settings come from kosm instead.

- **13q. Live reload for Qt and KDE apps** `ASK`
  - Do: find out whether running Qt/KDE apps can pick up new colors without a restart (e.g. KDE's `kdeglobals` change notification over D-Bus, `plasma-apply-colorscheme`, qt5ct/qt6ct watching their files), and whether it works outside Plasma on Hyprland. `kosm_kde` and `kosm_qtct` are the packages it affects: they write `kdeglobals`, `kosm.colors` and the qtct color files. Propose a reloader for them if one works.
  - Done when: the human has a short answer on what reloads and how, and has chosen whether `kosm_kde` and `kosm_qtct` gain a reloader.
