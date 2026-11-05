# AGENTS.md

Instructions for AI coding agents working on Kosm.
Humans: edit the "Project settings" section freely; the rest is the stable rulebook.

---

## Project settings (edit me)

- **Project name:** Kosm (prose name). The repo, binary, package and namespace are lowercase `kosm`; packages are `kosm_<name>` (`kosm_hyprland`, `kosm_lua`, D51); environment variables use `KOSM_`. A rice is a **kosmos** (pl. **kosmoi**); the dotfiles holding them are the **Ktisis**. Use these words, and **package / app / adapter** (D54), exactly as `DESIGN.md` does. "Module" only ever means a Zig module.
- **Language / version:** Zig 0.17.0 (tagged release, D44). Pinned via `minimum_zig_version` in `build.zig.zon`. Never target Zig master.
- **Docs location:** dependency docs live in the dependencies themselves (doc comments in Zig bindings, headers and `docs/` of C sources) under `zig-pkg/`. `doc/` holds project docs, plus the Zig language reference split into one file per chapter in `doc/generated/zig/` (run `./fetch-docs.sh` to create it). All of these can be large: follow "Reading documentation and large files" below.
- **Zig std source:** found via `zig env` (the `.std_dir` field). Do not hard-code the path.
- **Primary dev platform:** Linux (Hyprland, Wayland). Hosts: nous, egregoros, ergasterion, synekdemos. No Windows or macOS yet.

---

## What this project is

A tool that rices a whole desktop from Zig code: a kosmos is a Zig function returning a tree of apps, and kosm writes their values into the apps' real config files, all or nothing. Read `DESIGN.md` before touching anything structural; it is the single source of truth. Every decision there is numbered (`D#`), every goal (`G#`); open questions (`Q#`) are in `QUESTIONS.md`. Your task list is `TODO.md`, which follows the build order in `DESIGN.md` section 11.

**Anything not in `DESIGN.md` is undecided. Do not invent it; ask.** Non-goals (`DESIGN.md` section 12) are never implemented unless the human moves them out of that list.

## Hard rules (never break these)

