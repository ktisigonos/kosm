# AGENTS.md

Instructions for AI coding agents working on Kosm. This file holds only what is specific to Kosm; read and follow these first, they apply in full:

- @.agents/general.md - rules for every project (git, one step at a time, questions, dependencies, style, testing, workflow)
- @.agents/zig.md - rules for every Zig project (looking things up, Zig style, `zig build test`)

Where this file is more specific than those, this file wins. Hard rule numbers refer to `general.md`.

Humans: edit the "Project settings" section freely; the rest is the stable rulebook.

---

## Project settings (edit me)

- **Project name:** Kosm (prose name). The repo, binary, package and namespace are lowercase `kosm`; packages are `kosm_<name>` (`kosm_hyprland`, `kosm_lua`); environment variables use `KOSM_`. A rice is a **kosmos** (pl. **kosmoi**); the dotfiles holding them are the **Ktisis**. Use these words, and **package / app / adapter**, exactly as `DESIGN.md` does. "Module" only ever means a Zig module.
- **Language / version:** Zig 0.17.0 (tagged release). Pinned via `minimum_zig_version` in `build.zig.zon`. Never target Zig master.
- **Docs location:** dependency docs live in the dependencies themselves under `zig-pkg/`. `doc/` holds project docs, plus the Zig language reference in `doc/generated/zig/`. All of these can be large: follow "Reading documentation and large files" in `general.md`.
- **Primary dev platform:** Linux (Hyprland, Wayland). Hosts: nous, egregoros, ergasterion, synekdemos. No Windows or macOS yet.

---

## What this project is

A tool that rices a whole desktop from Zig code: a kosmos is a Zig function returning a tree of apps, and kosm writes their values into the apps' real config files, all or nothing. Read `DESIGN.md` before touching anything structural: goals, architecture, rules and non-goals. Your task list is `TODO.md`.

## Kosm rules

- **Layers (hard rule 7).** Core data (Color, Modifier, Theme) knows nothing about apps or files. Apps never parse and never do file IO; they only call `output`. Adapters never know about any app. Kosm's own built-in apps and adapters are written exactly like third-party packages, with no private API.
- **Real configs (hard rule 6).** Never touch the Ktisis. Do not run `kosm apply` (or anything that commits a plan) against real configs unless the human asks for that exact command; `--diff` is fine.
- **ASCII exceptions (hard rule 12).** The Greek words naming the project (`κόσμος`, `κτίσις`).
- **Grammars are dependencies (hard rule 5).** A tree-sitter grammar needs approval like any library. If a binding's comments are not enough, search tree-sitter's `api.h` and each grammar's `node-types.json` for node names.

## Priorities in kosm

- **Correctness:** if kosm cannot do exactly what was asked, it errors with a message naming the kosmos, app, file and path involved, and writes nothing.
- **The user's experience** is that of writing a kosmos or app: tiny kosmoi, plain data, completion everywhere.
- **Performance:** kosm runs on demand, so clarity wins unless a speedup is measured.

## Code style in kosm

- **Naming.** An app field mirroring a program's setting keeps that program's name, adjusted only to Zig's casing (`kitty_mod`, not `kitty_modifier`).
- **User-facing API rules.** Everything a kosmos or app author touches is a plain struct field or a plain function argument with a concrete type, so editor completion works. No `anytype` patches, no `@Type`/`@Struct`-generated types, no `io`, allocators, `environ` or `deinit` in user code. Reflection is fine *inside* kosm (walking the tree, CLI params), never in what the user writes. Allocators, `init`/`deinit` and ownership stay inside kosm.
- **Package roots** (`root.zig`) export `App`, `from` and `App.apply` for an app, and the adapter declaration for an adapter, like the existing packages.
- **Errors** reaching the user carry the kosmos, app, file, path and match count through a diagnostics value.
- **Doc comments** use OKLCH units where relevant (lightness 0..1, hue in degrees). User-tweakable fields (app fields, `Variations` members, `Params`) always get a short `///` comment with meaning and default behaviour, because kosmos authors read them through completion.
- **Defaults** users may want to change (variation amounts, app values) are fields with defaults set in `from`.
- **Docs to update:** a package's README field list when an app gains or changes fields.

## What to test in kosm

- color math: sRGB <-> OKLCH round trips, gamut clamping, hue wrap-around at 0/360, alpha
- palette resolution: no hues set, one hue set, neighbours across the wheel's wrap, mixing by wheel position not actual hue
- modifiers: each kind, mode inversion, compositions resolving at apply time
- CLI parsing of `Params` and `--set` paths: types, colors by hex or name, bad input
- path matching and cardinality: zero matches, too many, indices out of range, quoted segments, `*`
- byte-preserving edits: only the value's bytes change, unchanged files are not rewritten
- transactional apply: any error means nothing on disk changes; overlapping edits are rejected
- every adapter: parse -> match -> format round trips on real-world config snippets, including odd nestings (Lua's `M.a = {...}`, `M.a.b = ...`, `hl.config({...})`)

## Where things are

The shared files (`DESIGN.md`, `QUESTIONS.md`, `TODO.md`, `UPSTREAM.md`) are listed in `general.md`; the Zig ones (`doc/ZIG_NOTES.md`, `fetch-docs.sh`, `doc/generated/zig/`) in `zig.md`.
