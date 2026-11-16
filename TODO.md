# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

- **17a. Zen repaints after an apply** (waits on the human)
  - Do: done (`kosm_firefox` `0f81ec4`, not pushed: Kosm Live sets each Zen window's opacity to 0.999 for two frames a second after an apply changes prefs, so a page turning translucent is not left drawn opaque until a refocus). Left for the human: pin `kosm_firefox` to `0f81ec4` in the config (Zig's cache already holds it), apply, restart Zen once, then switch between an opaque and a translucent theme with Zen open. If it does not help, put the old pin `7f20d67` back and revert the commit. Once it works and the git server is back: push `kosm_firefox` and re-pin it in `kosm_base`.
  - Done when: going from an opaque to a translucent theme with Zen open shows the page translucent without refocusing.

- **18d. wlr-which-key colors and font** (waits on the human)
  - Do: wlr-which-key's `~/.config/wlr-which-key/config.yaml` is YAML; kosm edits only its style keys (`font`, `background`, `color`, `border`, `border_width`, `corner_r`) and leaves the menu alone. Needs a `kosm_yaml` adapter on the tree-sitter YAML grammar (`tree-sitter-grammars/tree-sitter-yaml`), which the human has approved. Do not start until the human says so: their git server is down, so the new package cannot be pushed.
  - Done when: an apply sets wlr-which-key's colors and font.


- **13w. Commet theme** (waits on the human)
  - Do: done (`kosm_commet` `168a4c9`, `kosm_base` `cc996b1`, `kosm_zen` `c3c8383`, none pushed; the config pins them already). Left for the human: create the `kosm_commet` repository and push it with `kosm_base` and `kosm_zen` once the git server is back; quit Commet, apply, start Commet.
  - Do: later, maybe: test whether a fully transparent `foundation` image with `glass` makes Commet's panels translucent.
  - Done when: Commet shows the kosmos' colors after a restart.


