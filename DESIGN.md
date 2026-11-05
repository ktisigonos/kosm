# Kosm - Design (Draft v0.5)

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
 KOSMOS                 APPS                        LANGUAGE ADAPTERS + WRITERS
 what the rice is   ->   what an app needs     ->     how bytes reach a file
 (user: functions       (packages: fields +         (packages, written once per language)
  returning apps)        from + apply)
```

- **D1.** The three layers never mix. An app never parses anything. An adapter never knows about any app.
- **D2.** Everything is a Zig package. One package can export any mix of adapters, apps and kosmoi. Kosm's own built-ins are written exactly like third-party packages.
- **D54. Vocabulary.** These four words mean exactly this, everywhere (docs, code, CLI output):
  - **package**: Zig's own term, anything `kosm add` fetches. A package can contain apps, adapters and/or kosmoi.
  - **app**: support for one program (`kosm_hyprland` exports `App`, `from`, `App.apply`).
  - **adapter**: support for one language or file format (Lua, TOML, JSON).
  - **kosmos**: a rice, a function returning a tree of apps.

  "Module" is left to Zig's own meaning (`b.addModule`) and is never used for apps.

## 3. The core rule (style A)

- **D3. Inputs before `from`, tweaks after.** Every layer works the same way. `from(inputs)` derives a complete struct of plain fields, and you change any field afterwards by assignment.
  - Want a change to *flow* into everything derived from it? Change the **input** and call `from` again.
  - Want to change one *result*? Assign the field.
- **D4. Inheritance is a function call.** A kosmos that builds on another calls the other's build function with different inputs, then assigns its own tweaks. No `.with`, no `.override`, no merge magic.
- **D5. Nothing is written until kosm says so.** User code only builds values. Kosm calls each app's `apply` at the end, plans every edit, and commits all or nothing (section 7.2). User code never calls `apply`.

## 4. Theme: the only standard

`kosm.Theme` is what every app's `from` receives. It has three parts: **palette**, **mode** and **variations**.

```zig
var theme = kosm.Theme.from(palette, .dark);
theme.variations.state.hovered.lightness = 0.06;   // tweak once, for every app built from this theme
```

### 4.1 Palette: the 12-hue wheel

```
red - orange - yellow - lime - green - teal - cyan - sky - blue - purple - magenta - pink
 0      30       60      90     120    150    180   210   240     270      300      330   (hue, deg)
```

- **D6.** `kosm.Palette` (the input) has **`black` and `white` as required fields**, and all 12 hues as `?Color = null`.
- **D7. Missing hues are mixed from the nearest set hues on either side of the wheel**, by *wheel position*, not by actual hue. So if `red` and `yellow` are both blues (FrostIced), the derived `orange` is a blue as well. Mixing happens in OKLCH. One set hue means every hue is that hue. No set hues means every hue derives from `gray`.
- **D8.** `gray` is always derived: mix(black, white). It can be overridden on the resolved palette.
- **D9.** `theme.palette` is the **resolved** palette (`kosm.Palette.Resolved`): all 12 hues, plus black, white and gray, all non-optional. Apps only ever see this one.
- **D10.** Extra colors beyond the wheel belong to apps (their own fields) or to your own consts. The wheel is the only shared vocabulary.

### 4.2 Mode

- **D11.** `mode: .dark | .light`. That's the single global fact apps use to decide their own background, foreground, buttons and so on. There is no global `bg`/`fg`/`button`/`outline`: every one of those belongs to an app.

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
    /// Apple label hierarchy, Radix steps 11-12, GTK dim-label.
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
        selected_inactive: ?Modifier = null,                // null: selected, then inactive

        pub fn selectedInactive(self: State) Modifier { ... } // read the composition through this
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

    pub fn from(mode: Mode) Variations { ... }            // mode-aware defaults
};
```

