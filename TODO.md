# TODO: path to a working kosm

Do **one step at a time**, then stop for review (see `AGENTS.md`). Steps follow the build order in `DESIGN.md` section 11; later ones depend on earlier ones. The `D#`s each step touches are the spec.

Each step has:
- **Do:** what to build.
- **Done when:** how to verify.

Markers:
- `ASK`: stop and ask the human before continuing.
- `PLAN FIRST`: post a short plan (files, key types, order of work) and wait for the go-ahead before writing code.
- `BLOCKED: Q#`: do not start until those questions are answered in `QUESTIONS.md`.

---

- [x] **1. Core data** `PLAN FIRST`
  - Do: Color (OKLCH, formatting), Modifier, Variations, Palette with wheel resolution, Theme (section 4, D6-D16). Pure: no files, no IO.
  - Done when: `zig build test` passes with tests for the risky parts listed in `AGENTS.md` (color round trips, wheel resolution edge cases, modifier kinds, compositions, mode inversion).

- [x] **2. Packaging spike** `PLAN FIRST`
  - Do: prove D43 (package imports from `build.zig.zon`, kosmos discovery D17) and D19 params on Zig 0.17, in a throwaway config project under the scratch directory.
  - Done when: a sample kosmos importing a sample app package by name builds and runs with a `--param` parsed into its `Params`. If D43 does not work, stop and report: section 9 is redesigned before going further.

- [x] **3a. Writers in core** (plan approved)
  - Do: `ColorFormat` (D61), `Adapter` (D39 without `parser`), `Value` (D64), `Output` with `generate` and `template` (D64, D65; `~` expands against an injected home), D60 template placeholders, `Plan` (D35, D38), all-or-nothing commit keeping file modes (D36), unified diff (D37), diagnostics naming kosmos, app, file.
  - Done when: tests prove a failing plan writes nothing, two apps writing one file is an error, unchanged files are not rewritten, and cover template placeholders and diff output.

- [x] **3b. Build and runner**
  - Do: turn the step 2 spike into real code: `addConfigProject` in kosm's `build.zig` (dependency walk, package unification, `dependOnDirectoryContents`, one module per single-file kosmos, app or adapter, and one per directory rooted at its `root.zig`, D62), the `package(b)` helper (D62), and the reflection runner (kosmos discovery, `Params` parsing with D55 and D56, tree walk).
  - Do: the runner's comptime walks set `@setEvalBranchQuota`; nested app trees exceed the default 1000.
  - Do: the `kosm` binary with only `kosm apply <kosmos> [--param value]... [--diff] [--config dir]` (D45, D66).
  - Done when: a scratch config project's kosmos plans, diffs and commits into a temp directory through `kosm apply --config`.

- [x] **3c. Built-in apps and Kyanos**
  - Do: `packages/kosm_kitty` (adapter + app, `generate`), `packages/kosm_css` (adapter), `packages/kosm_zen` (app, `generate`), `packages/kosm_nvim` (app, `template`) as directory packages (D2, D62, D67). Apps use D27 defaults and never copy Ricer's choices.
  - Do: port `~/.config/Ricer/Kyanos.toml` (the theme in use) to a Kyanos kosmos in a scratch config project; it assigns fields to reproduce the current look (G2). Read the human's current files, never write them.
  - Done when: Kyanos rices those apps end to end in `--diff` mode against the real files, and every difference the kosmos can't close is reported (missing app field or deliberate D27 change). Nothing is applied for real until kosm is finished.

- [x] **3d. Color spaces and formatting** `PLAN FIRST`
  - Do: modifier parts for HSV/HSB, HSL, RGB and CMYK (D68), converting from and back to the stored OKLCH (D48).
  - Do: `kosm.Format` per file (D69, D70): hex letter case, bool spelling, number precision; it replaces `color_format` in `Output`, the adapters and the kitty, css, zen and nvim apps.
  - Do: the Kyanos port uses HSV `value +10` / `-15` like Ricer, so its bright and inactive colors match exactly.
  - Done when: round trips sRGB <-> each space are tested (hue wrap, gray hue, gamut edges), each modifier space is tested, and Kyanos `--diff` shows no color differences from Ricer except deliberate D27 ones.

