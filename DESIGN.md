# Kosm - Design

> κόσμος: *order, arrangement, adornment*. The root of both *cosmos* and *cosmetic*.
>
> **Kosm** is the tool. A **kosmos** (pl. **kosmoi**) is a rice. The dotfiles holding every
> kosmos are the **Ktisis** (κτίσις, *creation*).

This file holds what guides new work: goals, the architecture, the rules every app and
adapter follows, and non-goals. How something already built works is in its code, doc
comments, tests and README. Work still to do is in `TODO.md`; anything neither here nor
there is undecided, so ask.

## Goals

- **Kosm configures the whole system,** not only its looks: settings several programs share (keyboard layouts, cursor, rounding) are set once like colors are.
- **A minimal kosmos is tiny.** One official base holds every supported app with plain defaults; a look makes it look nice; a user's kosmos picks a base and a look and sets the few things that are personal. Every app derives the rest.
- **Depth is opt-in, in the same file.** Any single value of any app is overridden by a plain assignment.
- **Variants are a function call.** A variant calls its base's build function with a few changed inputs, then assigns its own tweaks.
- **Nothing is written twice.** No full-file template copies of configs.
- **Anyone can support anything.** Apps and adapters are ordinary Zig packages: `kosm add <url>` and it works. Kosm's own are written exactly like third-party ones, with no private API.
- **Never wrong silently.** If kosm can't do exactly what was asked, it errors naming the kosmos, app, file and path involved, and writes nothing.
- **The user writes data, not plumbing.** No `io`, allocators, `environ`, `deinit` or cursors in user code.
- **Completion everywhere.** Everything a user sets is a plain struct field or function argument with a concrete type: no `anytype` patches, no `@Type`-generated types. Reflection is fine inside kosm.
- **Full words.** `Modifier`, `variations`, never `mod` or `vars`; Zig naming conventions.

## Vocabulary

- **package:** anything `kosm add` fetches; it may hold apps, adapters, kosmoi and a base kosmoi build on.
- **app:** support for one program (`kosm_hyprland` exports `App`, `from`, `App.apply`).
- **adapter:** support for one file format (Lua, TOML, JSON).
- **kosmos:** a rice, a function returning a tree of apps. It is what kosm applies.
- **base:** turns a look into apps; the official one is `kosm_base`, and a user's own base holds it and adds apps.
- **look:** what makes a base look nice (Krystallos, Everforest): a theme, fonts, the base's shared values, and a tweak of the official base's apps. A look builds no apps, so it works on any base holding the official one.

"Module" only ever means a Zig module.

## Architecture

```
 KOSMOS                  APPS                       ADAPTERS + WRITERS
 what the rice is   ->   what a program needs  ->   how bytes reach a file
```

- The layers never mix. Core data (colors, modifiers, the theme) knows nothing about apps or files. An app never parses and never does file IO; it only tells its `output` what to write. An adapter never knows about any app. The build enforces this where it can.
- **Inputs before `from`, tweaks after.** `from(inputs)` derives a complete struct of plain fields; any field can be assigned afterwards. To make a change flow into everything derived from it, change the input and call `from` again.
- **Nothing is written until kosm says so.** User code only builds values. Kosm calls every app's `apply`, plans every edit in memory, and commits all or nothing. `--diff` prints the plan and writes nothing.

## Theme

`kosm.Theme` is the only thing every app receives: a palette, a mode, roles, code colors, a background alpha and variations.

- **Palette:** black and white are required; the 12 hues of the wheel (red, orange, yellow, lime, green, teal, cyan, sky, blue, purple, magenta, pink, 30 deg apart) are optional, and a missing one is mixed from its nearest set neighbours by wheel position. Colors beyond the wheel belong to apps or to the kosmos' own constants.
- **Mode:** dark or light; the background and foreground roles follow it.
- **Roles:** libadwaita's names, which KDE and Material map onto: background, foreground, accent, secondary, success, warning, error. Each is optional and defaults from the palette (the accent is cyan); an app reads the role, never the palette color it defaults to, so one assignment recolors every app. An app's own colors beyond these stay its own fields.
- **Code colors:** tree-sitter's capture names (comment, keyword, string, number, constant, function, type, variable, property, operator, punctuation, tag), each optional and defaulting from the palette or the foreground, for editors and anything highlighting code.
- **Background alpha:** one alpha every app gives its own background, so a single value makes terminals, browser and editors translucent together.
- **Name:** the name programs show for the kosmos, falling back to the name kosm applies it under. One switch names the files a program picks by name: `kosm` for every kosmos, or after the kosmos so each keeps its own. Files a program includes by path are always `kosm`.
- **Variations:** named color transforms in families (lightness, emphasis, state, surface, line, contrast, alpha), tweaked once on the theme for every app.
- Colors are OKLCH in f64. Modifiers also work in HSV, HSL, RGB and CMYK. A color outside sRGB is clipped when printed; `kosm colors` marks the palette colors that are.

