# TODO

One step at a time, then stop for review (`AGENTS.md`). Decisions taken while the human was away are listed in `REVIEW.md`.

Each step has **Do** (what to build) and **Done when** (how to verify). Markers: `ASK` stop and ask the human first; `PLAN FIRST` post a short plan (files, key types, order) and wait for the go-ahead; `BLOCKED` wait for the named question in `QUESTIONS.md`.

Steps 1-12b (core, writers, CLI, packages, adapters, built-in apps, Kyanos/Krystallos) are done; `git log` has them.

---

Steps 21e-21j: kosmoi written in Lua, through a **frontend**. Decided with the human:
- A **frontend** lets users write kosmoi in a language other than Zig, like an adapter lets kosm write a format. It is an ordinary package, written like a third-party one; kosm core knows no frontend language, only the interface every frontend implements. Lua comes first; TOML, JSON or C# may follow later, each optional, so a large runtime (.NET) is acceptable.
- One package per language, `kosm_<language>`, holds everything kosm does with that language: its adapter and its frontend, each a Zig module of its own. `kosm_lua` (today the Lua adapter) gains the Lua frontend. Apps depending on a package only for its adapter (`kosm_hyprland`, `kosm_nvim` on `kosm_lua`) must not fetch the frontend's interpreter: make it a lazy dependency, and verify that this holds before relying on it.
- Every language is equal: any kosmos, look or base, in any language, builds on any other, the same workflow in a different syntax. Lua may be more limited, and gets idioms where they read better in Lua. Zig is the natural pick for low-level code, but apps, adapters and the rest of kosm can be written through any frontend whose own code is Zig too.
- No compiling on a Lua edit: the script is read when kosm runs, so only adding, updating or editing Zig code (packages, Zig kosmoi) rebuilds. Per-package binaries are not done: Zig has no stable ABI, and a rebuild on `add`/`update`/Zig edits is fast enough.
- Kosmoi keep doing no IO themselves: kosm loads the script, like an image named in `Params`, so missing files, `~/`, caching and errors work as for every other input.
- Completion is generated at build time, when types change: `kosm build` (and `add`, `update`) writes completion files for every app, base, look, Zig kosmos and its `Params`, with their doc comments. A Zig kosmos thus shows up in Lua completion after a build.
- Every step updates `DESIGN.md` in the same commit as the code relying on it: the vocabulary (frontend), the `kosm_<language>` layout, and kosmoi written through a frontend.

Steps 23a-23k come from a review of kosm with the human (2026-11-24), in the order to take them.

- **23a. Re-pin the packages that reload only while their program runs** (waits on the human)
  - Do: kosm_kitty, kosm_ghostty, kosm_dunst, kosm_hyprland, kosm_hyprpaper and kosm_cursor call `Reloader.runIfRunning`, which their pinned kosm lacks, so on their own they build only with `--fork` to a local kosm. Once the human has pushed kosm and the six packages, pin each to that kosm, then `kosm_base` and the config to the new package commits.
  - Done when: each package's `zig build test` passes without `--fork`, and an apply with kitty closed prints no warning.

- **23b. `kosm doctor`** `PLAN FIRST`
  - Do: a program that never includes kosm's file shows no change and no error, the likeliest first-day failure. Propose how an app declares how its file is reached (which file of the program includes it, and the line that does) and how its program is found (a command, a Flatpak id), then add `kosm doctor [kosmos]` printing one line per app: fine, not included (with the exact line to add), or program not found.
  - Done when: the human agreed on the declaration, doctor reports each case, and a test covers each.

- **23c. Seed files for configs that don't exist yet** `ASK`
  - Do: a fresh install fails on apps editing a program's main config the machine lacks (qtct, tuios, hyprmouse, wlr-which-key, Vicinae), so the starting kosmos leaves them out by hand. Propose a seed, the least content an app starts such a file from only when it does not exist at all, which goes against the non-goal on inserting keys, so it needs the human's word.
  - Done when: the human decided, and if agreed, those apps apply on a machine without their configs.