- [x] **4. `block` writer**
  - Do: `# kosm:begin <id>` ... `# kosm:end` blocks using the adapter's comment syntax (section 7).
  - Do: add the `comment` capability to `kosm.Adapter` (D39); 3a left it out until it has a user.
  - Do: `Plan` entries become byte ranges inside a file, so D38 rejects only overlapping ranges instead of any second writer of a file.
  - Done when: tests cover creating, replacing, and malformed or duplicate markers.

- [x] **5a. `edit` writer and JSON** `PLAN FIRST` (plan approved)
  - Do: tree-sitter runtime in core (D41, D78), the `format` and `parser` capabilities of `kosm.Adapter` (D39, D42), path syntax (D32, D77), the file selector (D79), `output.edit` with every D31 call and the escape hatch (D34, D80), then `kosm_json` (D28-D35, D39-D40).
  - Done when: path matching, cardinality, the selector and byte-preserving edits are tested, and `kosm_json` is tested on real-world snippets.

- [x] **5b. `kosm_lua`**
  - Do: the Lua adapter, covering every nesting D30 lists (`M.blur = {...}`, `M.blur.enabled = ...`, `hl.config({...})`).
  - Do: `kosm.treesitter.Spec` gains what Lua needs (`assign`, `transparent`, D39); dotted assignments build tables with no value (`Adapter.Node.value` null), so test `Selection` refusing to replace one (`error.NoValue`).
  - Done when: path matching, cardinality and byte-preserving edits are tested on real-world snippets, including the D30 nestings.

- [x] **6a. Reloads and `--set`** `PLAN FIRST`
  - Do: apps' optional `reload`, called after the commit for every applied app, never on `--diff` (D59, D74); `kosm_kitty` reloads kitty.
  - Do: `--set path=value` on the returned tree (D20), with `set` reserved as a parameter name (D19).
  - Done when: tests show reloads run only after a successful commit, a failing reload is a warning naming its app while the rest still reload and the exit status stays 0, and `--set` covers nested paths, unknown fields, bad values, optionals and colors.

- [x] **6b. `kosm current`**
  - Do: record each successful apply in the state directory and print it with `kosm current` (D75).
  - Done when: tests with `XDG_STATE_HOME` in a temp directory show an apply records the kosmos, arguments and config, and `--diff` records nothing.

- [x] **6c. Package commands** `PLAN FIRST`
  - Do: `kosm add/remove/update` wrapping `zig fetch` with `packages.zon` (D46).
  - Done when: each command is tested against a temp config project; nothing touches `~/.config/kosm`.

- [x] **6d. Kosmoi from packages** `PLAN FIRST`
  - Do: apply kosmoi from installed packages and keep directory manifests up to date (D62).
  - Done when: a temp config project applies a packaged kosmos, and building a directory kosmos rewrites only its own manifest.

- [x] **7a. `kosm init` and `kosm list`** `PLAN FIRST`
  - Do: `kosm init [--config dir]` creates a config project (section 9): `build.zig`, `build.zig.zon` depending on `kosm`, `packages.zon`, and empty `kosmoi/`, `apps/`, `adapters/`. The plan settles what happens when the directory exists and how the config finds `kosm` and the built-in packages while they live in this repo (D67).
  - Do: `kosm init` fills in only what is missing (D83) and adds the Kyanos kosmos to an empty `kosmoi/` (D84).
  - Do: `kosm list [kosmos] [--config dir]` prints every kosmos with its variants, and the installed packages with what each provides (D85).
  - Done when: tests init a temp config, apply a kosmos in it, and list it; init on a complete project changes no byte, and init on a partial one adds only what is missing.