## Rules for apps

- A field mirroring a program's setting keeps the program's name, in Zig casing (`kitty_mod`). Null means "not written; the program's default applies".
- `from(theme)` fills fields from the theme; an `App{}` without `from` writes nothing. Fields derived from another field of the same app (an inactive color from the active one) are null until `apply`, so assigning the source still flows into them and assigning the derived one still wins.
- A program's separate opacity setting follows its background's alpha; the background is one color with alpha, never a color plus an opacity value.
- Every app has `extra` for settings it doesn't cover, written after its own and failing if one overlaps a set setting.
- An app writes its own file that the program includes, rather than the program's main config. Making the program read it is the user's job, except for an app's own visible include block, which the user can turn off. Kosm never creates backups.
- Each written file has a `kosm.Format` (color spelling, booleans, float precision) layered from the user's assignment, the app's default, the adapter's and kosm's.
- An app may reload its program after a successful apply, and set there what a program keeps outside files (gsettings); a failure is a warning.
- An app's package exports the adapters it writes with, so a config needs only that package to rice the program.

## Rules for adapters and edits

- An adapter declares only what it can do (`serialize`, `parser`, `format`, `comment`); kosm says clearly when an app needs a capability an adapter lacks.
- Edits are byte-preserving: only a value's own bytes change, and unchanged files are not rewritten. Two apps writing the same bytes is an error.
- A path that matches nothing is an error; kosm never inserts keys. A path matching several values must say which (`setFirst`, `setAll`, `setNth`).
- Kosm core owns the tree-sitter runtime; an adapter ships only its grammar. A grammar is a dependency like any library. Simple formats are hand-written instead.

## Packages and the config project

- A config project (`~/.config/kosm`, made by `kosm init`) is a Zig project depending on `kosm` by URL; `kosmoi/`, `apps/` and `adapters/` hold the user's own. A file there is private to its directory; a directory with `root.zig` is a package.
- Package commands (`kosm add`, `remove`, `update`) wrap `zig fetch`; `packages.zon` remembers the ref to follow.
- Kosm's own packages live in repositories of their own, like anyone's. `kosm init` adds every official package to a new config, with a starting kosmos that uses them.
- The base kosmos is the package `kosm_base`: `from(look, apps)` returns the official apps chosen, each an optional field, then applies the look's tweak. Its default look is literal: black is `#000000`, red `#ff0000`, rounding 0. Its shared values (rounding, gaps, border, padding, cursor, keyboard layouts and the like) are set once and read by every app with that setting; a value is shared once two apps use it or very likely will. Personal settings (shaders, keyboard layouts, editor) default to null, so the program's own default applies.
- A kosmos chooses its base, its look and its apps (all, none, only some, or all but some; the others are never applied), then assigns its overrides. A user's own base holds `kosm_base`'s in a struct of its own beside its added apps, which follow the look through the theme's roles. The starting kosmos builds on `kosm_base`.
- A build holds one copy of each package: what a config (or a package built on its own) lists itself wins over the copy a package pins, and packages pinning different copies of a package it doesn't list fail the build naming them.
- Zig is pinned to a tagged release, never master.

## Non-goals

- Inserting missing keys, or include lines outside an app's include block.
- Backup files.
- Checking package versions against the user's kosm.
- `**`, predicates or regex in paths.
- `.with` / `.override` patch APIs.
- Wallpaper -> palette generation (could be a package later).
- Any custom configuration language.
- LSP integration.
