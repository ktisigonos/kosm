# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

- **18d. wlr-which-key colors and font** (waits on the human)
  - Do: wlr-which-key's `~/.config/wlr-which-key/config.yaml` is YAML; kosm edits only its style keys (`font`, `background`, `color`, `border`, `border_width`, `corner_r`) and leaves the menu alone. Needs a `kosm_yaml` adapter on the tree-sitter YAML grammar (`tree-sitter-grammars/tree-sitter-yaml`), which the human has approved. Do not start until the human says so: their git server is down, so the new package cannot be pushed.
  - Done when: an apply sets wlr-which-key's colors and font.


- **18e. Neovim highlight groups from kosm**
  - Do: `kosm_nvim` writes the highlight groups itself (editor UI, Treesitter, LSP, diagnostics) from the theme's roles and code colors, instead of base16 slots for the `nvim-base16` plugin; the human's `nvim/lua/config/colors.lua` then loads them and drops base16 and its overrides. Propose the groups and the module's shape first.
  - Done when: the human's Neovim shows kosm's colors without nvim-base16.


- **18g. A kosmos from an image** `ASK` `PLAN FIRST`
  - Do: like pywal: `kosm new kosmos <name>` takes an image and writes the usual kosmos scaffold with a palette taken from it (black and white from its darkest and lightest colors, each hue from the image's colors nearest it on the wheel, hues it lacks left out to be mixed), and the image as the wallpaper. Decoding PNG, JPEG and JPEG XL needs libraries: propose them (or which formats to write ourselves) and the command's flags first.
  - Done when: the human has approved the decoders, and a kosmos made from one of their wallpapers builds and applies with colors that match the image.


- **13a. Kosm's packages in their own repositories**
  - Do: the code is done and each package is a repository beside kosm (`~/Projects/Zig/ktisigonos/kosm_<name>`), pinning kosm and its adapter packages by url. What is left is the human's: create a repository per package on the forge and push kosm and each package (`REVIEW.md` has the commands), `kosm_glsl` included.
  - Do: when `kosm_json` next pins kosm, drop its tests of clip warnings (`context.clipped`, the `outside sRGB` warning).
  - Done when: `zig build test -Dnetwork` passes: a config `kosm init` makes from the real repositories diffs the starting kosmos for kitty, ghostty, Hyprland, Zen and nvim.


- **13l. CS2's fonts.conf** (waits on the human)
  - Do: the game's `fonts.conf` is stock again (Ricer's "Custom fonts" section is gone, likely restored by Steam) and `kosm_counter_strike_2` writes `42-repl-global.conf`, which that file says still applies. Left: the human checks the font in game; if it shows, delete this step, otherwise the human describes the cleanup still needed.
  - Done when: the human has seen the font in game, or the described cleanup is tested without touching the game's real files.


