# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

- **18h. Equibop theme** `ASK`
  - Do: find out how Equibop (the Vesktop-based Discord client) takes a theme (Vencord's QuickCSS or a CSS file in its themes folder, Discord's CSS variables, live reload) and propose `kosm_equibop` from it, with its fields and the Krystallos values.
  - Done when: the human has agreed on the app, and Equibop takes the kosmos' colors and fonts.


- **13q. A Qt style that looks right: Kvantum or our own** `ASK` `PLAN FIRST`
  - Do: Darkly is rejected (it looks wrong in many apps and misses colors). Already built: kosm `12c064d` (`hex8_argb`), `kosm_qtct` `dc481be` (`#aarrggbb` colors, `translucent` and `style` per program, alpha lowered for Darkly's double paint, a `touch -c` reload); the config pins these and `personal` sets qt6ct to Darkly and translucent until this step replaces it. Undo the double-paint lowering if the chosen style does not paint twice.
  - Do: give Kvantum an honest try: kosm generates a Kvantum theme (its `.kvconfig` and the `.svg` its colors live in) from the theme's roles, then compare it with the real apps (qt6ct, OpenRGB, Dolphin, KDE Connect, Mumble through Qt 5) in a headless KWin with screenshots over a checker backdrop. Weigh it against writing our own Qt style (a C++ QStyle plugin, or Zig behind a thin C++ shim) that draws from the platform palette, skips inner panel backgrounds so translucency is one layer, and reloads live. If our own style is less work for a result that works across the board, propose it instead. Also check whether COSMIC's way of styling Qt apps (step 19) can serve.
  - Found so far (headless KWin, real apps): Qt Widgets apps paint each container in the window color, so a translucent window color stacks into near-opaque layers; a stylesheet clearing inner backgrounds barely helped. Darkly paints the window twice on top of that. Bundled Kvantum themes at 50% opacity: Dolphin with KvantumAlt shows one clean see-through layer in its file view (sidebar and toolbar solid), qt6ct and OpenRGB only at the window edges with solid gray panels; Kvantum ignores the platform palette (colors come from the theme's SVG) and does not reload live. KDE Connect's window is QML (Kirigami), which neither style makes translucent; it shows a greenish tint from alpha on an opaque surface. KDE apps force Breeze unless kdeglobals' `[KDE] widgetStyle` names a style, and take their palette from `kosm_kde`'s scheme, so they recolor only on restart; under `QT_QPA_PLATFORMTHEME=kde` colors are live but fonts never reload outside Plasma (the KDE portal announces no setting changes there). Plain Qt apps recolor and change fonts live through qt6ct/qt5ct.
  - Left for the human: push kosm (kosm_qtct is pushed and pinned in kosm_base `66ca146`).
  - Done when: the human has picked Kvantum or our own style from screenshots of their apps, and Qt and KDE apps wear it in the kosmos' colors.


- **19. COSMIC desktop and apps** `ASK`
  - Do: find out how COSMIC reads its theme, icons, fonts and settings (its RON files under `~/.config/cosmic`, live reload) and propose `kosm_cosmic` from it, with its fields and the Krystallos values; it reads `kosm_icons`' theme like GTK and KDE. Cover COSMIC's own apps (Files, Terminal, Edit and so on) run under Hyprland, and find out how COSMIC styles Qt apps and whether that works outside COSMIC, for step 13q.
  - Done when: the human has agreed on the app, and COSMIC and its apps take the kosmos' colors and icons, and step 13q knows whether COSMIC's Qt styling can serve.


- **18e. Neovim highlight groups from kosm**
  - Do: `kosm_nvim` writes the highlight groups itself (editor UI, Treesitter, LSP, diagnostics) from the theme's roles and code colors, instead of base16 slots for the `nvim-base16` plugin; the human's `nvim/lua/config/colors.lua` then loads them and drops base16 and its overrides. Propose the groups and the module's shape first.
  - Do: info diagnostics take the info role; diff and git-sign groups (`DiffAdd`, `DiffChange`, `DiffDelete`, `Added`, `Changed`, `Removed`) take the theme's diff colors.
  - Done: `kosm_nvim` `6ebf23f` writes `background`, `highlights` (groups by Neovim's name, fields in snake case, a translucent `bg` as `NONE`, plugin groups through `groups`) and `terminal`; base16 is gone. Pinned in `kosm_base` `710c699`, both pushed.
  - Left for the human: re-pin `kosm_base` in the config; replace `app.base16.base0F` in `kosmoi/krystallos/nvim.zig` and `kosmoi/og_steam/nvim.zig`; rewrite `colors.lua` to set `theme.highlights` with `nvim_set_hl` and read `theme.terminal` in `get`, dropping nvim-base16, `transparent_groups` and `overrides()`.
  - Done when: the human's Neovim shows kosm's colors without nvim-base16.


- **18l. Image commands** (optional)
  - Do: `kosm palette <image> [style options]` prints the palette (and roles) as Zig source to paste into a kosmos, for a palette frozen from an image. `kosm new kosmos <name> --image <path>` scaffolds a kosmos on `kosm_base` taking the image as its `Params` default, with its palette and hyprpaper's wallpaper from it; it fails if the config lacks `kosm_base`.
  - Do: the scaffold wears its look through `base.fromTheme(look, theme, apps)` (`kosm_base` `d15972b`), as `base.from` takes the look at compile time; its wallpaper list is a list of run-time values, so it is written with `kosm.keep`.
  - Done when: both commands work on one of the human's wallpapers and the scaffold builds.

- **18m. Re-apply the current kosmos with other arguments** `ASK`
  - Do: propose how to re-apply the kosmos `kosm current` records with changed arguments (`kosm apply --current --wallpaper <path>`), merging with or replacing the recorded ones.
  - Done when: the human has agreed on the form and it works.

- **18n. A palette generator** `ASK`
  - Do: the human wants a palette generator besides images; ask what it generates from (a seed color, a few hues, a scheme like Material's) and propose its API beside `kosm.Image`'s.
  - Done when: the human has agreed on it and it builds a palette.


- **13a. kosm_json's clip warning tests**
  - Do: when `kosm_json` next pins kosm, drop its tests of clip warnings (`context.clipped`, the `outside sRGB` warning).
  - Done when: `kosm_json`'s tests pass without them, pinned on the new kosm.


- **13l. CS2's fonts.conf** (paused: the human has disabled it for now)
  - Do: the game's `fonts.conf` is stock again (Ricer's "Custom fonts" section is gone, likely restored by Steam) and `kosm_counter_strike_2` writes `42-repl-global.conf`, which that file says still applies. Left: the human checks the font in game; if it shows, delete this step, otherwise the human describes the cleanup still needed.
  - Done when: the human has seen the font in game, or the described cleanup is tested without touching the game's real files.


- **13p. Drop qt6ct and qt5ct** `ASK`
  - Do: nwg-look is replaced (`kosm_gtk` writes GTK's settings files and sets gsettings) and Kvantum is not installed. Left: the human uninstalls nwg-look and deletes `~/.config/Kvantum`; then decide qt6ct/qt5ct: `QT_QPA_PLATFORMTHEME=kde` (plasma-integration, installed) reads colors, fonts, icons, style and single-click from kdeglobals, which `kosm_kde` would gain fields for; the tooltip qss is lost, and Qt 5 apps need `plasma5-integration` or keep qt5ct.
  - Do: Krystallos' Hyprland app sets the `GTK_THEME` environment variable (or leaves it unset) instead of the hand-written `defs.lua`.
  - Do: `kosm_kde` gains the cursor theme and size (`kcminputrc` `[Mouse] cursorTheme`, `cursorSize`), set from the shared cursor values like GTK's.
  - Do: the human's Flatpak overrides (`flatpak override --user --show`, and the system-wide one) still set `QT_QPA_PLATFORMTHEME=qt6ct`, `QT_STYLE_OVERRIDE=breeze` and Kvantum access; settle them with qt6ct/qt5ct.
  - Done when: the human has agreed whether qt6ct and qt5ct go, and their settings come from kosm instead.


- **13y. `kosm install` for styles and themes apps need** `PLAN FIRST`
  - Do: `kosm install` (short `kosm i`) installs what an app needs to look as configured (styles, themes such as Darkly or adw-gtk3), never the programs themselves; it is optional, and users may install these by hand instead. Each app declares its needs, with a package name per distro (Arch first, Fedora later). A need in the distro's official repositories is installed with its package manager, showing the exact command and running it only once the user confirms; kosm never updates it, the package manager does. Otherwise kosm installs it per user (under `~/.local`, no root) from source pinned by commit and content hash, showing the install script before it runs; `kosm update` shows the new commits and the diff of the build and install files, and moves the pin only once the user accepts. Propose how apps declare needs, the per-distro names, the source build and where files go first.
  - Done when: the human has agreed on the plan, and `kosm install` installs Darkly on the human's machine the chosen way.

- **13u. Flatpak GTK apps** (waits on the human)
  - Do: Flatpak apps still load the old theme: the human's Flatpak overrides set `GTK_THEME` (`oomox-Ricer` per user, `Nordic-darker-v40` system-wide), so libadwaita Flatpaks (Blanket) get Oomox drawn over them and plain GTK 4 ones (Nicotine+) draw Oomox. Without it, Flatpaks take the theme name kosm sets in gsettings, but see themes only in `~/.local/share/themes` (not `/usr/share/themes`), so plain GTK 4 Flatpaks need adw-gtk3 there; with it they follow kosm's colors (checked off-screen with a plain GTK 4 window). Setting `GTK_THEME=adw-gtk3-dark` instead would also force adw-gtk3's copy of libadwaita's stylesheet over every libadwaita app's own. Left: the human unsets `GTK_THEME` (`flatpak override --user --unset-env=GTK_THEME`) and makes adw-gtk3 visible to Flatpaks (a copy in `~/.local/share/themes`, which pacman does not update); then decide whether `kosm_gtk` keeps that copy current or unsets the override itself, after an apply.
  - Done when: Nicotine+ and Blanket take kosm's colors like native GTK apps.


- **18a. Zen's new tab page in the theme** `PLAN FIRST` (backlog: the human does not use it)
  - Do: the new tab page (Firefox's built-in `about:newtab`) is a page, which Zen mods cannot style: only the profile's `userContent.css` reaches it. `kosm_zen` writes its own stylesheet into each profile's `chrome` folder: the page transparent, its search box in `--kosm-button`, and Zen's logo replaced by the `logo` app's SVG; the human's `userContent.css` imports it. Propose the file, the import and how a missing import is reported first; drop the step if it makes setup harder for users.
  - Done when: on the human's machine the new tab page shows the window's background, a themed search box and the themed logo.

- **17a. Zen repaints after an apply** (later)
  - Do: done (`kosm_firefox` `22059df`, pushed, pinned in the config): the browser keeps the window's opaque region per painted element and refreshes only what it repaints, so a background turning translucent stayed marked opaque (a dark box without blur) until a refocus. A second after an apply changes prefs, Kosm Live nudges each window's root background color invisibly for two frames, which forces a full rebuild (an opacity change did not). It did not help on the human's first tries (once it worked, but so it did now and then without it). Next: find out whether the stale opaque region is the cause at all, without refocusing Zen (Hyprland focuses the Browser Console's window, so running the nudge from there is no test); if it is, trigger the rebuild once Zen's new styles have landed instead of after a fixed second. Once it works: re-pin `kosm_firefox` and `kosm_qtct` (`dc481be`) in `kosm_base`, push it, and re-pin `kosm_base` in the config.
  - Done when: going from an opaque to a translucent theme with Zen open shows the page translucent, blurred, without refocusing.