- **23d. Leave out apps whose program is missing** `ASK`
  - Do: propose a way (a flag, or a per-app choice) to leave out an app whose program isn't installed with a one-line notice, so choosing apps is about what is riced, not what is installed. It builds on how 20a finds installs.
  - Done when: the human decided, and if agreed, it works and is tested.

- **23e. Suggestions for misspelled fields, tags and parameters**
  - Do: `--set base.kity.x=1` lists all of `Base`'s fields, while a misspelled kosmos gets "did you mean". Give every "no field", "no tag", "none of" and unknown-parameter message the closest names, falling back to the list when none is close, from tables (`kosm.assign`, `--set`) and script calls alike. Use one edit distance for all of them: `names.zig` and `template.zig` each have their own.
  - Done when: `--set base.kity.x=1` suggests `kitty`, a far-off name still lists the fields, and tests cover fields, tags and parameters.

- **23f. Lua helpers for writing a kosmos** `ASK`
  - Do: propose names and forms for: printing a value while writing a kosmos (`kosm.trace(...)`, kosm prints it to stderr with the script's file and line, so the script still does no IO), showing a handle's fields (`kosm.inspect`), copying a handle (`:copy()`, today `color:mix(color, 0)`), a color with some components changed (`color:with({ lightness = 0.7 })`), and reading an optional chain without nil checks at every level.
  - Done when: the human agreed on the names, each works from Lua, completes, and is tested.

- **23g. `kosm --help`, `kosm help <command>` and `kosm --version`**
  - Do: `--help` prints "unknown command '--help'". Add the three, `help <command>` printing that command's usage and flags.
  - Done when: each prints what it should, and the CLI tests cover them.

- **23h. A summary of the diff**
  - Do: with thousands of files a whole diff is too long to read. Add `--diff --stat`: per app, the files and lines changed, groups as one line as now.
  - Done when: it prints per app counts that match the full diff, and a test covers it.

- **23i. Review the diff, then commit it** `ASK`
  - Do: propose `kosm apply -i`: print the diff, ask y/N, then commit the same plan without planning again, so what is committed is what was shown (a program saving a file meanwhile already fails the commit).
  - Done when: the human agreed, it works, and saying no writes nothing.

- **23j. Completion without waiting for a build**
  - Do: the first Tab after a change builds the runner, which takes seconds to half a minute. Keep the last completion answer per kosmos in the config's `zig-out` and answer from it while a rebuild runs.
  - Done when: Tab answers at once after an edit, the answer catches up once the build finished, and a test covers a stale answer being replaced.

- **23k. Say which kosm a build uses once**
  - Do: "building with the kosm at ..." and Zig's own "info: fork ... matched N kosm packages" print on every command, and may print twice when one command runs two builds (check whether a script kosmos whose base needs its manifest refreshed does). Print them once per command, and only with `-v` or when the kosm used changed since the last command.
  - Done when: a command running two builds prints them at most once, an unchanged override prints nothing without `-v`, and a CLI test covers it.

- **21l. Pick a suggestion for a misspelled kosmos** `ASK` (later)
  - Do: when a kosmos name is misspelled and stdin and stderr are a terminal, offer the closest names (up to 3) numbered and apply the one picked; without a terminal, fail in one line as today. Propose the prompt (its look, how a choice is typed, cancelling) first. `kosm apply` of a Zig kosmos is the easy part (the check runs in the command line before building); names the runner of scripts checks (a script, its variants, `--on`, a script's `base`) need it to hand its suggestions back to the command line, or to prompt itself. Decide whether `kosm build`, `colors` and `list` prompt too.
  - Done when: the human has agreed on the prompt, and picking a suggestion applies that kosmos, under a test.

- **18h. Equibop theme** (waits on the human)
  - Do: done (`kosm_equibop` `4188ae5`, `kosm_base` `cba3f15`, both pushed): Equibop reads its themes folder and QuickCSS live, and applies online themes, then local themes, then QuickCSS, the later winning. kosm writes a local theme, `themes/kosm.theme.css`, pointing Material Discord's variables at the theme's colors, font and rounding (its stacked window backgrounds painted once, so translucency stays see-through), in the Flatpak's folder (`~/.var/app/org.equicord.equibop/config/equibop`) until step 20a finds installs. Material Discord stays an online theme underneath it. The old `~/.config/equibop` is a leftover native install, which the Flatpak cannot read.
  - Left for the human: re-pin `kosm_equibop` and `kosm_base` in the config (`kosm update kosm_equibop`, `kosm update kosm_base`) and apply; once in Equibop, turn `kosm.theme.css` on among the local themes, delete the Ricer variables from the Flatpak's QuickCSS (which would win over the theme), and drop the stale `TranslucencePlus.theme.css` and `TransparentNord.css` from the enabled themes.
  - Do: `--kosm-placeholder` comes out a neutral gray (`#636363`) for Krystallos, not a dimmed foreground: find out whether `state.placeholder` drops the hue, across apps.
  - Done when: Equibop shows Krystallos' colors, font and rounding.

- **13q. A Qt style that looks right: Kvantum or our own** `ASK` `PLAN FIRST`
  - Do: Darkly is rejected (it looks wrong in many apps and misses colors). Already built: kosm `12c064d` (`hex8_argb`), `kosm_qtct` `dc481be` (`#aarrggbb` colors, `translucent` and `style` per program, alpha lowered for Darkly's double paint, a `touch -c` reload); the config pins these and `personal` sets qt6ct to Darkly and translucent until this step replaces it. Undo the double-paint lowering if the chosen style does not paint twice.
  - Do: give Kvantum an honest try: kosm generates a Kvantum theme (its `.kvconfig` and the `.svg` its colors live in) from the theme's roles, then compare it with the real apps (qt6ct, OpenRGB, Dolphin, KDE Connect, Mumble through Qt 5) in a headless KWin with screenshots over a checker backdrop. Weigh it against writing our own Qt style (a C++ QStyle plugin, or Zig behind a thin C++ shim) that draws from the platform palette, skips inner panel backgrounds so translucency is one layer, and reloads live. If our own style is less work for a result that works across the board, propose it instead. Also check whether COSMIC's way of styling Qt apps (step 19) can serve.
  - Found so far (headless KWin, real apps): Qt Widgets apps paint each container in the window color, so a translucent window color stacks into near-opaque layers; a stylesheet clearing inner backgrounds barely helped. Darkly paints the window twice on top of that. Bundled Kvantum themes at 50% opacity: Dolphin with KvantumAlt shows one clean see-through layer in its file view (sidebar and toolbar solid), qt6ct and OpenRGB only at the window edges with solid gray panels; Kvantum ignores the platform palette (colors come from the theme's SVG) and does not reload live. KDE Connect's window is QML (Kirigami), which neither style makes translucent; it shows a greenish tint from alpha on an opaque surface. KDE apps force Breeze unless kdeglobals' `[KDE] widgetStyle` names a style, and take their palette from `kosm_kde`'s scheme, so they recolor only on restart; under `QT_QPA_PLATFORMTHEME=kde` colors are live but fonts never reload outside Plasma (the KDE portal announces no setting changes there). Plain Qt apps recolor and change fonts live through qt6ct/qt5ct.
  - Left for the human: push kosm (kosm_qtct is pushed and pinned in kosm_base `66ca146`).
  - Done when: the human has picked Kvantum or our own style from screenshots of their apps, and Qt and KDE apps wear it in the kosmos' colors.


- **19. COSMIC desktop and apps** `ASK`
  - Do: find out how COSMIC reads its theme, icons, fonts and settings (its RON files under `~/.config/cosmic`, live reload) and propose `kosm_cosmic` from it, with its fields and the Krystallos values; it reads `kosm_icons`' theme like GTK and KDE. Cover COSMIC's own apps (Files, Terminal, Edit and so on) run under Hyprland, and find out how COSMIC styles Qt apps and whether that works outside COSMIC, for step 13q.
  - Done when: the human has agreed on the app, and COSMIC and its apps take the kosmos' colors and icons, and step 13q knows whether COSMIC's Qt styling can serve.


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

- **18s. Simple controls over the mapping** `ASK`
  - Decided with the human: a layer over the ranges, curves and contributors for people who never touch those: a handful of plain fields on the mapping's options, so a kosmos sets them and the image kosmos takes them as flags (`--frost 0.8`, `--opacity 0.7`, `--opaque true`). Amounts are multipliers, 1 being what the picture calls for, and stay within the ranges; `opaque` is a hard toggle.
  - Do: propose the list (likely opaque, opacity, blur, frost toward more passes, roundness, spacing, borders, shadow, glow) and their exact effect first; then add them to `kosm_base`'s mapping and `personal.image`'s `Params`, with README rows.
  - Done when: the human agreed on the list, it is under tests, and `--diff` shows `--frost` and `--opaque` changing the look.

- **18r. Hyprland reads traits**
  - Do: `kosm_hyprland.from(theme)` with traits picks its blur variant from them (frost for a blue, cold picture) and whatever else the human agrees on; propose the list first.
  - Done when: the human has agreed on the list and `--diff` shows it on two different wallpapers.

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


- **20a. Find every install of a program** `PLAN FIRST`
  - Do: kosm cannot know how a user installed a program (native, Flatpak, later Windows and macOS folders), and an app's single literal path misses the others: Equibop's Flatpak reads `~/.var/app/<id>/config/equibop`, not `~/.config/equibop`. Each app names the places its program may keep its config: its standard folders (step 20's `{config}`, `{data}`) and each packaged kind it knows (a Flatpak id, more kinds later). kosm, not the app, checks which kinds are installed and writes to every one found; the kosmos can turn any of them off per app.
  - Do: the human's idea for programs found nowhere: a kosm-wide setting, set once in the user's config (and once by an installer), listing the kinds missing programs are written for (such as `.system` and `.flatpak`), so kosm writes to those instead of guessing. Propose where the setting lives (the config's root, beside `packages.zon`, or a kosmos field) and its default.
  - Do: settle the edge cases in the plan: how kosm detects a kind (a config folder exists only after a first run, so a Flatpak is better checked by `flatpak info <id>` or its install folder); a Flatpak granted the host's `~/.config` reads the native files, so both kinds are one program; reloads per kind (signals and `touch -c` reach a Flatpak's files, commands may need `flatpak run --command`); how `--diff` and errors name each install; kinds that make no sense on a platform are skipped.
  - Done when: the human has agreed on the plan, and an app with a native and a Flatpak install writes to both, under a test.

- **20. Windows support** `ASK` `PLAN FIRST`
  - Do: apps' default paths are literal (`~/.config/...` in 22 apps, `~/.local/share/nvim/site` in `kosm_nvim`), and kosm resolves only `~/` and absolute paths, so on Windows every default is wrong, and on Linux a set `XDG_CONFIG_HOME` or `XDG_DATA_HOME` is ignored. Propose standard folders an app names instead (such as `{config}` and `{data}`), which kosm resolves per platform and environment: the XDG variables when set, their defaults on Linux and macOS (Neovim uses them on macOS too), `%APPDATA%` and `%LOCALAPPDATA%` on Windows; apps never read the environment themselves. Neovim's `NVIM_APPNAME` becomes an `appname` field of `kosm_nvim` (default `"nvim"`) its default `directory` follows.
  - Do: then list what else Windows needs: paths with `\` and drive letters, file replacement and permissions in commits, reloads (gsettings, `touch -c`, signals) that have no Windows counterpart, building and running a kosmos there, and which apps exist on Windows at all.
  - Done when: the human has agreed on the plan, and a kosmos applies on Windows with its apps' files in the right folders.

- **22. Shell completion of path parameters**
  - Do: `kosm apply personal.image --wallpaper ~/Pictures/<TAB>` offers nothing: the fish script disables file completion for every word (`complete -c kosm -f`), and `completeApply` prints nothing after any parameter, so a `kosm.Image` or `kosm.File` parameter (and a `--set` path whose value is one) gets no path completion. The runner reports each parameter's kind along with its flag, `kosm complete` prints a marker for a path-valued one, and the fish, bash and zsh scripts fall back to their own file completion on it, as fish already does after `--config`.
  - Done when: in fish, bash and zsh, Tab after `--wallpaper` completes files, and a test covers the marker `kosm complete` prints for a path parameter and for an ordinary one.

- **99. Optimization** (last: once the final product works) `PLAN FIRST`
  - Do: work through the list below, measuring before and after each change. Steps before this one only add to the list; they never optimize on their own.
  - Do: the runner's stack. A Debug build gives every temporary its own stack slot, and kosm's values are large: a `kosm.Modifier` is 2.4 KB (its chain holds 7 steps inline), a `kosm.Theme` 83 KB (80 KB of it the 33 variation modifiers), `kosm_icons`' `Recolor` holds a whole theme and `BeautyLine` two. `Colors.rule` (a three-line switch) got a 1.2 MiB frame, `walk.planNode` 1.8 MiB per level, some `assignment.copy.deep` 16.7 MiB. The runner now runs on a 256 MiB thread to fit. Options: store a modifier's chain out of line, have `Recolor` hold only the palette and roles, walk trees by pointer, build the runner in ReleaseSafe.
  - Do: `lifetime.Stack.below` bounds the stack by `getrlimit`, not by the thread it runs on; with a limit above 256 MiB it may refuse a list living in memory below the thread's stack.
  - Do: every kosmos variant is its own runner executable (`personal` is 156 MB in Debug), so `kosm build` of a config with 30 kosmoi and variants filled 4.4 GB of cache, and every edit leaves the old copies there until the next `kosm update` with a change or `kosm clean`. Options: one runner per kosmos choosing its variant at run time, a smaller build mode.
  - Do: the script runner (`zig build -Dscripts`) takes 31.6 s to compile cold on the personal config (38 packages, 1 GB peak memory), and 28.4 s after any change to kosm's sources with the cache kept, so every `kosm update` that changes kosm, and every kosm edit, waits about 30 s; a Zig kosmos runner takes about 2 s. Measured 2026-11-23, the same at every commit from `3ccfb33` to `0569949`. Zig's progress shows ~92k semantic analysis, ~60k code generation and ~79k link items, mostly under `bindings.Library` (the reflection over every package's API the scripts call). Profile it (`zig build --time-report`), then options: bind less (only what scripts use), build the runner in a release mode, split it so a kosm change does not recompile every package's bindings.
  - Do: a no-change `kosm apply personal --diff` takes 3.5 s (390 MB peak), all of it in the Debug script runner (the build is a 0.07 s cache hit). Stack samples (2026-11-23): about 70% in `kosm_icons` regenerating the whole BeautyLine theme every run (3175 SVGs read and recolored, `Colors.gradientStop` and `svg.colorAt` hottest, plus 11645 links planned and compared), about 25% in `kosm_cursor` rasterizing every cursor (`Picture.render`, `xcursor.encode`), and about a third of all samples inside Debug's `SafeAllocator` capturing a stack trace per allocation (`Plan.addLink`, `Plan.freeLink`, `Plan.read`). Options: build the runner in a release mode or use a plain allocator there, skip regenerating a theme whose inputs (source, colors) are unchanged, fewer allocations per link.
  - Do: loading an image parses its whole 1024px copy through `Color.fromRgb` (atan2, hypot, three `pow` and `cbrt` per pixel) for lightness alone: about 100 ms per image on every apply even from the cache, measured in ReleaseFast on the human's wallpapers (2026-11-23). `Image.readableAlpha` takes about 30 ms per call, and `Image.traits` makes one per blur spread (5) on top of its measures, most of it blurring and measuring the 1024px lightness. Options: a lightness-only conversion with a table for the 8-bit channels, caching the parsed planes, measuring texture on a smaller plane at large blurs; `Image.themeInput` now measures the traits on every call too, so a kosmos calling it and `Image.traits` pays twice.
  - Done when: each item is measured and either improved or dropped with the human's agreement.
