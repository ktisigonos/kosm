# General rules

The shared rulebook for AI coding agents, the same in every project. Copy this file unchanged between projects; anything specific to one project or language goes in the project's `AGENTS.md` or a language file next to this one. Where the project's `AGENTS.md` says something more specific, it wins.

## Project files

Every project following these rules keeps the same files at its root:

| File | Purpose |
|------|---------|
| `AGENTS.md` | Project-specific rules and settings, plus pointers to the files in `.agents/`. |
| `DESIGN.md` | The design: goals (`G#`), decisions (`D#`), build order, non-goals. Source of truth. |
| `QUESTIONS.md` | Open questions (`Q#`). An open one blocks the work that depends on it. |
| `TODO.md` | Steps following the build order. Your task list. |
| `UPSTREAM.md` | Bugs found in dependencies, to report to their projects. |

**Anything not in `DESIGN.md` is undecided. Do not invent it; ask.** Non-goals listed in `DESIGN.md` are never implemented unless the human moves them out of that list.

## Hard rules (never break these)

1. **Never push, and never run branch, tag, rebase, amend, or other repo-management commands.** Committing is required: commit each step's work as soon as it is done and verified, so the human always has a clean commit to review; review fixes land as a separate follow-up commit, never amended into the step's own commit. Match the human's commit style from `git log`: `feat:`, `fix:`, `docs:`, `chore:`, `style:`, `refactor:`, `test:` plus a short capitalized description, one line, written as what changed for a user (`feat: Missing hues are mixed from their wheel neighbours`), not as a file list. Split commits sensibly by type. A local commit is reversible, a push is not. Do not touch licenses, CI, or repo metadata. Reading (`git status`, `git diff`, `git log`) is fine.
2. **One step at a time.** Do exactly one step from `TODO.md`, make it pass its "Done when" checks, then **stop** and report. Do not start the next step. Tick the step's checkbox yourself once it is fully done: every "Done when" check passes, nothing waits on the human (an open `Q#`, a dependency approval), and you are confident it is right. Commit the tick with the step's final work. If anything is still pending, leave it unticked and say what is missing.
3. **Open questions block their section.** Never start work that depends on a `Q#` still open in `QUESTIONS.md`, and never answer one yourself by picking the recommendation. When the human answers one, move the answer into `DESIGN.md` as a new `D#` (next free number, in the right section) and delete the question, in the same `docs:` commit.
4. **The design changes only on purpose.** If the code needs something `DESIGN.md` does not say, or contradicts a `D#`, stop and propose the change (which decision, what it would say, why). Once the human agrees, update `DESIGN.md` in the same commit as the code that relies on it. Never renumber decisions; a removed one stays as `D# (removed: reason)` so references do not break.
5. **Ask before adding any dependency** (library, tool, vendored code, grammar). Stop and propose: what it is, why it is needed, what the alternative is (often "write it ourselves, ~N lines"). Wait for approval. Name the exact change you will make (the command you will run, or the entries you will delete); once approved, make it yourself and wire it into the build. Never touch the dependency manifest without that explicit approval.
6. **Never write to the human's real files.** Tests and experiments work in a temporary directory or the scratch directory, never in `~/.config`, the human's dotfiles, or any path under `$HOME` outside the repo. Do not run anything that changes the human's real setup unless the human asks for that exact command.
7. **Respect the architecture's boundaries.** Follow the layers `DESIGN.md` defines. Where the build can enforce a boundary (by limiting what a module may import), it does. Never "fix" a compile error by loosening a boundary; ask instead.
8. **Do not ask the human about things you can verify yourself** (APIs, compile errors, test failures). Ask about design choices, dependencies, naming with several good options, and open questions.
9. **Do not invent features.** Implement what the step says. If you notice something worth doing, add a short note under "Notes for the human" in your final report, not in code.
10. **Plan first for big steps.** If a step is marked `PLAN FIRST` in `TODO.md`, or you find it will touch more than about five files, post a short plan (files to create or change, key types, order of work) and wait for the human's go-ahead before writing code.
11. **Small follow-ups go into `TODO.md`, not the report.** When your work leaves a small concrete task for later (a stopgap to replace, a cleanup a later step makes possible), add it as one line to the `Do:` of the future step where it belongs, written as a plain task. Report only what needs the human: questions, design concerns, and bugs or missing bindings in dependencies (verify those fully, and add each as an unticked item under its project in `UPSTREAM.md`).
12. **Plain ASCII only.** Code, comments, docs, commit messages, and `TODO.md` use plain ASCII: `-` (never an em or en dash), `->`, `<=`, `>=`, `*` (never a multiplication sign), `deg`, `...`. Write non-ASCII test data with escapes. The only exceptions are those the project's `AGENTS.md` lists and any non-ASCII text the human wrote on purpose. Before committing, check with `git diff --cached | grep -P '[^\x00-\x7F]'`.
13. **Do not trust your memory of the language or its libraries.** They change between versions and you were likely trained on older ones. Before using an API you are not 100% sure about, look it up in the source or the docs the project points to. When you hit a gotcha, add a line to the project's notes file for that language.

## Reading documentation and large files

