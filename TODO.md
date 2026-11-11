# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

- **13a. Kosm's packages in their own repositories**
  - Do: the code is done and each package is a repository beside kosm (`~/Projects/Zig/kosm_<name>`), pinning kosm and its adapter packages by url. What is left is the human's: create a repository per package on the forge and push kosm and each package (`REVIEW.md` has the commands).
  - Done when: `zig build test -Dnetwork` passes: a config `kosm init` makes from the real repositories diffs the starting kosmos for kitty, ghostty, Hyprland, Zen and nvim.

- **13l. CS2's fonts.conf** `ASK`
  - Do: CS2's panorama `fonts.conf` keeps the "Custom fonts" section Ricer's template added; the human describes the exact cleanup (which of the game's font fields to remove, or none now that `kosm_cs2` writes `42-repl-global.conf`), and the plan says whether it runs as the app's `reload` or as edits kosm makes itself (which needs an XML parser for `kosm_xml`).
  - Done when: the cleanup is tested without touching the game's real files.

- **13m. Kosm's own GTK and KDE themes** (waits on the human)
  - Do: `kosm_gtk` (libadwaita's color variables in GTK 4's gtk.css, `@define-color` names for adw-gtk3 in GTK 3's) and `kosm_kde` (a `.colors` scheme and a kdeglobals block) are done and in Krystallos. Left: the human checks them in real apps (`REVIEW.md` says how), and says whether GTK 3 apps should move from the Oomox theme to adw-gtk3.
  - Done when: the human has seen libadwaita, adw-gtk3 and KDE apps take the colors.

- **13n. Blender theme** (waits on the human)
  - Do: `kosm_blender` is done and in Krystallos; the preset loads in a headless Blender 5.2 with every color applied. Left: the human picks it in Blender and checks it looks right.
  - Done when: the human has seen the theme in Blender.

- **13o. The base kosmos** `PLAN FIRST` `ASK`
  - Do: one official kosmos holding every officially supported app with sane defaults, that a user's kosmos builds on: set its palette and fonts, override single values, add or drop apps. The plan proposes how a kosmos builds on another (a function taking the theme and returning the base's apps, as variants do), where it ships (with kosm or as a package, 13a) and how it relates to the starting kosmos `kosm init` writes. Krystallos becomes a kosmos on top of it.
  - Done when: a kosmos holding only a palette and two overrides rices every supported app through the base, and Krystallos is rewritten on top of it with the same `--diff` output.