1. **Never push, and never run branch, tag, rebase, amend, or other repo-management commands.** Committing is required: commit each step's work as soon as it is done and verified, so the human always has a clean commit to review; review fixes land as a separate follow-up commit, never amended into the step's own commit. Match the human's commit style from `git log`: `feat:`, `fix:`, `docs:`, `chore:`, `style:`, `refactor:`, `test:` plus a short capitalized description, one line, written as what changed for a user (`feat: Missing hues are mixed from their wheel neighbours`), not as a file list. Split commits sensibly by type. A local commit is reversible, a push is not. Do not touch licenses, CI, or repo metadata. Reading (`git status`, `git diff`, `git log`) is fine.
2. **One step at a time.** Do exactly one step from `TODO.md`, make it pass its "Done when" checks, then **stop** and report. Do not start the next step. Tick the step's checkbox yourself once it is fully done: every "Done when" check passes, nothing waits on the human (an open `Q#`, a dependency approval), and you are confident it is right. Commit the tick with the step's final work. If anything is still pending, leave it unticked and say what is missing.
3. **Open questions block their section.** Never start work that depends on a `Q#` still open in `QUESTIONS.md`, and never answer one yourself by picking the recommendation. When the human answers one, move the answer into `DESIGN.md` as a new `D#` (next free number, in the right section) and delete the question, in the same `docs:` commit.
4. **The design changes only on purpose.** If the code needs something `DESIGN.md` does not say, or contradicts a `D#`, stop and propose the change (which decision, what it would say, why). Once the human agrees, update `DESIGN.md` in the same commit as the code that relies on it. Never renumber decisions; a removed one stays as `D# (removed: reason)` so references do not break.
5. **Do not trust your memory of Zig.** Zig changes between versions and you were likely trained on older ones. Before using a std or build API you are not 100% sure about, look it up in the std source or `doc/generated/zig/`. When you hit a gotcha, add a line to `doc/ZIG_NOTES.md`.
6. **Ask before adding any dependency** (library, tool, vendored code, tree-sitter grammar). Stop and propose: what it is, why it is needed, what the alternative is (often "write it ourselves, ~N lines"). Wait for approval. Name the exact change you will make (the `zig fetch --save=<name> <url>` you will run, or the entries you will delete); once approved, make it yourself and wire it up in `build.zig`. Never touch `build.zig.zon` dependencies without that explicit approval.
7. **Respect the layers** (D1). Core data (Color, Modifier, Theme) knows nothing about apps or files. Apps never parse and never do file IO; they only call `output`. Adapters never know about any app. Kosm's own built-in apps and adapters are written exactly like third-party packages, with no private API (D2). Where `build.zig` can enforce a boundary by limiting a module's imports, it does. Never "fix" a compile error by loosening a boundary; ask instead.
8. **Never write to the human's real files.** Tests and experiments work in `std.testing.tmpDir` or the scratch directory, never in `~/.config`, the Ktisis, or any path under `$HOME` outside the repo. Do not run `kosm apply` (or anything that commits a plan) against real configs unless the human asks for that exact command; `--diff` is fine.
9. **Do not ask the human about things you can verify yourself** (APIs, compile errors, test failures). Ask about design choices, dependencies, naming with several good options, and open questions.
10. **Do not invent features.** Implement what the step says. If you notice something worth doing, add a short note under "Notes for the human" in your final report, not in code.
11. **Plan first for big steps.** If a step is marked `PLAN FIRST` in `TODO.md`, or you find it will touch more than about five files, post a short plan (files to create or change, key types, order of work) and wait for the human's go-ahead before writing code.
12. **Small follow-ups go into `TODO.md`, not the report.** When your work leaves a small concrete task for later (a stopgap to replace, a cleanup a later step makes possible), add it as one line to the `Do:` of the future step where it belongs, written as a plain task. Report only what needs the human: questions, design concerns, and bugs or missing bindings in dependencies (verify those fully, and add each as an unticked item under its project in `UPSTREAM.md`).
13. **Plain ASCII only.** Code, comments, docs, commit messages, and `TODO.md` use plain ASCII: `-` (never an em or en dash), `->`, `<=`, `>=`, `*` (never a multiplication sign), `deg`, `...`. Write non-ASCII test data with `\u{...}` escapes. The only exceptions are the Greek words naming the project (`κόσμος`, `κτίσις`) and any non-ASCII text the human wrote on purpose. Before committing, check with `git diff --cached | grep -P '[^\x00-\x7F]'`.

## Reading documentation and large files

Binding sources, C headers, the Zig language reference in `doc/`, and std source files are thousands of lines long. Loading them whole wastes your context and makes your work worse.

**Rules**
1. **Never open, `cat`, or view a whole large file.** This applies to files in `doc/` over about 300 lines, to Zig std source files, to vendored C headers and sources, and to any file over about 300 lines that you did not write in this session. (`DESIGN.md` is the exception: read it whole once per session.)
2. **Search first, then read a narrow window.** (a) Search for the term with line numbers. (b) Read roughly 40 to 120 lines around the best hit. (c) Widen only if you still need more.
3. If a search returns more than about 20 hits, refine the pattern instead of skimming them.
4. Prefer your tool's built-in search and line-range reading. Otherwise use the shell commands below.

