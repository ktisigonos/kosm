# Kosm — Design (Draft v0.4)

> κόσμος: *order, arrangement, adornment*. The root of both *cosmos* and *cosmetic*.
>
> **Kosm** is the tool. A **kosmos** (pl. **kosmoi**) is a rice. The dotfiles
> that contain every kosmos are the **Ktisis** (κτίσις, *creation*: the whole
> created order).

Status: a draft for discussion. Every decision is numbered (`D#`) so it can be
referenced, changed or overruled. Open questions (`Q#`) are collected in
[QUESTIONS.md](QUESTIONS.md). Anything not in this file is undecided, so don't
invent it. Ask first.

Previous attempts and what they taught us:

| Attempt | Where | Lesson |
|---|---|---|
| Ricer (Python) | `~/Data/Projects/Ricer` | Works, but you need one whole TOML per theme, and templates are full copies of the configs (Fleet.json: 1271 lines). |
| Ricer (C#, `.ricer` language) | `~/Data/Projects/C_Sharp/Ricer` | A custom language is too much to maintain. Its mods and variations ideas were good. |
| Kosm (C#) | `~/Data/Projects/C_Sharp/Kosm` | Themes as code with variations works. The csproj plumbing doesn't. |
| Kosm (Zig, GLM) | `~/Projects/Zig/kosm-glm` | io/allocator plumbing leaked into user code. Users re-declared every field. App plugins mixed app semantics with parsing. Nobody could use it. |

---

## 1. Goals

- **G1. A minimal kosmos is tiny.** Black, white and a few hues rice everything. Every app derives the rest.
- **G2. Depth is opt-in, in the same file.** Override any single value of any app with a plain assignment.
- **G3. Variants are a function call.** FrostIced = Frost's build function called with a few changed inputs, plus a few assignments.
- **G4. Nothing is written twice.** No full-file template copies of configs.
- **G5. Anyone can support anything.** Language support and app support are ordinary Zig packages: `kosm add <url>` and it works.
- **G6. Never wrong silently.** If kosm can't do exactly what was asked, it errors and writes nothing.
- **G7. The user writes data, not plumbing.** No `io`, allocators, `environ`, `deinit` or cursors in user code.
- **G8. Completion everywhere.** Everything a user sets is a plain struct field or a plain function argument with a concrete type. No `anytype` patches, and no `@Type`-generated types in user-facing APIs.
- **G9. Full words.** `const kosm = @import("kosm")`, `Modifier`, `variations`, never `k`, `mod` or `vars`. Zig naming conventions throughout (`TitleCase` types, `camelCase` functions, `snake_case` fields).

## 2. Architecture: three layers

```
 KOSMOS                 APP MODULES                 LANGUAGE ADAPTERS + WRITERS
 what the rice is   →   what an app needs     →     how bytes reach a file
 (user: functions       (packages: fields +         (packages, written once per language)
  returning modules)     from + apply)
```

- **D1.** The three layers never mix. An app module never parses anything. An adapter never knows about any app.
- **D2.** Everything is a Zig package. One package can export any mix of adapters, modules and kosmoi. Kosm's own built-ins are written exactly like third-party packages.

## 3. The core rule (style A)

- **D3. Inputs before `from`, tweaks after.** Every layer works the same way. `from(inputs)` derives a complete struct of plain fields, and you change any field afterwards by assignment.
  - Want a change to *flow* into everything derived from it? Change the **input** and call `from` again.
  - Want to change one *result*? Assign the field.
- **D4. Inheritance is a function call.** A kosmos that builds on another calls the other's build function with different inputs, then assigns its own tweaks. No `.with`, no `.override`, no merge magic.
- **D5. Nothing is written until kosm says so.** User code only builds values. Kosm calls each module's `apply` at the end, plans every edit, and commits all or nothing (§7.2). User code never calls `apply`.

## 4. Theme: the only standard

`kosm.Theme` is what every module's `from` receives. It has three parts: **palette**, **mode** and **variations**.

```zig
var theme = kosm.Theme.from(palette, .dark);
theme.variations.state.hovered.lightness = 0.06;   // tweak once, for every app built from this theme
```

### 4.1 Palette: the 12-hue wheel

```
red · orange · yellow · lime · green · teal · cyan · sky · blue · purple · magenta · pink
 0°     30°      60°     90°    120°   150°   180°  210°  240°    270°     300°     330°
```

- **D6.** `kosm.Palette` (the input) has **`black` and `white` as required fields**, and all 12 hues as `?Color = null`.
- **D7. Missing hues are mixed from the nearest set hues on either side of the wheel**, by *wheel position*, not by actual hue. So if `red` and `yellow` are both blues (FrostIced), the derived `orange` is a blue as well. Mixing happens in OKLCH. One set hue means every hue is that hue. No set hues means every hue derives from `gray`.
- **D8.** `gray` is always derived: mix(black, white). It can be overridden on the resolved palette.
- **D9.** `theme.palette` is the **resolved** palette (`kosm.Palette.Resolved`): all 12 hues, plus black, white and gray, all non-optional. Modules only ever see this one.
- **D10.** Extra colors beyond the wheel belong to modules (their own fields) or to your own consts. The wheel is the only shared vocabulary.

### 4.2 Mode

- **D11.** `mode: .dark | .light`. That's the single global fact modules use to decide their own background, foreground, buttons and so on. There is no global `bg`/`fg`/`button`/`outline`: every one of those belongs to a module.

### 4.3 Variations

A variation is a `kosm.Modifier`, a transform applied to *any* color: `variations.state.hovered.apply(theme.palette.cyan)`. They're grouped into nested family structs so the intent is clear and completion narrows step by step.

```zig
pub const Variations = struct {
    lightness: Lightness,
    emphasis: Emphasis,
    state: State,
    surface: Surface,
    line: Line,
    contrast: Contrast,
    alpha: Alpha,

    /// Absolute: ignores mode. Qt Light/Midlight/Dark/Shadow, Tailwind/Radix scales, ANSI bright.
    pub const Lightness = struct {
        lightest: Modifier, lighter: Modifier, light: Modifier,
        dark: Modifier, darker: Modifier, darkest: Modifier,
        bright: Modifier,                                   // terminal "bright" colors
    };

    /// Mode-aware: more / less contrast against the background.
    /// Apple label hierarchy, Radix steps 11–12, GTK dim-label.
    pub const Emphasis = struct {
        strong: Modifier, muted: Modifier, subtle: Modifier, faint: Modifier,
    };

    /// Interaction and window focus. CSS pseudo-classes, GTK states, Material state layers,
    /// Fluent, JetBrains, Qt Inactive group / GTK :backdrop.
    pub const State = struct {
        hovered: Modifier, pressed: Modifier, focused: Modifier,
        selected: Modifier, checked: Modifier, dragged: Modifier, visited: Modifier,
        disabled: Modifier, placeholder: Modifier,
        inactive: Modifier,                                 // unfocused window / widget
        selected_inactive: Modifier,                        // default: selected, then inactive
    };

    /// Mode-aware elevation. GTK shade/card/popover, Material surface containers, Qt Shadow.
    pub const Surface = struct {
        sunken: Modifier, raised: Modifier, overlay: Modifier, shadow: Modifier,
    };

    /// libadwaita borders, Material outline / outlineVariant.
    pub const Line = struct {
        border: Modifier, border_strong: Modifier, separator: Modifier,
    };

    /// Readable foreground *on* this color. Material onPrimary, libadwaita accent_fg_color.
    pub const Contrast = struct {
        on: Modifier, on_muted: Modifier,
    };

    /// Low-alpha washes. Material state layers, editor selection / search highlights.
    pub const Alpha = struct {
        translucent: Modifier, highlight: Modifier,
    };

    pub fn from(mode: Mode) Variations { … }            // mode-aware defaults
};
```

- **D12.** There are 33 variations in 7 families, and `Variations.from(mode)` provides every default. Mode-aware families (emphasis, surface, state) invert direction in light mode, e.g. `hovered` darkens.
- **D13. Variations transform; they never choose hues.** `error`, `warning` and the like are a module's decision (`error = palette.red`), not variations.
- **D14. `active` is deliberately absent.** It means "pressed" in CSS and "focused window" in Qt, so it's split into `state.pressed` and `state.inactive`.
- **D15. A `Modifier` is one of:**
  - OKLCH deltas (`lightness`, `chroma`, `hue`) plus optional `alpha`;
  - a mix toward a color (`mix = .{ .toward = …, .amount = 0.5 }`);
  - a contrast function (`contrast.on` / `on_muted`: picks a readable color);
  - a **composition** of sibling variations (`.compose = &.{ .state_selected, .state_inactive }`).
- **D16. Compositions are references, resolved when applied.** That's the one exception to D3, and it's what makes tweaking `state.selected` also change `state.selected_inactive`. Users can write their own: `variations.state.selected.then(variations.state.hovered)`.

## 5. Kosmoi

- **D17. A kosmos is a public function returning a struct of modules.**
  - Each `pub fn` in a file under `kosmoi/` that returns such a struct is a kosmos: `kosmos()` is the file's default, and any other name is a variant.
  - `kosm apply frost` → `frost.kosmos()`; `kosm apply frost.iced` → `frost.iced()`.
  - One file or many is your choice: nothing forces a base/frost split.
- **D18. The returned tree is the selection.** Kosm walks the returned struct recursively. Any field whose type has `pub fn apply` is a module, and any other struct is recursed into. Only modules that appear in the tree are applied. A website-only kosmos returns `struct { website: website.Module }`.
- **D19. Parameters become CLI flags.** A kosmos function may take one `Params` struct. Kosm parses `kosm apply frost --accent '#ff0000' --blur false` into it by reflection. Field types decide parsing, and colors accept hex or a palette name like `sky`. Fields should be optional with defaults.
- **D20. `--set` pokes the final tree.** `--set hyprland.blur.size=20` runs after the kosmos function returns and walks the tree by reflection. It's for one-off tweaks: it assigns a result, so nothing derived from it changes (D3).
- **D21. Kosmos functions may return an error union** (`!Base`). Kosm reports the error with the kosmos name.

```zig
// kosmoi/base.zig
const kosm = @import("kosm");
const hyprland = @import("kosm-hyprland");
const browser = @import("kosm-browser");

pub const Base = struct {
    hyprland: hyprland.Module,
    browser: browser.Module,
};

pub fn from(theme: kosm.Theme) Base {
    var result: Base = .{
        .hyprland = hyprland.from(theme),
        .browser = browser.from(theme),
    };
    result.browser.colors.links = kosm.hex("324212");
    return result;
}
```

```zig
// kosmoi/frost.zig
const kosm = @import("kosm");
const base = @import("base.zig");

pub const frost_palette: kosm.Palette = .{
    .black = kosm.hex("102840"), .white = kosm.hex("eceff4"),
    .red = kosm.hex("bf616a"), .yellow = kosm.hex("ebcb8b"), .blue = kosm.hex("5e81ac"),
};

pub fn frostTheme(palette: kosm.Palette) kosm.Theme {
    var theme = kosm.Theme.from(palette, .dark);
    theme.variations.state.hovered.lightness = 0.06;
    return theme;
}

pub fn build(theme: kosm.Theme) base.Base {
    var result = base.from(theme);
    result.hyprland.blur.size = 10;
    return result;
}

pub const Params = struct { blur: ?bool = null };

pub fn kosmos(params: Params) base.Base {
    var result = build(frostTheme(frost_palette));
    if (params.blur) |blur| result.hyprland.blur.enabled = blur;
    return result;
}

pub fn iced() base.Base {
    var palette = frost_palette;
    palette.red = kosm.hex("5e81ac");                 // input change: everything derived follows
    const theme = frostTheme(palette);
    var result = build(theme);                        // frost's tweaks are kept
    const hyprland_module = &result.hyprland;         // plain pointer for repeated edits
    hyprland_module.colors.border_active = theme.palette.blue;
    hyprland_module.blur.passes = 4;
    return result;
}
```

## 6. App modules

- **D22. A module package exports `Module` (a struct of plain fields), `from`, and `Module.apply`.**
  - `from(theme)`, or `from(theme, required)` when the module has required inputs. `required` is a struct whose fields have **no defaults**, so leaving one out is a compile error naming the field. That's how a maintainer makes e.g. a glow color mandatory.
  - Every other field is filled with a sane default by `from` and can be overwritten by assignment.
  - New fields can be added at any time without breaking existing kosmoi.
  - `apply(self: Module, output: *kosm.Output) !void` contains no parsing and no file IO, only calls on `output`.
- **D23. Derived-from-sibling fields are `?Color = null`.** If a module color is naturally derived from another *module* field (e.g. `border_inactive` from `border_active`), it's declared `?Color = null` and computed in `apply`. So changing `border_active` after `from` still flows into it, and setting `border_inactive` explicitly still wins.
- **D24.** A module stores whatever it needs from the theme inside its own fields during `from`. `apply` only sees `self`.

```zig
// kosm-hyprland/src/root.zig
const kosm = @import("kosm");

pub const Module = struct {
    colors: struct {
        border_active: kosm.Color,
        border_inactive: ?kosm.Color = null,          // null → inactive variation of border_active
        glow: kosm.Color,
    },
    border_size: u16 = 2,
    blur: struct { enabled: bool = true, size: u16 = 8, passes: u8 = 2 } = .{},
    inactive: kosm.Modifier,

    pub fn apply(self: Module, output: *kosm.Output) !void {
        var file = try output.edit(.{ .files = "~/.config/hypr/**/*.lua" });
        const inactive_border = self.colors.border_inactive orelse self.inactive.apply(self.colors.border_active);
        try file.set("general.active_border", self.colors.border_active.format("rgba({hex8})"));
        try file.set("general.inactive_border", inactive_border.format("rgba({hex8})"));
        try file.set("decoration.glow.color", self.colors.glow.format("rgba({hex8})"));
        try file.set("decoration.blur.enabled", self.blur.enabled);
        try file.set("decoration.blur.passes", self.blur.passes);
    }
};

pub fn from(theme: kosm.Theme) Module {
    return .{
        .colors = .{ .border_active = theme.palette.cyan, .glow = theme.palette.red },
        .inactive = theme.variations.state.inactive,
    };
}
```

- **D25. Local modules: kosm owns whatever you tell it to own.** Any `.zig` file in `~/.config/kosm/modules/` with the same shape is a module, just not packaged. Use it to point kosm at *your* files:

  ```zig
  // ~/.config/kosm/modules/hypr_defs.zig
  pub const Module = struct {
      blur: bool = true,
      border_active: kosm.Color,
      terminal: []const u8 = "ghostty",

      pub fn apply(self: Module, output: *kosm.Output) !void {
          var file = try output.edit(.{ .files = "~/.config/hypr/defs.lua" }); // lang from .lua
          try file.set("M.blur.enabled", self.blur);
          try file.set("M.border.active_col", self.border_active.format("rgba({hex8})"));
          try file.set("M.apps.terminal", self.terminal);
      }
  };

  pub fn from(theme: kosm.Theme) Module {
      return .{ .border_active = theme.palette.cyan };
  }
  ```

  Packaged modules are just local modules that someone shared. Non-color values (terminal, main_mod, …) are just module fields, so a kosmos can hold anything.
- **D26.** The adapter is inferred from the file extension unless `.lang` is given. If several installed adapters claim the same extension, that's an error asking for `.lang`.
- **D27. Conventions for module authors (non-binding).** These keep independent modules consistent:
  - background/foreground come from `black`/`white`, swapped in light mode;
  - comment/muted text uses `emphasis.muted` on the foreground;
  - error/warning/success/info are `red`/`yellow`/`green`/`blue`;
  - accent and active border are `cyan`;
  - every field and its default is listed in the module's README.

## 7. Writers

Four writers. A module chooses whichever fits each target.

| Writer | Use when | Needs from adapter |
|---|---|---|
| `generate` | the app can include/import a data file (Lua `require`, CSS `@import` + `var()`, kitty `include`) | `serialize` |
| `template` | the output is mostly structure rather than values (nvim colorscheme, fastfetch) | nothing |
| `block` | a line format, no includes, comments allowed: kosm owns `# kosm:begin <id>` … `# kosm:end` | `comment` syntax |
| `edit` (path) | set exact keys in a file you also edit by hand | `parse` + `match` + `format` |

### 7.1 Path editing semantics

- **D28. Missing means error.** Zero matches is always an error, whatever the cardinality. (G6.)
- **D29. Literal or not, we overwrite.** If the current value is an expression (`defs.blur.enabled`), it still gets replaced. Being careful is the user's job. The usual way to avoid it is to target the file where the literal lives (D25).
- **D30. Paths follow the language, not just tables.** Adapters map *every* way a language nests keys onto the same path, so `M.blur = { enabled = true }`, `M.blur.enabled = true` and `hl.config({ M = { blur = { enabled = true } } })` all match `M.blur.enabled`.
- **D31. Cardinality is explicit**, as one concept with sugar on top:

  | Call | Matches allowed | Edits |
  |---|---|---|
  | `set(path, value)` | exactly 1 | that one |
  | `setFirst(path, value)` | ≥ 1 | first |
  | `setAll(path, value)` | ≥ 1 | all |
  | `setNth(path, n, value)` | ≥ n+1 | the n-th |
  | `setIndices(path, &.{1, 3, 8}, value)` | every listed index exists | those |
  | `setRange(path, 2, 5, value)` | every index in `[2, 5)` exists | those |

  They all lower to `setOptions(path, value, .{ .match = … })`. Indices are 0-based, in match order (files sorted by path, then file order). **This list is closed: no more variants are ever added.** Anything fancier uses the escape hatch (D34).

  A real example of why `set` defaults to exactly-one: `decoration.blur.enabled` exists in **both** `hypr/hyprland/decoration/blur.lua` and `hypr/hyprland/gamemode.lua`. A blind `setAll` would break gamemode. `set` errors and tells you to narrow the file scope.
- **D32. Path syntax:** dot-separated segments. A segment containing a dot is quoted: `general."col.active_border"`. `*` matches exactly one level. **No `**`, predicates or regex in v1.** Tuple form `.{ "general", "col.active_border" }` is also accepted.
- **D33. Scope narrowing** goes through the file selector (`files`, `exclude`), not the path language.
- **D34. Escape hatch:** `file.nodes(path)` returns the raw matches (file, byte range, adapter node).
- **D35. Byte-preserving:** only the value's byte range is replaced. If a value is unchanged, the file isn't rewritten.

### 7.2 Transactional apply

- **D36.** `kosm apply` happens in two phases. **Plan:** call the kosmos function, apply `--set`, call every module's `apply`, and compute every edit in memory. Any error aborts, and nothing is touched. **Commit:** write temp files, then rename them all. Then run the reload hooks.
- **D37.** `kosm apply frost --diff` prints the plan as a unified diff and writes nothing.
- **D38.** Two modules editing the same byte range in the same apply is a plan-time error.

## 8. Language adapters

- **D39.** An adapter is a package exporting a declaration that matches the adapter interface. **Every capability is optional**, and kosm reports clearly when a module needs a capability that an adapter lacks.

```zig
// kosm-lua/src/root.zig
pub const adapter = kosm.Adapter{
    .name = "lua",
    .extensions = &.{".lua"},
    .comment = .{ .line = "--" },                        // enables `block`
    .format = formatValue,                               // value → source text (true, "str", 1.0)
    .serialize = serialize,                              // value tree → whole file (enables `generate`)
    .parser = kosm.treesitter.parser(tree_sitter_lua, .{ // enables `edit`
        .pair = "field",
        .key = "name",
        .value = "value",
        .nest = &.{"table_constructor"},
        .assign = .{ .node = "assignment_statement", .target = "dot_index_expression" },
        .transparent = &.{ "function_call", "arguments" }, // hl.config({...}) is path-invisible
    }),
};
```

- **D40.** Most tree-sitter adapters should be **declarative** (node names, as above). Hand-written `match` functions are allowed for strange grammars. Adapters may skip tree-sitter entirely (e.g. a 40-line INI parser).
- **D41.** **Kosm core owns the tree-sitter runtime.** Adapters depend on core and ship only their grammar's C sources, which avoids duplicate symbols.
- **D42.** Value formatting has two cases: `string`, which the adapter quotes and escapes, and `kosm.raw(text)`, which is inserted verbatim. Colors are formatted by the **module** (`color.format("rgba({hex8})")`), because only the module knows the app's color syntax.

## 9. Packages and the config project

```
~/.config/kosm/              # a Zig project, generated by `kosm init`
├── build.zig                # generic; reads build.zig.zon, exposes every package to kosmoi + modules
├── build.zig.zon            # `kosm add` writes dependencies here
├── packages.zon             # refs to follow for `kosm update` (D46)
├── modules/                 # optional: local modules (D25)
└── kosmoi/
    ├── base.zig
    ├── frost.zig
    └── …
```

- **D43. Seamless install:** `build.zig` imports `build.zig.zon` at comptime, iterates `.dependencies`, and makes every package importable by name from `kosmoi/` and `modules/` (`@import("kosm-hyprland")`). It also discovers every `pub fn` kosmos (D17). No hand-editing of build.zig. **Verify on Zig 0.17 first.**
- **D44.** Pin a tagged Zig (currently 0.17.0) via `minimum_zig_version`. Never track master.
- **D45.** `kosm apply <kosmos>` = `zig build` in the config dir (cached), then run. Error output should point at the user's kosmos file, not at generated code.

## 10. CLI (v1)

```
kosm init                            # create ~/.config/kosm
kosm new <kosmos>                    # scaffold kosmoi/<kosmos>.zig
kosm apply <file>[.<variant>] [--<param> value]... [--set path=value]... [--diff]
kosm list                            # kosmoi + variants, installed packages
kosm current                         # what's applied (kosm records the last apply)

kosm add <url>[#ref]                 # zig fetch --save in the config dir + validate it's a kosm package
kosm remove <name>
kosm update [name]                   # re-fetch packages at their tracked ref, rebuild
```

- **D46. Package commands wrap `zig fetch`.** No custom package format or registry. `add` checks that the package provides at least one module or adapter, and reports what it provides. `build.zig.zon` stores only the resolved URL + hash, which loses "follow branch `main`", so kosm keeps that intent in `packages.zon` (name → url + ref), and `update` re-runs `zig fetch --save=<name>` from it.

## 11. Build order

Each step is usable on its own.

1. **Core data:** Color (OKLCH, formatting), Modifier, Variations, Palette + wheel resolution, Theme. Pure, with tests and no files.
2. **Packaging spike:** prove D43 (package imports + kosmos discovery + D19 params) on Zig 0.17. If it fails, redesign §9 before going further.
3. **Writers:** `generate` + `template`, plus 3 built-in modules (kitty, one CSS app, nvim). Rice the real Frost end to end. Implement D36–D38 here.
4. **`block` writer.**
5. **`edit` writer:** tree-sitter runtime in core, then `kosm-json`, then `kosm-lua`, then `kosm-hyprlang`.
6. `kosm add/remove/update`, reload hooks, `current`, `--set`.

## 12. Non-goals (v1)

- Inserting missing keys (D28).
- `**`, predicates or regex in paths.
- Global semantic colors (bg, fg, roles): these belong to modules (D11).
- `.with` / `.override` patch APIs (D4, G8).
- Wallpaper → palette generation (could be a package later).
- Any custom configuration language.
- LSP integration.