- **D12.** There are 33 variations in 7 families, and `Variations.from(mode)` provides every default. Mode-aware families (emphasis, state, surface, line) invert direction in light mode, e.g. `hovered` darkens. `Theme.from` points `contrast.on`/`on_muted` at the palette's black and white, and `surface.shadow` at its black.
- **D13. Variations transform; they never choose hues.** `error`, `warning` and the like are an app's decision (`error = palette.red`), not variations.
- **D14. `active` is deliberately absent.** It means "pressed" in CSS and "focused window" in Qt, so it's split into `state.pressed` and `state.inactive`.
- **D15. A `Modifier` is a struct of optional parts**, applied in this order: OKLCH deltas (`lightness`, `chroma`, `hue`; chroma never drops below 0, hue wraps), a mix toward a color (`mix = .{ .toward = ..., .amount = 0.5 }`), a contrast pick (`contrast`: whichever of two candidates has the higher WCAG 2 contrast ratio on the color, optionally mixed back toward it, for `contrast.on` / `on_muted`), and finally an absolute `alpha`. Each part is a plain field, so `hovered.lightness = 0.06` works.
- **D16. Compositions are copies, read through a method.** `a.then(b)` returns a modifier that applies `a`, then `b`, holding up to 8 steps inline (no memory needed). A copied modifier can't look anything up later (D24: `apply` only sees `self`), so variations that default to a composition are `?Modifier = null` and are read through a method, like D23's derived colors: `state.selectedInactive()` returns `selected_inactive orelse selected.then(inactive)`. That's what makes tweaking `state.selected` also change it, for every app built afterwards.

### 4.4 Color

- **D47. Colors are formatted with a template and a list of components.** `color.format("rgba({}, {}, {}, {})", &.{ .red_255, .green_255, .blue_255, .alpha_01 })`: each `{}` takes the next component, `{{` and `}}` are literal braces. The template and the list are comptime, so a typo in a component or a count mismatch is a compile error (G8). Shortcuts: `color.hex()` (`#rrggbb`) and `color.hex8()` (`#rrggbbaa`).
- **D48. Colors are OKLCH in f64, and out-of-gamut values are kept.** Nothing is clamped while colors are built, mixed or modified, since some apps (game engines, HDR) want values beyond sRGB. Clipping happens only when printing bytes (`red_255`, `hex`, ...); float components (`red_01`, `lightness`, ...) print the real value.
- **D49. `kosm.hex(text)` is comptime**, so a bad literal is a compile error. It takes `rgb`, `rgba`, `rrggbb` or `rrggbbaa` with an optional `#`. `Color.parseHex` is the runtime version and returns an error; params and `--set` use it.

## 5. Kosmoi

- **D17. A kosmos is a public function returning a struct of apps.**
  - A kosmos is a `pub fn` in a kosmos file (D62: `kosmoi/frost.zig`, or `kosmoi/nord/root.zig`) that takes either nothing or one `Params` struct whose fields all have defaults, and returns (optionally through `!`) a struct containing at least one app (D53). Helpers like `frostTheme(palette)` or `build(theme)` therefore aren't kosmoi.
  - Each one is applied by name: `kosmos()` is the file's default, and any other name is a variant.
  - `kosm apply frost` -> `frost.kosmos()`; `kosm apply frost.iced` -> `frost.iced()`.
  - One file or many is your choice: nothing forces a base/frost split.