**Dependency docs (bindings first)**
```sh
ls zig-pkg/                                        # fetched packages, one directory each
rg -n "pub fn parse" zig-pkg/<package>/src/        # find the API and its doc comment
rg -n "pattern" zig-pkg/<package>/ -g '*test*'     # usage examples in the package's tests
```
If a binding's comments are not enough, search the wrapped C library's headers and `docs/` (for tree-sitter: `api.h`, and each grammar's `node-types.json` for node names).

**The Zig language reference and std**
```sh
ls doc/generated/zig/                              # chapter list, one file per langref section
rg -n "pattern" doc/generated/zig/                 # search all chapters with file and line
wc -l doc/generated/zig/<file>.md                  # check a chapter's size before opening it
sed -n '120,200p' doc/generated/zig/<file>.md      # read lines 120 to 200 only
rg -n "pub fn name" "$(zig env | rg -o '"std_dir": *"[^"]*"' | cut -d'"' -f4)"   # std source
```
Chapters under about 300 lines may be read whole. For std, read the doc comment and signature at the hit, and the file's `test` blocks for usage. Never rely on memory for a std API.

## Priorities

1. **Correctness, never silent (G6).** If kosm cannot do exactly what was asked, it errors with a message naming the kosmos, app, file and path involved, and writes nothing.
2. **Readability and maintainability.** The human reviews and maintains all of this code.
3. **The user's experience of writing a kosmos or app (G1, G7-G9).** If an internal shortcut makes user code worse, take the longer way inside kosm.
4. **Performance**, a close fourth. Kosm runs on demand, so do not trade clarity for speed without a measured reason, but do not be careless either (no re-parsing a file per key).
5. Cleverness is last. Prefer boring, obvious code.

## Code style

Follow idiomatic Zig and the official Zig style guide.

- **Naming (G9):** types `PascalCase`; functions `camelCase`; variables, fields, parameters `snake_case`; enum values `snake_case`; namespace files `snake_case.zig`. **Full words**, no abbreviations: `variations` not `vars`, `Modifier` not `Mod`, `output` not `out` (`min`/`max`/`hex` are fine). A name must say what it does to someone who never read the code. If a new user-facing name has several good options, ask. Exception: an app field mirroring a program's setting keeps that program's name, adjusted only to Zig's casing (`kitty_mod`, not `kitty_modifier`; D27).
- **User-facing API rules (G7, G8).** Everything a kosmos or app author touches is a plain struct field or a plain function argument with a concrete type, so editor completion works. No `anytype` patches, no `@Type`/`@Struct`-generated types, no `io`, allocators, `environ` or `deinit` in user code. Reflection is fine *inside* kosm (walking the tree, D18; CLI params, D19), never in what the user writes.
- **File per struct.** A struct gets its own file named `PascalCase.zig`, written as a file-level struct (`const Color = @This();` with fields at the top). Files that are collections of functions or constants are namespaces in `snake_case.zig`. Package roots (`root.zig`) follow the shape in `DESIGN.md` (D22, D39).
- **Separation of concerns.** A struct handles only its own concern. If its description needs the word "and", consider splitting it. Keep functions short and single-purpose.
- **Errors:** error sets and `try`; no silent catches. Errors that reach the user carry context (which kosmos, app, file, path, match count) through a diagnostics value, not a bare error name. `catch unreachable` and `@panic` only for genuine invariants, with a comment.
- **Memory:** pass allocators explicitly inside kosm. Every struct that allocates has `init`/`deinit`; ownership is documented. No hidden global allocators. (Users never see any of this, G7.)
- **No globals** except where unavoidable (e.g. a logger); document them.
- **Inline comments are rare; doc comments are required.** Write code that reads clearly through good names and small functions. Add a `//` comment only when a reader would be confused or likely to "fix" something intentional: an edge case, a workaround, a non-obvious invariant, a surprising ordering. One concise line saying *why* (three at most). Never write comments that:
  - restate what the code does, or narrate steps
  - label sections with banners or separators
  - document self-explanatory declarations or parameters
  - contain commented-out code
  - are TODO or note-to-self comments (follow-ups go in `TODO.md`, hard rule 12)

  Every **public** declaration gets a brief `///` doc comment in the style of the Zig standard library: one to three lines, written for someone *using* it - what it does, units and ranges (OKLCH lightness 0..1, hue in degrees), ownership, constraints. Do not repeat the name or narrate the body. Where a declaration implements a decision, cite it (`/// Missing hues mix from wheel neighbours (D7).`). Package roots carry a one-line `//!` header.

  Exception: user-tweakable fields (app fields, `Variations` members, `Params`) always get a short `///` comment with meaning and default behaviour, because kosmos authors read them through completion.
- **Magic numbers:** name them. Defaults users may want to change (variation amounts, app values) are fields with defaults set in `from`, never constants buried in logic.
- **Formatting:** run `zig fmt` on everything you touch.

## Testing

Use Zig's built-in `test` blocks at the bottom of the file they test. Run with `zig build test`.

The rule: **test what a careful senior developer would be nervous about.** Use common sense.

Write tests for things that are easy to get subtly wrong:
- color math: sRGB <-> OKLCH round trips, gamut clamping, hue wrap-around at 0/360, alpha
- palette resolution (D7): no hues set, one hue set, neighbours across the wheel's wrap, mixing by wheel position not actual hue
- modifiers: each kind (D15), mode inversion (D12), compositions resolving at apply time (D16)
- CLI parsing of `Params` (D19) and `--set` paths (D20): types, colors by hex or name, bad input
- path matching and cardinality (D28-D33): zero matches, too many, indices out of range, quoted segments, `*`
- byte-preserving edits (D35): only the value's bytes change, unchanged files are not rewritten
- transactional apply (D36-D38): any error means nothing on disk changes; overlapping edits are rejected
- every adapter: parse -> match -> format round trips on real-world config snippets, including the odd nestings D30 lists

Do **not** write tests for trivial getters, thin wrappers, or code whose correctness is obvious on reading. A test that restates the implementation is noise. When unsure, **write the test**. Keep tests small, named for the behaviour (`test "set errors when the path matches two files"`), and free of heavy setup. File tests always use `std.testing.tmpDir` (hard rule 8).

## Workflow for each step

1. Read the step in `TODO.md`, the `D#`s it touches in `DESIGN.md`, and check `QUESTIONS.md` for anything blocking it.
2. Read `doc/ZIG_NOTES.md`. Look up any API you are unsure of: dependency doc comments first, then headers, `doc/` and std source for Zig. Never guess.
3. Implement the step, and only that step.
4. Run `zig fmt`, `zig build`, `zig build test`. Fix everything. Check the test summary count: a suite can pass while running none of your tests (see ZIG_NOTES).
5. Update docs touched by the change in the same commit: `DESIGN.md` (agreed design changes), `doc/ZIG_NOTES.md` (gotchas), `UPSTREAM.md` (dependency bugs), and a package's README field list when an app gains or changes fields (D27).
6. Tick the step in `TODO.md` if it is fully done (rule 2), then commit (rule 1).
7. Write a short final report:
   - what you changed (files)
   - how you verified it
   - gotchas added to `doc/ZIG_NOTES.md`
   - notes for the human (questions, concerns, design proposals)
   - whether to clear, compact, or keep the conversation:
     - **clear** (`/clear`) when the step is committed and nothing from this session is needed next. The usual case.
     - **compact** (`/compact`) when the conversation is long but something must carry over: an open review, a half-verified fix, a question awaiting an answer.
     - **keep** when the conversation is short and work on this step continues.
8. **Stop.** Wait for the human. Review feedback is implemented as a new commit on top.

If a step is too big or its instructions seem wrong, stop and say so instead of improvising.

When a file degrades mid-session - fragmented edits, stale compiler errors, reads that do not match - rewrite it whole instead of patching. In long sessions, watch for edit discipline slipping and suggest a break before it costs a step. After any confusing stretch, re-verify the real state (`git status`, `ls`, a fresh build) instead of trusting remembered results: phantom tool outputs look identical to real ones.

## Where things are

| File | Purpose |
|------|---------|
| `DESIGN.md` | The design: goals (`G#`), decisions (`D#`), build order, non-goals. Source of truth. |
| `QUESTIONS.md` | Open questions (`Q#`). An open one blocks the work that depends on it. |
| `TODO.md` | Steps following the build order. Your task list. |
| `doc/ZIG_NOTES.md` | Zig 0.17 gotchas. Read before coding, append when you learn something. |
| `UPSTREAM.md` | Bugs found in dependencies, to report to their projects. |
| `fetch-docs.sh` | Downloads the Zig language reference into `doc/generated/zig/`. |