- **13p. Drop qt6ct and qt5ct** `ASK`
  - Do: nwg-look is replaced (`kosm_gtk` writes GTK's settings files and sets gsettings) and Kvantum is not installed. Left: the human uninstalls nwg-look and deletes `~/.config/Kvantum`; then decide qt6ct/qt5ct: `QT_QPA_PLATFORMTHEME=kde` (plasma-integration, installed) reads colors, fonts, icons, style and single-click from kdeglobals, which `kosm_kde` would gain fields for; the tooltip qss is lost, and Qt 5 apps need `plasma5-integration` or keep qt5ct.
  - Do: Krystallos' Hyprland app sets the `GTK_THEME` environment variable (or leaves it unset) instead of the hand-written `defs.lua`.
  - Do: the human's Flatpak overrides (`flatpak override --user --show`, and the system-wide one) still set `QT_QPA_PLATFORMTHEME=qt6ct`, `QT_STYLE_OVERRIDE=breeze` and Kvantum access; settle them with qt6ct/qt5ct.
  - Done when: the human has agreed whether qt6ct and qt5ct go, and their settings come from kosm instead.


- **13q. Live reload for Qt and KDE apps** `ASK`
  - Do: find out whether running Qt/KDE apps can pick up new colors without a restart (e.g. KDE's `kdeglobals` change notification over D-Bus, `plasma-apply-colorscheme`, qt5ct/qt6ct watching their files), and whether it works outside Plasma on Hyprland. `kosm_kde` and `kosm_qtct` are the packages it affects: they write `kdeglobals`, `kosm.colors` and the qtct color files. Propose a reloader for them if one works.
  - Done when: the human has a short answer on what reloads and how, and has chosen whether `kosm_kde` and `kosm_qtct` gain a reloader.


- **13x. Lists built from run-time values** `ASK`
  - Do: a list field (`Recolor.colors.only`, but also keyboard layouts, font families and any other `[]const`) set inside a function to `&.{ ... }` of run-time values points into that function's stack, which is reused once it returns: the app later reads garbage, silently (icons came out white instead of black). Zig cannot avoid the `&`: checked on 0.17, `[N]?Color` wants exactly N elements, tuple fields cannot default to run-time null, and a struct with numbered fields does not take list syntax; an `anytype` helper breaks the user-facing rules. `kosm.hex` is inline, so lists of hex colors are constants already. Run-time values remain: the theme handed to a look's `tweak` or to a kosmos' own functions (known at compile time unless `Params`/`--set` change it, which rules out evaluating the whole kosmos at compile time), and `Params` themselves. Options to weigh: pass the theme as `comptime` where it is known, so `&.{ theme.palette.blue }` is constant (the config's `personal/icons.zig` does this already: `wearing` hands its icon functions `comptime theme`; a look's `tweak` cannot, as `Look.tweak` is a run-time function pointer); have kosm copy every slice of the app tree into its arena right after the kosmos function returns (too late: the frames are gone, so this only works if the kosmos builds everything in one frame); a `.of(&.{ ... })` copy into a fixed buffer per list field; or document the rule ("lists of run-time values are top-level constants") in kosm_icons' README and the kosmos docs. Ask the human which.
  - Done when: writing `.only = &.{ theme.palette.blue }` in a look's tweak or a kosmos function either works or cannot compile, and the human has seen the chosen form.


- **13s. Cursors generated from the palette** `ASK` `PLAN FIRST`
  - Do: an app (`kosm_cursor`) that builds a cursor theme (XCursor, and hyprcursor) in the theme's colors. Default: Bibata Modern Ice's SVG sources recolored (fill, outline, shadow from the palette). Later maybe a cursor of kosm's own. Make it easy for users to rice their own cursors: their own SVGs, colors and size as plain fields. Propose how SVGs become cursors (rendering and the XCursor/hyprcursor formats, written ourselves or a dependency), where the theme is written, and how `kosm_gtk`'s cursor settings and Hyprland's `XCURSOR_*`/`HYPRCURSOR_*` pick it up.
  - Done when: the human has seen the generated cursor in GTK, Qt and Hyprland, in the kosmos' colors.


- **13u. Flatpak GTK apps** (waits on the human)
  - Do: Flatpak apps still load the old theme: the human's Flatpak overrides set `GTK_THEME` (`oomox-Ricer` per user, `Nordic-darker-v40` system-wide), so libadwaita Flatpaks (Blanket) get Oomox drawn over them and plain GTK 4 ones (Nicotine+) draw Oomox. Without it, Flatpaks take the theme name kosm sets in gsettings, but see themes only in `~/.local/share/themes` (not `/usr/share/themes`), so plain GTK 4 Flatpaks need adw-gtk3 there; with it they follow kosm's colors (checked off-screen with a plain GTK 4 window). Setting `GTK_THEME=adw-gtk3-dark` instead would also force adw-gtk3's copy of libadwaita's stylesheet over every libadwaita app's own. Left: the human unsets `GTK_THEME` (`flatpak override --user --unset-env=GTK_THEME`) and makes adw-gtk3 visible to Flatpaks (a copy in `~/.local/share/themes`, which pacman does not update); then decide whether `kosm_gtk` keeps that copy current or unsets the override itself, after an apply.
  - Done when: Nicotine+ and Blanket take kosm's colors like native GTK apps.


- **13w. Commet theme** `ASK`
  - Do: find out how Commet (commet.chat, a Matrix client) reads its colors (a theme or config file, its format, live reload) and propose `kosm_commet` from it, with its fields and the Krystallos values.
  - Done when: the human has agreed on the app, and Commet takes the kosmos' colors.


- **19. COSMIC desktop** `ASK` (down the line)
  - Do: find out how COSMIC reads its theme, icons, fonts and settings (its RON files under `~/.config/cosmic`, live reload) and propose `kosm_cosmic` from it, with its fields and the Krystallos values; it reads `kosm_icons`' theme like GTK and KDE.
  - Done when: the human has agreed on the app, and COSMIC takes the kosmos' colors and icons.


- **18a. Zen's new tab page in the theme** `PLAN FIRST` (backlog: the human does not use it)
  - Do: the new tab page (Firefox's built-in `about:newtab`) is a page, which Zen mods cannot style: only the profile's `userContent.css` reaches it. `kosm_zen` writes its own stylesheet into each profile's `chrome` folder: the page transparent, its search box in `--kosm-button`, and Zen's logo replaced by the `logo` app's SVG; the human's `userContent.css` imports it. Propose the file, the import and how a missing import is reported first; drop the step if it makes setup harder for users.
  - Done when: on the human's machine the new tab page shows the window's background, a themed search box and the themed logo.