- **13z. A tertiary role** `ASK`
  - Do: apps wanting a third highlight (Commet's Material `tertiary`) take a fixed role, hardcoded in `kosm_commet`'s `from` (the warning role, as Commet's own Dark uses yellow); propose a theme-wide setting for it instead (a role beside `secondary`, or something else) and use it in every app that has such a color.
  - Done when: the human has agreed on the setting and `kosm_commet` reads it.


- **18h. Equibop theme** `ASK`
  - Do: find out how Equibop (the Vesktop-based Discord client) takes a theme (Vencord's QuickCSS or a CSS file in its themes folder, Discord's CSS variables, live reload) and propose `kosm_equibop` from it, with its fields and the Krystallos values.
  - Done when: the human has agreed on the app, and Equibop takes the kosmos' colors and fonts.


- **13q. A Qt style that looks right: Kvantum or our own** `ASK` `PLAN FIRST`
  - Do: Darkly is rejected (it looks wrong in many apps and misses colors). Already built: kosm `12c064d` (`hex8_argb`), `kosm_qtct` `dc481be` (`#aarrggbb` colors, `translucent` and `style` per program, alpha lowered for Darkly's double paint, a `touch -c` reload); the config pins these and `personal` sets qt6ct to Darkly and translucent until this step replaces it. Undo the double-paint lowering if the chosen style does not paint twice.
  - Do: give Kvantum an honest try: kosm generates a Kvantum theme (its `.kvconfig` and the `.svg` its colors live in) from the theme's roles, then compare it with the real apps (qt6ct, OpenRGB, Dolphin, KDE Connect, Mumble through Qt 5) in a headless KWin with screenshots over a checker backdrop. Weigh it against writing our own Qt style (a C++ QStyle plugin, or Zig behind a thin C++ shim) that draws from the platform palette, skips inner panel backgrounds so translucency is one layer, and reloads live. If our own style is less work for a result that works across the board, propose it instead. Also check whether COSMIC's way of styling Qt apps (step 19) can serve.
  - Found so far (headless KWin, real apps): Qt Widgets apps paint each container in the window color, so a translucent window color stacks into near-opaque layers; a stylesheet clearing inner backgrounds barely helped. Darkly paints the window twice on top of that. Bundled Kvantum themes at 50% opacity: Dolphin with KvantumAlt shows one clean see-through layer in its file view (sidebar and toolbar solid), qt6ct and OpenRGB only at the window edges with solid gray panels; Kvantum ignores the platform palette (colors come from the theme's SVG) and does not reload live. KDE Connect's window is QML (Kirigami), which neither style makes translucent; it shows a greenish tint from alpha on an opaque surface. KDE apps force Breeze unless kdeglobals' `[KDE] widgetStyle` names a style, and take their palette from `kosm_kde`'s scheme, so they recolor only on restart; under `QT_QPA_PLATFORMTHEME=kde` colors are live but fonts never reload outside Plasma (the KDE portal announces no setting changes there). Plain Qt apps recolor and change fonts live through qt6ct/qt5ct.
  - Left for the human: when the git server is back, push kosm and kosm_qtct and re-pin kosm_qtct in kosm_base.
  - Done when: the human has picked Kvantum or our own style from screenshots of their apps, and Qt and KDE apps wear it in the kosmos' colors.


- **19. COSMIC desktop and apps** `ASK`
  - Do: find out how COSMIC reads its theme, icons, fonts and settings (its RON files under `~/.config/cosmic`, live reload) and propose `kosm_cosmic` from it, with its fields and the Krystallos values; it reads `kosm_icons`' theme like GTK and KDE. Cover COSMIC's own apps (Files, Terminal, Edit and so on) run under Hyprland, and find out how COSMIC styles Qt apps and whether that works outside COSMIC, for step 13q.
  - Done when: the human has agreed on the app, and COSMIC and its apps take the kosmos' colors and icons, and step 13q knows whether COSMIC's Qt styling can serve.


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


- **13x. Lists built from run-time values** `ASK`
  - Do: a list field (`Recolor.colors.only`, but also keyboard layouts, font families and any other `[]const`) set inside a function to `&.{ ... }` of run-time values points into that function's stack, which is reused once it returns: the app later reads garbage, silently (icons came out white instead of black). Zig cannot avoid the `&`: checked on 0.17, `[N]?Color` wants exactly N elements, tuple fields cannot default to run-time null, and a struct with numbered fields does not take list syntax; an `anytype` helper breaks the user-facing rules. `kosm.hex` is inline, so lists of hex colors are constants already. Run-time values remain: the theme handed to a look's `tweak` or to a kosmos' own functions (known at compile time unless `Params`/`--set` change it, which rules out evaluating the whole kosmos at compile time), and `Params` themselves. Options to weigh: pass the theme as `comptime` where it is known, so `&.{ theme.palette.blue }` is constant (the config's `personal/icons.zig` does this already: `wearing` hands its icon functions `comptime theme`; a look's `tweak` cannot, as `Look.tweak` is a run-time function pointer); have kosm copy every slice of the app tree into its arena right after the kosmos function returns (too late: the frames are gone, so this only works if the kosmos builds everything in one frame); a `.of(&.{ ... })` copy into a fixed buffer per list field; or document the rule ("lists of run-time values are top-level constants") in kosm_icons' README and the kosmos docs. Ask the human which.
  - Done when: writing `.only = &.{ theme.palette.blue }` in a look's tweak or a kosmos function either works or cannot compile, and the human has seen the chosen form.


- **13y. `kosm install` for styles and themes apps need** `PLAN FIRST`
  - Do: `kosm install` (short `kosm i`) installs what an app needs to look as configured (styles, themes such as Darkly or adw-gtk3), never the programs themselves; it is optional, and users may install these by hand instead. Each app declares its needs, with a package name per distro (Arch first, Fedora later). A need in the distro's official repositories is installed with its package manager, showing the exact command and running it only once the user confirms; kosm never updates it, the package manager does. Otherwise kosm installs it per user (under `~/.local`, no root) from source pinned by commit and content hash, showing the install script before it runs; `kosm update` shows the new commits and the diff of the build and install files, and moves the pin only once the user accepts. Propose how apps declare needs, the per-distro names, the source build and where files go first.
  - Done when: the human has agreed on the plan, and `kosm install` installs Darkly on the human's machine the chosen way.

- **13s. Cursors generated from the palette** `ASK` `PLAN FIRST`
  - Do: an app (`kosm_cursor`) that builds a cursor theme (XCursor, and hyprcursor) in the theme's colors. Default: Bibata Modern Ice's SVG sources recolored (fill, outline, shadow from the palette). Later maybe a cursor of kosm's own. Make it easy for users to rice their own cursors: their own SVGs, colors and size as plain fields. Propose how SVGs become cursors (rendering and the XCursor/hyprcursor formats, written ourselves or a dependency), where the theme is written, and how `kosm_gtk`'s cursor settings and Hyprland's `XCURSOR_*`/`HYPRCURSOR_*` pick it up.
  - Done when: the human has seen the generated cursor in GTK, Qt and Hyprland, in the kosmos' colors.


- **13u. Flatpak GTK apps** (waits on the human)
  - Do: Flatpak apps still load the old theme: the human's Flatpak overrides set `GTK_THEME` (`oomox-Ricer` per user, `Nordic-darker-v40` system-wide), so libadwaita Flatpaks (Blanket) get Oomox drawn over them and plain GTK 4 ones (Nicotine+) draw Oomox. Without it, Flatpaks take the theme name kosm sets in gsettings, but see themes only in `~/.local/share/themes` (not `/usr/share/themes`), so plain GTK 4 Flatpaks need adw-gtk3 there; with it they follow kosm's colors (checked off-screen with a plain GTK 4 window). Setting `GTK_THEME=adw-gtk3-dark` instead would also force adw-gtk3's copy of libadwaita's stylesheet over every libadwaita app's own. Left: the human unsets `GTK_THEME` (`flatpak override --user --unset-env=GTK_THEME`) and makes adw-gtk3 visible to Flatpaks (a copy in `~/.local/share/themes`, which pacman does not update); then decide whether `kosm_gtk` keeps that copy current or unsets the override itself, after an apply.
  - Done when: Nicotine+ and Blanket take kosm's colors like native GTK apps.


- **18a. Zen's new tab page in the theme** `PLAN FIRST` (backlog: the human does not use it)
  - Do: the new tab page (Firefox's built-in `about:newtab`) is a page, which Zen mods cannot style: only the profile's `userContent.css` reaches it. `kosm_zen` writes its own stylesheet into each profile's `chrome` folder: the page transparent, its search box in `--kosm-button`, and Zen's logo replaced by the `logo` app's SVG; the human's `userContent.css` imports it. Propose the file, the import and how a missing import is reported first; drop the step if it makes setup harder for users.
  - Done when: on the human's machine the new tab page shows the window's background, a themed search box and the themed logo.