- [x] **7b. `kosm new`**
  - Do: `kosm new kosmos|app|adapter <name>` scaffolds a directory package with a commented `root.zig`, `build.zig` and `build.zig.zon` (D62, D63).
  - Do: keep the manifests of directory apps and adapters (`apps/my_bar/build.zig.zon`) up to date when a kosmos using them is applied; D76 refreshes only the applied kosmos' own.
  - Done when: each kind is scaffolded in a temp config and builds there, a scaffolded kosmos applies with `--diff`, and an existing name is refused.

- [x] **7c. Local packages provide everything**
  - Do: local kosmoi, apps and adapters provide whatever they declare, wherever they live (D87): adapters from every local package the applied kosmos reaches through imports, and kosmoi from `apps/` and `adapters/` for `kosm apply` and `kosm list`.
  - Done when: tests show an adapter declared in a directory kosmos, in a directory app the kosmos imports, and in a single-file kosmos itself are used on apply; a kosmos in `apps/` applies and is listed; and a compile error in a kosmos the applied one doesn't import leaves the apply working.

- [x] **8a. Warnings** `PLAN FIRST`
  - Do: a way for core and apps to report a warning that doesn't fail the apply, printed with the kosmos, app and file like an error (G6). The plan proposes the `D#`.
  - Do: warn when a printed color is clipped to the gamut (D48).
  - Done when: tests show a clipped color warns naming the app and file, still writes, and an in-gamut one doesn't warn.

- [x] **8b. `kosm_kitty` formatting fix**
  - Do: compound values (`Timing`, `Edges`, `MouseHideWait`, ...) print their floats and booleans themselves while the tree is built, so they ignore `format.float_precision` and `format.boolean`; write them with the file's `kosm.Format`.
  - Do: `TransparentColor` prints its color through the file's `kosm.Format` (its `Context.writeColor`), so a clipped one warns like any other color (D88).
  - Done when: tests show a compound value follows a changed `float_precision` and `boolean`.

- [x] **9a. `kosm_ghostty`** `PLAN FIRST`
  - Do: a hand-written ghostty adapter (D40: `key = value` lines, repeated keys such as `palette` and `font-family`, `#` comments) with `serialize`, `format` and `comment`, and a ghostty app that `generate`s a file the user includes with `config-file` (D57), following D27.
  - Done when: the adapter round trips real ghostty config snippets, and the app's output for Kyanos matches `~/.config/ghostty/Ricer` except deliberate D27 changes (read only).

- [x] **9b. `kosm_hyprland`** `PLAN FIRST`
  - Do: a Hyprland app covering every `hl.config` option of upstream Hyprland (D27), whose `target` (D91) either `generate`s `~/.config/hypr/kosm.lua` (the default) or sets the keys in the user's Lua files through `output.edit` (D25, D30).
  - Do: `kosm_lua`: `serialize`, writing a module (`return { ... }`) for `generate`; positional tables (`{ "a", "b" }`) as lists for `elements` (D80, D90).
  - Done when: the generated module holds Hyprland's own shape, and the edit target is tested on real-world `hl.config` snippets in a temp directory, including gradients (`{ colors = { ... } }`) and values split across files.

- [x] **9c. Zen prefs through `kosm_userjs`** `PLAN FIRST`
  - Do: a `user.js` adapter (`user_pref("name", value);`) and `kosm_zen` fields for Zen's about:config prefs (D27). The plan asks which prefs to cover first.
  - Done when: the adapter round trips real `user.js` snippets and `kosm_zen` writes its prefs in a temp profile.

- [x] **9d. Include block for Hyprland**
  - Do: `output.templateBlock` (D71) and `.missing = .skip` for blocks (D72): a missing file is not created, and kosm warns with the block's lines.
  - Do: `kosm_hyprland` keeps `hl.config(require("kosm"))` in a block at the end of `~/.config/hypr/hyprland.lua` through its `include` field (D97).
  - Done when: tests show the block is appended once and then left unchanged, a missing `hyprland.lua` is not created and warns, and a generated module `require("kosm")` can't find fails the apply.