Dependency sources, C headers, language references, and standard library files are thousands of lines long. Loading them whole wastes your context and makes your work worse.

1. **Never open, `cat`, or view a whole large file.** This applies to files in `doc/` over about 300 lines, to standard library source files, to vendored sources and headers, and to any file over about 300 lines that you did not write in this session. (`DESIGN.md` is the exception: read it whole once per session.)
2. **Search first, then read a narrow window.** (a) Search for the term with line numbers. (b) Read roughly 40 to 120 lines around the best hit. (c) Widen only if you still need more.
3. If a search returns more than about 20 hits, refine the pattern instead of skimming them.
4. Prefer your tool's built-in search and line-range reading. Otherwise use `rg -n`, `wc -l` and `sed -n 'A,Bp'`.
5. Read dependency docs bindings first: the doc comments of the binding, then the wrapped library's headers and `docs/`, then its tests for usage examples.

## Priorities

1. **Correctness, never silent.** If the program cannot do exactly what was asked, it errors with a message naming everything involved, and changes nothing.
2. **Readability and maintainability.** The human reviews and maintains all of this code.
3. **The user's experience.** If an internal shortcut makes the user's side worse, take the longer way inside the program.
4. **Performance**, a close fourth. Do not trade clarity for speed without a measured reason, but do not be careless either (no re-parsing a file per key).
5. Cleverness is last. Prefer boring, obvious code.

## Code style

- **Names:** **full words**, no abbreviations: `variations` not `vars`, `Modifier` not `Mod`, `output` not `out` (`min`/`max`/`hex` are fine). A name must say what it does to someone who never read the code. If a new user-facing name has several good options, ask.
- **Separation of concerns.** A type handles only its own concern. If its description needs the word "and", consider splitting it. Keep functions short and single-purpose.
- **Errors:** no silent catches. Errors that reach the user carry context (what was being done, on which file or item) through a diagnostics value, not a bare error name.
- **No globals** except where unavoidable (e.g. a logger); document them.
- **Magic numbers:** name them. Defaults users may want to change are configurable values, never constants buried in logic.
- **Inline comments are rare; doc comments are required.** Write code that reads clearly through good names and small functions. Add an inline comment only when a reader would be confused or likely to "fix" something intentional: an edge case, a workaround, a non-obvious invariant, a surprising ordering. One concise line saying *why* (three at most). Never write comments that:
  - restate what the code does, or narrate steps
  - label sections with banners or separators
  - document self-explanatory declarations or parameters
  - contain commented-out code
  - are TODO or note-to-self comments (follow-ups go in `TODO.md`, hard rule 11)

  Every **public** declaration gets a brief doc comment: one to three lines, written for someone *using* it - what it does, units and ranges, ownership, constraints. Do not repeat the name or narrate the body. Where a declaration implements a decision, cite it (`Missing hues mix from wheel neighbours (D7).`).
- **Formatting:** run the language's formatter on everything you touch.

## Testing

The rule: **test what a careful senior developer would be nervous about.** Use common sense. Test things that are easy to get subtly wrong: math and conversions, edge cases and wrap-around, parsing bad input, error paths, anything that writes files. The project's `AGENTS.md` lists the risky parts specific to it.

Do **not** write tests for trivial getters, thin wrappers, or code whose correctness is obvious on reading. A test that restates the implementation is noise. When unsure, **write the test**. Keep tests small, named for the behaviour (`test "set errors when the path matches two files"`), and free of heavy setup. File tests always work in a temporary directory (hard rule 6).

## Workflow for each step

1. Read the step in `TODO.md`, the `D#`s it touches in `DESIGN.md`, and check `QUESTIONS.md` for anything blocking it.
2. Read the language notes file. Look up any API you are unsure of: dependency doc comments first, then headers, `doc/` and the standard library source. Never guess.
3. Implement the step, and only that step.
4. Run the formatter, the build, and the tests. Fix everything. Check the test summary count: a suite can pass while running none of your tests.
5. Update docs touched by the change in the same commit: `DESIGN.md` (agreed design changes), the language notes file (gotchas), `UPSTREAM.md` (dependency bugs), and any user-facing docs the change affects.
6. Tick the step in `TODO.md` if it is fully done (hard rule 2), then commit (hard rule 1).
7. Write a short final report:
   - what you changed (files)
   - how you verified it
   - gotchas added to the language notes file
   - notes for the human (questions, concerns, design proposals)
   - whether to clear, compact, or keep the conversation:
     - **clear** (`/clear`) when the step is committed and nothing from this session is needed next. The usual case.
     - **compact** (`/compact`) when the conversation is long but something must carry over: an open review, a half-verified fix, a question awaiting an answer.
     - **keep** when the conversation is short and work on this step continues.
8. **Stop.** Wait for the human. Review feedback is implemented as a new commit on top.

If a step is too big or its instructions seem wrong, stop and say so instead of improvising.

When a file degrades mid-session - fragmented edits, stale compiler errors, reads that do not match - rewrite it whole instead of patching. In long sessions, watch for edit discipline slipping and suggest a break before it costs a step. After any confusing stretch, re-verify the real state (`git status`, `ls`, a fresh build) instead of trusting remembered results: phantom tool outputs look identical to real ones.