- **D18. The returned tree is the selection.** Kosm walks the returned struct recursively. **D53:** a field is an app when its type is a struct with exactly `pub fn apply(self, *kosm.Output) !void` (so `Modifier.apply(Color) Color` doesn't count), and any other struct is recursed into. An optional app (`?hyprland.App`) set to `null` is skipped. Only apps that appear in the tree are applied. A website-only kosmos returns `struct { website: website.App }`.
- **D19. Parameters become CLI flags.** A kosmos function may take one `Params` struct. Kosm parses `kosm apply frost --accent '#ff0000' --blur false` into it by reflection. Field types decide parsing (colors: D55). Fields should be optional with defaults. A bool flag always takes a value (`--blur false`), and no field may be named `diff` or `config`, which are kosm's own flags.
- **D55. Colors in flags.** A `kosm.Color` field accepts every common text form: `#rgb`, `#rrggbb`, `#rrggbbaa` (with or without `#`), `rgb(...)`, `rgba(...)`, `hsl(...)`, `hsla(...)` and `oklch(...)`. A `kosm.ColorChoice` field additionally accepts a hue name (`--accent sky`). Kosm can't know the kosmos' palette while parsing, so the kosmos resolves it with `params.accent.resolve(theme.palette)`. Flags are spelled `--border-size`; the field spelling `--border_size` is accepted too.
- **D56. Hosts are opt-in.** If `Params` has a field `host` of an enum type the user declares (`pub const Host = enum { nous, egregoros, ergasterion, synekdemos };`), kosm fills it from the machine's hostname. An unknown hostname is an error naming the hostname and the enum. Without such a field nothing happens, so kosmoi that don't care never see hosts. Combined with optional apps (D53), `if (params.host == .ergasterion) result.hyprland = null;` skips an app on one machine.
- **D20. `--set` pokes the final tree.** `--set hyprland.blur.size=20` runs after the kosmos function returns and walks the tree by reflection. It's for one-off tweaks: it assigns a result, so nothing derived from it changes (D3).
- **D50. Kosmoi, apps and adapters import each other by name**, like packages: `@import("base")`, `@import("hypr_defs")`, never `@import("base.zig")`. Each one is its own Zig module, and Zig doesn't allow a file in two modules. Names must be unique among your local kosmoi, apps, adapters and installed packages; kosm errors on a collision, naming both. Files *inside* a directory kosmos, app or adapter (D62) are private to it and import each other relatively (`@import("colors.zig")`).
- **D62. A file is private, a directory is a package.** The same rule holds for `kosmoi/`, `apps/` and `adapters/`:
  - `kosmoi/frost.zig`: a single-file kosmos. It has no manifest and can't be installed by others (they can still copy the file).
  - `kosmoi/nord/` with `root.zig`, plus any files, templates and subdirectories it needs: a directory kosmos. It carries a `build.zig.zon` and a minimal `build.zig` that only calls kosm's helper (`pub fn build(b: *std.Build) void { @import("kosm").package(b); }`), so it's an ordinary Zig package: ZLS completion, `zig build test` and `zig fetch --save` all work inside it, also when someone develops it on its own outside a config. All the logic lives in kosm's `package` helper, so the generated `build.zig` never changes. Publishing it means pushing that directory as a git repo, and others `kosm add` it and use it as `@import("nord")` or `kosm apply nord.iced`. (A zon-only package would also work, verified on 0.17, but the standard shape costs nothing since kosm generates it.)
  - **Kosm keeps that manifest up to date when it builds that one kosmos.** `kosm apply nord` regenerates `kosmoi/nord/build.zig.zon`, and nothing else: `kosm apply frost` doesn't touch nord. Kosm writes `build.zig`, and the manifest's `.name`, `.fingerprint`, `.version` and `.minimum_zig_version`, once and never changes them afterwards. On every build it rewrites `.dependencies` (`kosm` itself plus exactly the installed packages nord imports, copied with their url and hash from the config's own `build.zig.zon`, which stays the source of truth) and `.paths` (every file in the directory).
  - If a directory kosmos imports a *local* kosmos, app or adapter that isn't a directory package (e.g. `@import("base")` where `base` is `kosmoi/base.zig`), regenerating its manifest is an error naming the import, because the published package couldn't resolve it.
- **D21. Kosmos functions may return an error union** (`!Base`). Kosm reports the error with the kosmos name.

```zig
// kosmoi/base.zig
const kosm = @import("kosm");
const hyprland = @import("kosm_hyprland");
const browser = @import("kosm_browser");

pub const Base = struct {
    hyprland: hyprland.App,
    browser: browser.App,
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
const base = @import("base");                       // by name (D50)

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
    const hyprland_app = &result.hyprland;         // plain pointer for repeated edits
    hyprland_app.colors.border_active = theme.palette.blue;
    hyprland_app.blur.passes = 4;
    return result;
}
```

## 6. Apps

- **D22. An app package exports `App` (a struct of plain fields), `from`, and `App.apply`.**
  - `from(theme)`, or `from(theme, required)` when the app has required inputs. `required` is a struct whose fields have **no defaults**, so leaving one out is a compile error naming the field. That's how a maintainer makes e.g. a glow color mandatory.
  - Every other field is filled with a sane default by `from` and can be overwritten by assignment.
  - New fields can be added at any time without breaking existing kosmoi.
  - `apply(self: App, output: *kosm.Output) !void` contains no parsing and no file IO, only calls on `output`.
- **D23. Derived-from-sibling fields are `?Color = null`.** If an app color is naturally derived from another *app* field (e.g. `border_inactive` from `border_active`), it's declared `?Color = null` and computed in `apply`. So changing `border_active` after `from` still flows into it, and setting `border_inactive` explicitly still wins.
- **D24.** An app stores whatever it needs from the theme inside its own fields during `from`. `apply` only sees `self`.

```zig
// kosm_hyprland/src/root.zig
const kosm = @import("kosm");

pub const App = struct {
    colors: struct {
        border_active: kosm.Color,
        border_inactive: ?kosm.Color = null,          // null -> inactive variation of border_active
        glow: kosm.Color,
    },
    border_size: u16 = 2,
    blur: struct { enabled: bool = true, size: u16 = 8, passes: u8 = 2 } = .{},
    inactive: kosm.Modifier,

    pub fn apply(self: App, output: *kosm.Output) !void {
        var file = try output.edit(.{ .files = "~/.config/hypr/**/*.lua" });
        const inactive_border = self.colors.border_inactive orelse self.inactive.apply(self.colors.border_active);
        try file.set("general.active_border", self.colors.border_active.format("rgba({})", &.{.hex8}));
        try file.set("general.inactive_border", inactive_border.format("rgba({})", &.{.hex8}));
        try file.set("decoration.glow.color", self.colors.glow.format("rgba({})", &.{.hex8}));
        try file.set("decoration.blur.enabled", self.blur.enabled);
        try file.set("decoration.blur.passes", self.blur.passes);
    }
};

pub fn from(theme: kosm.Theme) App {
    return .{
        .colors = .{ .border_active = theme.palette.cyan, .glow = theme.palette.red },
        .inactive = theme.variations.state.inactive,
    };
}
```

- **D25. Local apps: kosm owns whatever you tell it to own.** Any app in `~/.config/kosm/apps/` (a file or a directory, D62) with the same shape is an app, just not installed from a package. Use it to point kosm at *your* files:

  ```zig
  // ~/.config/kosm/apps/hypr_defs.zig
  pub const App = struct {
      blur: bool = true,
      border_active: kosm.Color,
      terminal: []const u8 = "ghostty",

      pub fn apply(self: App, output: *kosm.Output) !void {
          var file = try output.edit(.{ .files = "~/.config/hypr/defs.lua" }); // lang from .lua
          try file.set("M.blur.enabled", self.blur);
          try file.set("M.border.active_col", self.border_active.format("rgba({})", &.{.hex8}));
          try file.set("M.apps.terminal", self.terminal);
      }
  };

  pub fn from(theme: kosm.Theme) App {
      return .{ .border_active = theme.palette.cyan };
  }
  ```

  Packaged apps are just local apps that someone shared. Non-color values (terminal, main_mod, ...) are just app fields, so a kosmos can hold anything.
- **D26.** The adapter is inferred from the file extension unless `.lang` is given. If several installed adapters claim the same extension, that's an error asking for `.lang`.
- **D27. Conventions for app authors (non-binding).** These keep independent apps consistent:
  - background/foreground come from `black`/`white`, swapped in light mode;
  - comment/muted text uses `emphasis.muted` on the foreground;
  - error/warning/success/info are `red`/`yellow`/`green`/`blue`;
  - accent and active border are `cyan`;
  - every field and its default is listed in the app's README.

## 7. Writers

Four writers. An app chooses whichever fits each target.

| Writer | Use when | Needs from adapter |
|---|---|---|
| `generate` | the app can include/import a data file (Lua `require`, CSS `@import` + `var()`, kitty `include`) | `serialize` |
| `template` | the output is mostly structure rather than values (nvim colorscheme, fastfetch) | nothing |
| `block` | a line format, no includes, comments allowed: kosm owns `# kosm:begin <id>` ... `# kosm:end` | `comment` syntax |
| `edit` (path) | set exact keys in a file you also edit by hand | `parse` + `match` + `format` |

- **D60. Template placeholders are fixed: `kosm.<path>` or `{kosm.<path>}`.** Neither the prefix nor the braces are configurable.
  - **Bare:** `kosm.palette.red`. The prefix is what marks a placeholder, so no other text is ever touched. It ends at the first character that can't continue a path (letters, digits and `_`, plus `.` only when a letter follows, so a sentence-ending `.` is left alone).
  - **Braced:** `{kosm.palette.red}` or `{ kosm.palette.red }`, for text glued on: `{kosm.rounding}px`. It ends at the `}`. Only a `{` followed by optional spaces and `kosm.` counts; every other brace (JSON, CSS, Lua, mustache) is plain text.
  - Paths resolve against the app's own fields. Color components are trailing segments with the D47 names (`kosm.palette.red.hex8`, `{kosm.colors.links.red_255}`); a color without one prints in the file's color format (D61).
  - An unknown path is an error naming the template, line and nearest field (`kosm.roundingpx`: did you mean `{kosm.rounding}px`?), never a silent pass-through (G6). Templates shipped inside a package are checked at compile time.
  - No loops or conditionals in v1.
- **D61. Every written file has a color format, set in layers.** A color printed without an explicit component (a template's `kosm.palette.red`, a `generate`d value, an `edit` value) uses the first of:
  1. the file's own setting, an ordinary app field (e.g. `color_format: kosm.ColorFormat`), which users override by assignment like any other field (D3);
  2. the app's default for that file, set in `from`;
  3. the adapter's default for its language (e.g. CSS -> `hex8`);
  4. `hex`.

  `kosm.ColorFormat` is a runtime value with the same template-and-components shape as D47, so it can be stored in a field. Predefined ones (`.hex`, `.hex8`, ...) are constants. An explicit component in a placeholder (`kosm.palette.red.red_255`) always wins.
- **D64. `generate` takes a plain struct.** `try output.generate(.{ .file = "~/.config/kitty/kosm.conf" }, .{ .foreground = self.foreground, .color0 = ... })`: the second argument is any plain struct (strings, numbers, bools, colors, nested structs), which kosm turns into a `kosm.Value` tree by reflection and hands to the adapter's `serialize`. It's an `anytype`, but a value, not a patch API (G8). An app whose fields don't map one to one onto the file (renamed enum tags, unit suffixes) may build the `kosm.Value` tree itself and pass that; a `kosm.Value` is taken as it is.
- **D65. `template` takes the app and comptime text.** `try output.template(self, .{ .file = "~/.config/nvim/lua/theme.lua", .text = @embedFile("templates/theme.lua"), .color_format = self.color_format })`. Placeholders resolve against `self`'s fields, and since `.text` is comptime, they're checked at compile time (D60). `.color_format` is the file's format (D61). Templates live in the app's own package directory (`templates/`), so `@embedFile` stays inside the module root.
- **D57. Kosm never wires files together.** It writes what an app tells it to write and nothing else. Making the program read a generated file (kitty's `include`, a Lua `require`, a CSS `@import`) is the user's job, done once in their own config. Kosm never inserts include or source lines.
- **D58. No backups.** Kosm never writes `.backup` copies. Git, the all-or-nothing commit (D36) and `--diff` (D37) cover it.

### 7.1 Path editing semantics

- **D28. Missing means error.** Zero matches is always an error, whatever the cardinality. (G6.)
- **D29. Literal or not, we overwrite.** If the current value is an expression (`defs.blur.enabled`), it still gets replaced. Being careful is the user's job. The usual way to avoid it is to target the file where the literal lives (D25).
- **D30. Paths follow the language, not just tables.** Adapters map *every* way a language nests keys onto the same path, so `M.blur = { enabled = true }`, `M.blur.enabled = true` and `hl.config({ M = { blur = { enabled = true } } })` all match `M.blur.enabled`.
- **D31. Cardinality is explicit**, as one concept with sugar on top:

  | Call | Matches allowed | Edits |
  |---|---|---|
  | `set(path, value)` | exactly 1 | that one |
  | `setFirst(path, value)` | >= 1 | first |
  | `setAll(path, value)` | >= 1 | all |
  | `setNth(path, n, value)` | >= n+1 | the n-th |
  | `setIndices(path, &.{1, 3, 8}, value)` | every listed index exists | those |
  | `setRange(path, 2, 5, value)` | every index in `[2, 5)` exists | those |

  They all lower to `setOptions(path, value, .{ .match = ... })`. Indices are 0-based, in match order (files sorted by path, then file order). **This list is closed: no more variants are ever added.** Anything fancier uses the escape hatch (D34).

  A real example of why `set` defaults to exactly-one: `decoration.blur.enabled` exists in **both** `hypr/hyprland/decoration/blur.lua` and `hypr/hyprland/gamemode.lua`. A blind `setAll` would break gamemode. `set` errors and tells you to narrow the file scope.
- **D32. Path syntax:** dot-separated segments. A segment containing a dot is quoted: `general."col.active_border"`. `*` matches exactly one level. **No `**`, predicates or regex in v1.** Tuple form `.{ "general", "col.active_border" }` is also accepted.
- **D33. Scope narrowing** goes through the file selector (`files`, `exclude`), not the path language.
- **D34. Escape hatch:** `file.nodes(path)` returns the raw matches (file, byte range, adapter node).
- **D35. Byte-preserving:** only the value's byte range is replaced. If a value is unchanged, the file isn't rewritten.

### 7.2 Transactional apply

- **D36.** `kosm apply` happens in two phases. **Plan:** call the kosmos function, apply `--set`, call every app's `apply`, and compute every edit in memory. Any error aborts, and nothing is touched. **Commit:** write temp files, then rename them all. Reloading apps afterwards is D59.
- **D37.** `kosm apply frost --diff` prints the plan as a unified diff and writes nothing.
- **D38.** Two apps editing the same byte range in the same apply is a plan-time error.
- **D59. Reloading is the app's job, not core's.** Each app knows how its program reloads. The mechanism is designed in step 6 (Q16); core only provides whatever hook an app needs to run after the commit, since `apply` runs before anything is written.

## 8. Language adapters

- **D39.** An adapter is a package exporting a declaration that matches the adapter interface. **Every capability is optional**, and kosm reports clearly when an app needs a capability that an adapter lacks.

```zig
// kosm_lua/src/root.zig
pub const adapter = kosm.Adapter{
    .name = "lua",
    .extensions = &.{".lua"},
    .comment = .{ .line = "--" },                        // enables `block`
    .format = formatValue,                               // value -> source text (true, "str", 1.0)
    .serialize = serialize,                              // value tree -> whole file (enables `generate`)
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
- **D42.** Value formatting has two cases: `string`, which the adapter quotes and escapes, and `kosm.raw(text)`, which is inserted verbatim. Colors are formatted by the **app** (`color.format("rgba({})", &.{.hex8})`, D47), because only the app knows the app's color syntax.

## 9. Packages and the config project

```
~/.config/kosm/              # a Zig project, generated by `kosm init`
|-- build.zig                # generic; reads build.zig.zon, exposes every package to kosmoi + apps
|-- build.zig.zon            # `kosm add` writes dependencies here
|-- packages.zon             # refs to follow for `kosm update` (D46)
|-- apps/                    # optional: local apps (D25)
|   |-- hypr_defs.zig        #   a file: private
|   `-- my_bar/              #   a directory: a package (D62)
|       |-- root.zig
|       |-- build.zig        #   one line, written once by kosm new
|       `-- build.zig.zon    #   written and kept up to date by kosm
|-- adapters/                # optional: local adapters, same rule
`-- kosmoi/
    |-- frost.zig            # a file: private
    `-- nord/                # a directory: a package (D62)
        |-- root.zig
        |-- colors.zig
        |-- templates/
        |-- build.zig        # one line, written once by kosm new
        `-- build.zig.zon    # written and kept up to date by kosm
```

- **D43. Seamless install:** `build.zig` imports `build.zig.zon` at comptime, iterates `.dependencies`, and makes every package importable by name from `kosmoi/` and `apps/` (`@import("kosm_hyprland")`). It also discovers every `pub fn` kosmos (D17). No hand-editing of build.zig. **Verify on Zig 0.17 first.**
- **D51. Package names are Zig identifiers, the same everywhere.** A package's manifest name, its module name and its import are all one snake_case identifier: `.name = .kosm_hyprland`, `@import("kosm_hyprland")`, and `kosm add` saves it under that name. (Zig requires the manifest name to be a bare identifier.) The git repo's name is up to the author.
- **D52. One kosm for every package.** Each package pins its own `kosm` by hash, and two copies make Zig see two different `Theme` types. So the config's `build.zig` re-points every package's `kosm` import, and its imports of any other package the config has, to the config's own copy. A package that doesn't fit the user's kosm fails with a normal compile error. No version checks in v1.
- **D44.** Pin a tagged Zig (currently 0.17.0) via `minimum_zig_version`. Never track master.
- **D45.** `kosm apply <kosmos>` = `zig build -Dkosmos=<kosmos>` in the config dir (cached), then run `zig-out/bin/kosmos`. That build compiles only the one kosmos and what it imports, so a broken kosmos never blocks applying another. Error output should point at the user's kosmos file, not at generated code.

## 10. CLI (v1)

```
kosm init                            # create ~/.config/kosm
kosm new kosmos|app|adapter <name>   # scaffold a directory package (D63)
kosm apply <file>[.<variant>] [--<param> value]... [--set path=value]... [--diff]
kosm list                            # kosmoi + variants, installed packages
kosm current                         # what's applied (kosm records the last apply)

kosm add <url>[#ref]                 # zig fetch --save in the config dir + validate it's a kosm package
kosm remove <name>
kosm update [name]                   # re-fetch packages at their tracked ref, rebuild
```

- **D66. `--config <dir>` picks the config project**, for every command, defaulting to `~/.config/kosm`. Tests and experiments always pass it.
- **D67. Built-in packages live in this repo under `packages/`** (`packages/kosm_kitty/`, `packages/kosm_zen/`, ...), as directory packages exactly like third-party ones (D2, D62). While kosm is developed, configs use them by `.path`; they move to their own repos later.
- **D63. `kosm new` scaffolds the full directory.** `kosm new kosmos frost` creates `kosmoi/frost/` with `root.zig` (a commented starting kosmos), `build.zig` and `build.zig.zon`; `kosm new app` and `kosm new adapter` do the same in `apps/` and `adapters/`. Nobody writes build files by hand. A single-file kosmos, app or adapter (D62) is still valid for personal use; you just create the file yourself.
- **D46. Package commands wrap `zig fetch`.** No custom package format or registry. `add` checks that the package provides at least one app or adapter, and reports what it provides. `build.zig.zon` stores only the resolved URL + hash, which loses "follow branch `main`", so kosm keeps that intent in `packages.zon` (name -> url + ref), and `update` re-runs `zig fetch --save=<name>` from it.

## 11. Build order

Each step is usable on its own.

1. **Core data:** Color (OKLCH, formatting), Modifier, Variations, Palette + wheel resolution, Theme. Pure, with tests and no files.
2. **Packaging spike:** prove D43 (package imports + kosmos discovery + D19 params) on Zig 0.17. If it fails, redesign section 9 before going further.
3. **Writers:** `generate` + `template`, plus 3 built-in apps (kitty, one CSS app, nvim). Rice the real Frost end to end. Implement D36-D38 here.
4. **`block` writer.**
5. **`edit` writer:** tree-sitter runtime in core, then `kosm_json`, then `kosm_lua`, then `kosm_hyprlang`.
6. `kosm add/remove/update`, app reloads (D59), `current`, `--set`.

## 12. Non-goals (v1)

- Inserting missing keys (D28), or include/source lines (D57).
- Backup files (D58).
- Checking package versions against the user's kosm (D52).
- `**`, predicates or regex in paths.
- Global semantic colors (bg, fg, roles): these belong to apps (D11).
- `.with` / `.override` patch APIs (D4, G8).
- Wallpaper -> palette generation (could be a package later).
- Any custom configuration language.
- LSP integration.