- [x] **9e. Kosm installed on the system** `PLAN FIRST`
  - Do: D98: `zig build install` puts kosm's sources in `<prefix>/share/kosm`; the built-in packages come from kosm's own tree in `addConfigProject` and `package(b)`; `kosm init` adds `kosm` by URL (no built-in entries, no repository path); every build kosm runs passes `--fork` for the sources it finds; `kosm source`; the interface number checked by the runner.
  - Do: drop the `kosm_repository` root that the binary records today (D83 no longer needs it).
  - Done when: tests (offline: the URL is a local directory) show an init config lists only `kosm` and applies with a built-in app, a build uses the forked sources over the pinned ones, `kosm source` sets, prints and clears the override, a config not depending on `kosm` gets no `--fork`, and an interface mismatch fails naming both numbers.

- [x] **9f. Settings an app doesn't cover**
  - Do: D99: `kosm.Setting` in core, and `kosm_hyprland.extra` written to both targets after the app's own settings, nested into the generated module's tables.
  - Done when: tests show extras land in the generated module beside typed options (quoted keys too), are set by path on the edit target, and an extra equal to, inside or containing another set setting or extra fails naming both.

- [ ] **9g. Apps without `from`**
  - Do: D100: every built-in `App{}` compiles and writes nothing; deriving modifiers (`kosm_hyprland.inactive`, `kosm_ghostty.bright`, ...) become `?kosm.Modifier = null`, and fields `from` fills get defaults; each README says a minimal config can skip `from`.
  - Do: D101: `kosm_ghostty.background_opacity` derives from the background's alpha like `kosm_kitty`'s.
  - Done when: tests show `App{}` of every built-in app plans nothing (or an empty file where the app always writes one), a null deriving modifier derives nothing, and ghostty's opacity follows the background's alpha below 1 and is not written at 1.

- [ ] **10. Kyanos for real** `PLAN FIRST`
  - Do: `~/.config/kosm` made by `kosm init` with the installed kosm (D98), holding the Kyanos kosmos: kitty, ghostty, nvim, Zen (theme CSS, and prefs in a test profile under `~/.zen-kosm/`), and `kosm_hyprland` generating `~/.config/hypr/defs-kosm.lua` with every `hl.config` value `defs.lua` feeds today, with `include = null`. The background is black with its alpha (D101). No existing file is written: every app targets a new file (`theme-kosm.lua` for nvim). Other programs Ricer rices are out of scope.
  - Done when: `kosm apply kyanos --diff` shows only deliberate differences from what Ricer and `defs.lua` hold today, each reported. Then stop: the human runs the first real `kosm apply` (hard rule 8).

- [ ] **11a. `kosm_toml`** `PLAN FIRST` `ASK`
  - Do: a TOML adapter with `serialize`, `format`, `comment` and `parser` (D39), mapping every way TOML nests keys (`[table]`, `[a.b]`, dotted keys `a.b = 1`, inline tables `{ a = 1 }`) onto one path (D30); arrays of tables (`[[x]]`) are lists for `elements` (D77, D80). The plan proposes a tree-sitter grammar or a hand-written parser (D40); a grammar is a dependency (hard rule 6).
  - Done when: path matching, cardinality and byte-preserving edits are tested on real-world TOML snippets (alacritty, vicinae), including the nestings above.

- [ ] **11b. `kosm_ini`** `PLAN FIRST`
  - Do: a hand-written INI adapter (D40) with `serialize`, `format`, `comment` and `parser`: `[section]` headers, `key = value` lines, `;` and `#` comments, keys before the first section at the top level. The plan settles the dialect details real configs need (`key=value` without spaces, repeated keys, `[Section][Sub]` as in kdeglobals).
  - Done when: path matching, cardinality and byte-preserving edits are tested on real-world snippets (dunst, qt5ct/qt6ct colors, kdeglobals, foot).

---

Follow-ups with no step yet:
- `extra` (D99) for `kosm_kitty`, `kosm_ghostty`, `kosm_zen` and `kosm_nvim`.
