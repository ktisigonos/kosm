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
  - Done when: a sample kosmos importing a sample module package by name builds and runs with a `--param` parsed into its `Params`. If D43 does not work, stop and report: section 9 is redesigned before going further.

- [ ] **3. Writers: `generate` + `template`** `PLAN FIRST` `BLOCKED: Q4, Q6, Q7, Q8, Q10, Q11, Q12, Q13, Q14`
  - Do: both writers, transactional apply and `--diff` (D36-D38), and 3 built-in modules (kitty, one CSS app, nvim) written exactly like third-party packages (D2).
  - Do: turn the step 2 spike into real code: `addConfigProject` in kosm's `build.zig` (dependency walk, package unification, `dependOnDirectoryContents`, one module per kosmoi file) and the reflection runner (kosmos discovery, `Params` parsing, tree walk).
  - Do: the runner's comptime walks set `@setEvalBranchQuota`; nested module trees exceed the default 1000.
  - Done when: the real Frost kosmos rices those apps end to end in `--diff` mode, and tests prove a failing plan writes nothing. Running it for real is `ASK`.

- [ ] **4. `block` writer**
  - Do: `# kosm:begin <id>` ... `# kosm:end` blocks using the adapter's comment syntax (section 7).
  - Done when: tests cover creating, replacing, and malformed or duplicate markers.

- [ ] **5. `edit` writer** `PLAN FIRST` `BLOCKED: Q9`
  - Do: tree-sitter runtime in core (D41, dependency approval is `ASK`), then `kosm-json`, `kosm-lua`, `kosm-hyprlang` (D28-D35, D39-D40).
  - Done when: path matching, cardinality, and byte-preserving edits are tested per adapter on real-world snippets.

- [ ] **6. CLI completion**
  - Do: `kosm add/remove/update` (D46), reload hooks, `current`, `--set` (D20).
  - Done when: each command is tested against a temp config project; nothing touches `~/.config/kosm`.
