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

- [ ] **3c. Built-in apps and Frost**
  - Do: `packages/kosm_kitty` (adapter + app, `generate`), `packages/kosm_css` (adapter), `packages/kosm_zen` (app, `generate`), `packages/kosm_nvim` (app, `template`) as directory packages (D2, D62, D67). Apps use D27 defaults and never copy Ricer's choices.
  - Do: port `~/.config/Ricer/Frost.toml` to a Frost kosmos in a scratch config project; it assigns fields to reproduce the current look (G2). Read the human's current files, never write them.
  - Done when: Frost rices those apps end to end in `--diff` mode against the real files, and every difference the kosmos can't close is reported (missing app field or deliberate D27 change). Running it for real is `ASK`.

- [ ] **4. `block` writer**
  - Do: `# kosm:begin <id>` ... `# kosm:end` blocks using the adapter's comment syntax (section 7).
  - Do: add the `comment` capability to `kosm.Adapter` (D39); 3a left it out until it has a user.
  - Do: `Plan` entries become byte ranges inside a file, so D38 rejects only overlapping ranges instead of any second writer of a file.
  - Done when: tests cover creating, replacing, and malformed or duplicate markers.

- [ ] **5. `edit` writer** `PLAN FIRST` `BLOCKED: Q9`
  - Do: tree-sitter runtime in core (D41, dependency approval is `ASK`), then `kosm_json`, `kosm_lua`, `kosm_hyprlang` (D28-D35, D39-D40).
  - Do: add the `format` and `parser` capabilities to `kosm.Adapter` (D39, D42).
  - Done when: path matching, cardinality, and byte-preserving edits are tested per adapter on real-world snippets.

- [ ] **6. CLI completion** `BLOCKED: Q16`
  - Do: `kosm add/remove/update` (D46), app reloads (D59), applying kosmoi from packages and keeping directory manifests up to date (D62), `current`, `--set` (D20).
  - Done when: each command is tested against a temp config project; nothing touches `~/.config/kosm`.
