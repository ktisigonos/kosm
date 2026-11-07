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
- **D48. Colors are OKLCH in f64, and out-of-gamut values are kept.** Nothing is clamped while colors are built, mixed or modified, since some apps (game engines, HDR) want values beyond sRGB. Clipping happens only when printing bytes (`red_255`, `hex`, ...); float components (`red_01`, `lightness`, ...) print the real value. A color that printing clips is a warning naming the app and file (D88).
- **D49. `kosm.hex(text)` is comptime**, so a bad literal is a compile error. It takes `rgb`, `rgba`, `rrggbb` or `rrggbbaa` with an optional `#`. `Color.parseHex` is the runtime version and returns an error; params and `--set` use it.
- **D68. Modifiers work in every color space ricers use, not only OKLCH.** The OKLCH deltas (D15) stay, as the first part and the recommended one. Colors are still stored as OKLCH (D48), the single source of truth; a modifier can also adjust a color through HSV (= HSB), HSL, CMYK, RGB and others ricers need, converting there and back. So a port of Ricer's `v+10` is exact instead of an OKLCH approximation. Each space is its own optional part of `Modifier`, so completion lists its channels: `hovered.hsv = .{ .value = 0.1 }`, `.hsl = .{ .lightness = -0.05 }`, `.cmyk = .{ .key = 0.1 }`. The parts apply in a fixed order after the OKLCH deltas. Deltas are absolute for now and never clamped (D48): an HSV value past 1 is kept for apps that take HDR values, and clips only when printed as bytes. Where a space leaves a channel undefined, it is 0: a gray's hue (so saturating a gray gives red, as in colorsys), and saturation at an HSV value or HSL room of exactly 0. Each part is a struct, so a relative form (`* 1.1`) can be added later as a new field without breaking anything. v1 spaces: HSV (= HSB), HSL, RGB and CMYK; more are added the same way.

## 5. Kosmoi

- **D17. A kosmos is a public function returning a struct of apps.**
  - A kosmos is a `pub fn` in a kosmos file (D62: `kosmoi/frost.zig`, or `kosmoi/nord/root.zig`) that takes either nothing or one `Params` struct whose fields all have defaults, and returns (optionally through `!`) a struct containing at least one app (D53). Helpers like `frostTheme(palette)` or `build(theme)` therefore aren't kosmoi.
  - Each one is applied by name: `kosmos()` is the file's default, and any other name is a variant.
  - `kosm apply frost` -> `frost.kosmos()`; `kosm apply frost.iced` -> `frost.iced()`.
  - One file or many is your choice: nothing forces a base/frost split.
- **D18. The returned tree is the selection.** Kosm walks the returned struct recursively. **D53:** a field is an app when its type is a struct with exactly `pub fn apply(self, *kosm.Output) !void` (so `Modifier.apply(Color) Color` doesn't count), and any other struct is recursed into. An optional app (`?hyprland.App`) set to `null` is skipped. Only apps that appear in the tree are applied. A website-only kosmos returns `struct { website: website.App }`.
- **D19. Parameters become CLI flags.** A kosmos function may take one `Params` struct. Kosm parses `kosm apply frost --accent '#ff0000' --blur false` into it by reflection. Field types decide parsing (colors: D55). Fields should be optional with defaults. A bool flag always takes a value (`--blur false`), and no field may be named `diff`, `config` or `set`, which are kosm's own flags.
- **D55. Colors in flags.** A `kosm.Color` field accepts every common text form: `#rgb`, `#rrggbb`, `#rrggbbaa` (with or without `#`), `rgb(...)`, `rgba(...)`, `hsl(...)`, `hsla(...)` and `oklch(...)`. A `kosm.ColorChoice` field additionally accepts a hue name (`--accent sky`). Kosm can't know the kosmos' palette while parsing, so the kosmos resolves it with `params.accent.resolve(theme.palette)`. Flags are spelled `--border-size`; the field spelling `--border_size` is accepted too.
- **D56. Hosts are opt-in.** If `Params` has a field `host` of an enum type the user declares (`pub const Host = enum { nous, egregoros, ergasterion, synekdemos };`), kosm fills it from the machine's hostname. An unknown hostname is an error naming the hostname and the enum. Without such a field nothing happens, so kosmoi that don't care never see hosts. Combined with optional apps (D53), `if (params.host == .ergasterion) result.hyprland = null;` skips an app on one machine.
- **D20. `--set` pokes the final tree.** `--set hyprland.blur.size=20` runs after the kosmos function returns and walks the tree by reflection. It's for one-off tweaks: it assigns a result, so nothing derived from it changes (D3). Values parse like `Params` flags (D19, D55). On an optional field the value `null` sets it to null; a path that goes through a struct or app that is `null` is an error.
- **D50. Kosmoi, apps and adapters import each other by name**, like packages: `@import("base")`, `@import("hypr_defs")`, never `@import("base.zig")`. Each one is its own Zig module, and Zig doesn't allow a file in two modules. Names must be unique among your local kosmoi, apps, adapters and installed packages; kosm errors on a collision, naming both. Files *inside* a directory kosmos, app or adapter (D62) are private to it and import each other relatively (`@import("colors.zig")`).
- **D62. A file is private, a directory is a package.** The same rule holds for `kosmoi/`, `apps/` and `adapters/`:
  - `kosmoi/frost.zig`: a single-file kosmos. It has no manifest and can't be installed by others (they can still copy the file).
  - `kosmoi/nord/` with `root.zig`, plus any files, templates and subdirectories it needs: a directory kosmos. It carries a `build.zig.zon` and a minimal `build.zig` that only calls kosm's helper (`pub fn build(b: *std.Build) void { @import("kosm").package(b); }`), so it's an ordinary Zig package: ZLS completion, `zig build test` and `zig fetch --save` all work inside it, also when someone develops it on its own outside a config. All the logic lives in kosm's `package` helper, so the generated `build.zig` never changes. Publishing it means pushing that directory as a git repo, and others `kosm add` it and use it as `@import("nord")` or `kosm apply nord.iced`. (A zon-only package would also work, verified on 0.17, but the standard shape costs nothing since kosm generates it.)
  - **Kosm keeps that manifest up to date when it builds a kosmos that reaches it.** `kosm apply nord` regenerates `kosmoi/nord/build.zig.zon` and the manifests of the directory packages nord imports (D76); `kosm apply frost` doesn't touch nord unless frost imports it. Kosm writes `build.zig`, and the manifest's `.name`, `.fingerprint`, `.version` and `.minimum_zig_version`, once and never changes them afterwards. On every build it rewrites `.dependencies` (`kosm` itself plus exactly the installed packages nord imports, copied with their url and hash from the config's own `build.zig.zon`, which stays the source of truth) and `.paths` (every file in the directory). The details are D76.
  - If a directory kosmos imports a *local* kosmos, app or adapter that isn't a directory package (e.g. `@import("base")` where `base` is `kosmoi/base.zig`), regenerating its manifest is an error naming the import, because the published package couldn't resolve it.
- **D76. How a directory kosmos' manifest is kept up to date (D62).**
  - Its imports are every `@import("name")` in its Zig files. An installed package is copied from the config's `build.zig.zon`, with a `.path` made relative to the kosmos' directory. A local *directory* package with a `build.zig.zon` of its own becomes a `.path` dependency (`../../apps/my_bar`), which resolves inside the config; publishing the kosmos means publishing that package too. A local directory without a manifest gets one in the same run, since the apply reaches it too. `kosm` comes first, the rest sorted by name.
  - `.paths` lists every file, sorted, leaving out `zig-out/` and hidden entries (`.git`, `.zig-cache`). A new manifest takes the config's `minimum_zig_version` and a fingerprint made the way Zig makes one.
  - `--diff` writes no manifest either (D37): it prints `would create` or `would update kosmoi/nord/build.zig.zon` instead. A stale manifest is fixed by the next apply that reaches it.
  - An apply refreshes the manifest of the applied kosmos (when it is a directory) and of every local directory package it reaches through imports, transitively: a single-file `kosmoi/frost.zig` importing `apps/my_bar/` refreshes my_bar, and so does whatever my_bar imports. Packages it doesn't reach are never touched. Every manifest is checked before any is written, so one failing writes none.
- **D87. A local package provides everything it declares, wherever it lives.** Like an installed package (D2), a local kosmos, app or adapter, file or directory, may declare any mix of kosmoi, apps and adapters; the folder it sits in (`kosmoi/`, `apps/`, `adapters/`) only sorts the config.
  - Apps already work anywhere: any app in the returned tree is applied (D18).
  - Adapters are collected from installed packages, from `adapters/`, and from every local kosmos, app or adapter the applied kosmos reaches through imports, the kosmos itself included. The reach is the same import walk as D76's. So an adapter shipped inside `kosmoi/nord/` works whenever nord or anything importing it is applied, and a broken package the applied kosmos doesn't reach never blocks it (D45).
  - Kosmoi in `apps/` and `adapters/` can be applied (`kosm apply my_bar`, `kosm apply my_bar.dark`) and are listed by `kosm list` (D85). Names are unique (D50), so the lookup is never ambiguous.
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
  - every field and its default is listed in the app's README;
  - an app covers every setting of its program, not only colors. `from` fills what derives from the theme; every other setting is `?T = null`, and `null` is not written, so the program's own default applies and the file stays minimal;
  - fields keep the program's own names, adjusted only to Zig's casing (`kitty_mod` stays `kitty_mod`, the value `thin-sparse` becomes the enum tag `thin_sparse`). G9's full-words rule never renames a program's setting;
  - fields are typed: a width in points is a float and the app writes the `pt`, a choice is an enum, a color is a `kosm.Color`. Plain strings are only for free text (commands, paths, templates);
  - settings are grouped into nested structs following the program's own documentation sections.

- **D91. An app may let the user choose who owns its values.** A program whose config can read a generated file (Hyprland's Lua `require`) may offer both writers through one field, `target`: `.generate` writes every set option to a file kosm owns, so kosm is the source of truth and any option can be derived; `.edit` replaces values where the user's files already hold them (D25, D30), so the user's files stay the source of truth and keys they lack must be left null (D28). The app's default target is one named constant (`default_target`), so changing which one is the default is a one-line edit. `kosm_hyprland` defaults to `.generate`, writing `~/.config/hypr/kosm.lua` (`return { general = { ... } }`), which `hyprland.lua` reads with `hl.config(require("kosm"))` (D57).

## 7. Writers

Four writers. An app chooses whichever fits each target.

| Writer | Use when | Needs from adapter |
|---|---|---|
| `generate` | the app can include/import a data file (Lua `require`, CSS `@import` + `var()`, kitty `include`) | `serialize` |
| `template` | the output is mostly structure rather than values (nvim colorscheme, fastfetch) | nothing |
| `block` | a line format, no includes, comments allowed: kosm owns `# kosm:begin <id>` ... `# kosm:end` | `comment` syntax (+ `serialize` for the data form, D71) |
| `edit` (path) | set exact keys in a file you also edit by hand | `parse` + `match` + `format` |

- **D60. Template placeholders are fixed: `kosm.<path>` or `{kosm.<path>}`.** Neither the prefix nor the braces are configurable.
  - **Bare:** `kosm.palette.red`. The prefix is what marks a placeholder, so no other text is ever touched. It ends at the first character that can't continue a path (letters, digits and `_`, plus `.` only when a letter follows, so a sentence-ending `.` is left alone).
  - **Braced:** `{kosm.palette.red}` or `{ kosm.palette.red }`, for text glued on: `{kosm.rounding}px`. It ends at the `}`. Only a `{` followed by optional spaces and `kosm.` counts; every other brace (JSON, CSS, Lua, mustache) is plain text.
  - Paths resolve against the app's own fields. Color components are trailing segments with the D47 names (`kosm.palette.red.hex8`, `{kosm.colors.links.red_255}`); a color without one prints in the file's color format (D61).
  - An unknown path is an error naming the template, line and nearest field (`kosm.roundingpx`: did you mean `{kosm.rounding}px`?), never a silent pass-through (G6). Templates shipped inside a package are checked at compile time.
  - No loops or conditionals in v1.
- **D61. Every written file has a color format, set in layers.** A color printed without an explicit component (a template's `kosm.palette.red`, a `generate`d value, an `edit` value) uses the first of:
  1. the file's own setting, an ordinary app field (`format.color`, D70), which users override by assignment like any other field (D3);
  2. the app's default for that file, set in `from`;
  3. the adapter's default for its language (`default_format`, e.g. CSS -> `hex8`);
  4. `hex`.

  `kosm.ColorFormat` is a runtime value with the same template-and-components shape as D47, so it can be stored in a field. Predefined ones (`.hex`, `.hex8`, ...) are constants. An explicit component in a placeholder (`kosm.palette.red.red_255`) always wins.
- **D69. Formatting is the app's choice and the user's override, for every kind of value.** Like the color format (D61), how other values are spelled (hex letter case, `true`/`yes`/`1` for bools, number precision, ...) is set per file by the app and overridable by assignment, per app or per file. How it is set is D70.
- **D70. One `kosm.Format` per file holds every formatting choice.** Its fields are `.color` (the `ColorFormat` of D61, which gains components such as `.hex_upper`), `.boolean` (`true`/`yes`/`1`/`on`), `.float_precision`, and whatever else D69 needs later. An app exposes one field per file (`format`), so a user writes `kitty.format.color = .hex_upper` or `kitty.format.boolean = .yes_no`. Every field layers like D61: the user's assignment, then the app's default, then the adapter's, then kosm's. It replaces the per-file `color_format` field of D61 and the `.color_format` option of D64 and D65. The adapter's layer is its `default_format` field, since `format` is the D39 capability. `float_precision` means at most that many decimals with trailing zeros trimmed (2 prints `0.5` and `13`), 0..12, kosm's default 6; it covers float color components (`alpha_01`) in files too, while `color.format(...)` called in app code keeps 6.
- **D64. `generate` takes a plain struct.** `try output.generate(.{ .file = "~/.config/kitty/kosm.conf" }, .{ .foreground = self.foreground, .color0 = ... })`: the second argument is any plain struct (strings, numbers, bools, colors, nested structs), which kosm turns into a `kosm.Value` tree by reflection and hands to the adapter's `serialize`. It's an `anytype`, but a value, not a patch API (G8). An app whose fields don't map one to one onto the file (renamed enum tags, unit suffixes) may build the `kosm.Value` tree itself and pass that; a `kosm.Value` is taken as it is.
- **D89. A `joined` value is parts written back to back.** `kosm.Value.joined` is a list of values written one after another with no separator, each the way the adapter writes that kind of value. An app that builds its own tree (D64) uses it for a value that mixes text with numbers, booleans or colors (kitty's `2pt`, `cubic-bezier(0.4, 0, 0.2, 1)`, `#041c26@0.5`), so those still follow the file's `kosm.Format` (D70) and a clipped color warns (D88). Every adapter that writes values handles it.
- **D65. `template` takes the app and comptime text.** `try output.template(self, .{ .file = "~/.config/nvim/lua/theme.lua", .text = @embedFile("templates/theme.lua"), .format = self.format })`. Placeholders resolve against `self`'s fields, and since `.text` is comptime, they're checked at compile time (D60). `.format` is the file's `kosm.Format` (D70). Templates live in the app's own package directory (`templates/`), so `@embedFile` stays inside the module root.
- **D71. A block's content is data or text, mirroring `generate` and `template`.** A block is a region kosm owns inside a file the user otherwise writes by hand.
  - **Data block** (the default): `try output.block(.{ .file = "~/.config/kitty/kitty.conf", .id = "colors", .lang = "kitty" }, .{ .foreground = ... })`. The second argument is what `generate` takes (D64); the adapter serializes it, so this form needs `comment` and `serialize`. `.format` layers as in D70.
  - **Text block**: `try output.templateBlock(self, .{ .file, .id, .text = @embedFile(...), .format })`, the call shape of `template` (D65) with comptime text resolved against the app (D60). It needs only `comment`, so it works for languages with no serializer. It is built when the first real app needs it.
- **D72. Block markers.** A block is the lines between `<comment> kosm:begin <id>` and `<comment> kosm:end`, each on its own line, written with the adapter's comment syntax: `# kosm:begin colors` for a line comment, `/* kosm:begin colors */` for a block comment. An id is letters, digits, `_`, `-` and `.`.
  - Only the bytes between the two marker lines are replaced; the markers themselves, and everything outside them, are kept byte for byte (D35). Whitespace around a marker is ignored when reading.
  - A block that is missing is appended at the end of the file (after a newline if the file lacks a final one); a missing file is created holding only the block.
  - Errors naming the line (G6): a `kosm:begin` without its `kosm:end` or the reverse, a `kosm:begin` inside a block, a comment starting with `kosm:` that is not exactly a marker, the same id twice in one file, and content that itself contains a marker line.
- **D73. The plan holds edits, not files.** Each planned file keeps its current contents and a list of edits (a byte range, its new bytes, the app that asked). `generate` and `template` edit the whole file, a block edits its range. D38 rejects two edits whose ranges overlap, an edit next to a whole-file one, and two edits of the same block id; distinct blocks appended at the end of one file are written in the order they were planned.
- **D57. Kosm never wires files together.** It writes what an app tells it to write and nothing else. Making the program read a generated file (kitty's `include`, a Lua `require`, a CSS `@import`) is the user's job, done once in their own config. Kosm never inserts include or source lines. The one exception is a seeded file (D92), since it only ever creates a file the user didn't have.
- **D92. Starting files (`seed`).** `try output.seed(.{ .file = "~/.config/hypr/hyprland.lua", .text = @embedFile("templates/hyprland.lua") })` writes the file only when it doesn't exist, and never reads, edits or overwrites it once it does; from then on the file is the user's. An app uses it to give a fresh machine a working config that already reads the generated file (`hl.config(require("kosm"))`). Like every writer it is planned and committed with the rest (D36), and `--diff` shows it as a new file.
- **D58. No backups.** Kosm never writes `.backup` copies. Git, the all-or-nothing commit (D36) and `--diff` (D37) cover it.

### 7.1 Path editing semantics

- **D28. Missing means error.** Zero matches is always an error, whatever the cardinality. (G6.)
- **D29. Literal or not, we overwrite.** If the current value is an expression (`defs.blur.enabled`), it still gets replaced. Being careful is the user's job. The usual way to avoid it is to target the file where the literal lives (D25).
- **D30. Paths follow the language, not just tables.** Adapters map *every* way a language nests keys onto the same path, so `M.blur = { enabled = true }`, `M.blur.enabled = true` and `hl.config({ M = { blur = { enabled = true } } })` all match `M.blur.enabled`. Code inside function bodies (keybind callbacks, `function ... end`) runs later, not when the file loads, so paths never see it.
- **D82. Values inside function bodies are out of reach in v1.** Neither paths nor the escape hatch (D34, D80) enter a function body, whether it runs later (a keybind callback) or at once (`(function() ... end)()`). A value meant to be riced lives outside any function, e.g. as a plain field of a defs table (D25) that the function reads. An opt-in way in can be added later without breaking anything.
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

  A real example of why `set` defaults to exactly-one: a key such as `decoration.blur.enabled` can be set by `hl.config` calls in two files; a blind `setAll` would change both. `set` errors and tells you to narrow the file scope.
- **D32. Path syntax:** dot-separated segments. A segment containing a dot is quoted: `general."col.active_border"`. `*` matches exactly one level. **No `**`, predicates or regex in v1.** Tuple form `.{ "general", "col.active_border" }` is also accepted.
- **D33. Scope narrowing** goes through the file selector (`files`, `exclude`), not the path language.
- **D79. The file selector.** `output.edit(.{ .files = "~/.config/hypr/**/*.lua", .exclude = &.{"~/.config/hypr/old/**"} })` returns a `kosm.Output.Selection`, which the D31 calls run on.
  - `files` is one glob and `exclude` a list of globs; both start with `~/` or `/`. One glob per selection keeps D31's counts across the whole selection.
  - `*` matches any part of a name inside one directory; `**`, as a whole segment, matches zero or more directories. Nothing else is special in v1 (`?`, `[...]` and `{a,b}` can be added later).
  - Hidden entries are skipped unless the pattern segment itself starts with a dot, so `**` never walks into `.git`.
  - Symlinks are followed. A file reached twice (a link and its target) counts once, by its real path, and a directory already visited is not entered again.
  - Files are sorted by path, the match order of D31. A selector matching no file, or a literal path that does not exist, is an error naming the glob (G6, D28).
- **D34. Escape hatch:** `file.nodes(path)` returns the raw matches (file, byte range, adapter node).
- **D80. The escape hatch can write, and knows no tree-sitter types.** `selection.nodes(path)` returns `[]const Match`, each with its file, byte range and source text (to read, never to parse). `selection.elements(match)` returns a list's elements as matches in file order; the adapter declares which nodes are lists. `selection.replace(match, value)` writes a value formatted like `set` does, checked like any edit (D38). Since D77 leaves lists to the escape hatch, this is how an app reaches `monitors` or keybind lists. The empty path, in `nodes` only, is each file's top-level value, so a file that is one list (waybar's list of bars) is reachable too.
- **D90. One node type can be both a table and a list.** Lua writes `{ "a", "b" }` and `{ a = 1 }` with the same table constructor, so an adapter lists that node type in both `Spec.nest` and `Spec.list`. Its entries with a key are reached by path as in any table; its entries without one are the list's elements, which `selection.elements` returns in file order (D80). A table holding only keyless entries is a list; one holding both, `{ "a", key = 1 }`, is a table whose keyless entries are still its elements. Nothing is lost either way.
- **D77. Paths never step into lists.** A segment always names a key; there is no list indexing (`monitors[0].scale`) in v1. List elements are reached through the escape hatch (D34). D31's indices pick among matches, never list elements.
- **D35. Byte-preserving:** only the value's byte range is replaced. If a value is unchanged, the file isn't rewritten.

### 7.2 Transactional apply

- **D36.** `kosm apply` happens in two phases. **Plan:** call the kosmos function, apply `--set`, call every app's `apply`, and compute every edit in memory. Any error aborts, and nothing is touched. **Commit:** write temp files, then rename them all. Reloading apps afterwards is D59 and D74.
- **D37.** `kosm apply frost --diff` prints the plan as a unified diff and writes nothing.
- **D38.** Two apps editing the same byte range in the same apply is a plan-time error.
- **D59. Reloading is the app's job, not core's.** Each app knows how its program reloads. The mechanism is D74; core only provides the hook an app needs to run after the commit, since `apply` runs before anything is written.
- **D74. An app reloads its program through an optional `reload` function.** An app may declare `pub fn reload(self: App, reloader: *kosm.Reloader) !void` next to `apply`. Like `Output` for `apply`, `kosm.Reloader` keeps io out of the app (G7): `try reloader.run(&.{ "pkill", "-USR1", "-x", "kitty" })` runs a command and waits for it, and a command that can't start or exits non-zero fails the reload. Kosm calls `reload` after the commit, for every app in the applied tree that has one, whether or not its files changed; `--diff` and a failed plan never reload. An app without `reload` is never reloaded. A reload is not critical: a failing one is printed as a warning naming the app (the program may simply not be running), the rest still reload, and the exit status is unaffected.
- **D88. Warnings report without failing.** A warning names the kosmos, app and file like an error (G6) and is printed to stderr as `warning: kosmos 'frost', app 'terminal.kitty', file ~/.config/kitty/kosm.conf: message`. It never changes what is written or the exit status. Warnings print once planning ends, before the diff or the `wrote` lines, on `--diff` and on a real apply alike; when planning fails, the warnings gathered before the failure print first, then the error.
  - **Apps** warn with `try output.warn(file, "message {s}", .{...})`; `file` may be `""`.
  - **Core** warns when printing a color clips it to sRGB (D48): a byte component (`*_255`, `hex*`) whose channel rounds outside 0..255, which is exactly when clipping changes a printed byte, so round-trip noise never warns. Float components never clip, so they never warn. Each distinct clipped color warns once per file, with a count when it repeats, and names where it went when kosm knows (`path 'general.active_border'`, `template line 3`): `color oklch(0.9 0.4 140) is outside sRGB and is clipped to #00ff00 (D48)`. Text an app formats itself (`color.format(...)`) remembers a clipped color, so it warns too when written.

## 8. Language adapters

- **D39.** An adapter is a package exporting a declaration that matches the adapter interface. **Every capability is optional**, and kosm reports clearly when an app needs a capability that an adapter lacks.

```zig
// kosm_lua/root.zig
pub const adapter: kosm.Adapter = .{
    .name = "lua",
    .extensions = &.{".lua"},
    .comment = .{ .line = "--" },                        // enables `block`
    .format = format,                                    // value -> source text (true, "str", 1.0)
    .parser = kosm.treesitter.parser(tree_sitter_lua, .{ // enables `edit`
        .pair = "field",
        .key = "name",
        .value = "value",
        .nest = &.{"table_constructor"},
        .quoted_key = &.{"string"},                      // ["col.active"] = ...
        // hl.config({...}) and `local M = {...}` are path-invisible; function bodies are not entered
        .transparent = &.{ "function_call", "arguments", "variable_declaration" },
        .assign = .{                                     // M.blur.enabled = true
            .node = "assignment_statement",
            .targets = "variable_list", .target = "name",
            .values = "expression_list", .value = "value",
            .name = "identifier",
            .index = .{ .node = "dot_index_expression", .table = "table", .key = "field" },
        },
    }),
};
```

- **D40.** Most tree-sitter adapters should be **declarative** (node names, as above). Hand-written `match` functions are allowed for strange grammars. Adapters may skip tree-sitter entirely (e.g. a 40-line INI parser).
- **D41.** **Kosm core owns the tree-sitter runtime.** Adapters depend on core and ship only their grammar's C sources, which avoids duplicate symbols.
- **D42.** Value formatting has two cases: `string`, which the adapter quotes and escapes, and `kosm.raw(text)`, which is inserted verbatim. Colors are formatted by the **app** (`color.format("rgba({})", &.{.hex8})`, D47), because only the app knows the app's color syntax.
- **D81. JSON and JSONC are two adapters of `kosm_json`.** `json` is strict JSON through tree-sitter and claims `.json`; `jsonc` is a hand-written parser (D40) that also takes `//` and `/* */` comments and trailing commas, and claims `.jsonc`. A `.json` file that is really JSONC (VS Code's `settings.json`) is edited with `.lang = "jsonc"`. Both write values the same way.
- **D78. A grammar is a dependency, compiled by kosm's package helper.** An adapter package fetches its tree-sitter grammar with `zig fetch --save` like any package; nobody writes C. `package(b)` (D62) compiles `src/parser.c`, and `src/scanner.c` when present, of every dependency that has one into the package's module, so a grammar adapter keeps the one-line `build.zig`. Core compiles the runtime (D41) and wraps it in Zig (`kosm.treesitter`).

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
- **D45.** `kosm apply <kosmos>` = `zig build -Dkosmos=<kosmos>` in the config dir (cached), then run `zig-out/bin/kosmos`. That build compiles only the one kosmos and what it imports, so a broken kosmos never blocks applying another unless that one imports it (D87): breaking frost leaves kyanos working, unless kyanos imports frost. Error output should point at the user's kosmos file, not at generated code.

## 10. CLI (v1)

```
kosm init                            # create ~/.config/kosm, or fill in what is missing (D83)
kosm new kosmos|app|adapter <name>   # scaffold a directory package (D63)
kosm apply <file>[.<variant>] [--<param> value]... [--set path=value]... [--diff]
kosm list [kosmos]                   # kosmoi + variants, installed packages (D85)
kosm current                         # what's applied (kosm records the last apply, D75)

kosm add <url>[#ref]                 # zig fetch --save in the config dir + validate it's a kosm package
kosm remove <name>
kosm update [name]                   # re-fetch packages at their tracked ref, rebuild
```

- **D66. `--config <dir>` picks the config project**, for every command that reads one, defaulting to `~/.config/kosm`. Tests and experiments always pass it. A command that reads no config (`kosm current`) rejects the flag with an error saying so, never ignores it.
- **D67. Built-in packages live in this repo under `packages/`** (`packages/kosm_kitty/`, `packages/kosm_zen/`, ...), as directory packages exactly like third-party ones (D2, D62). While kosm is developed, configs use them by `.path`; they move to their own repos later.
- **D75. `current` lives in the state directory, not the config.** The config is usually part of a dotfiles repo, where a record of every apply would be a git change. After each successful commit (never on `--diff`) kosm writes `$XDG_STATE_HOME/kosm/current.zon`, falling back to `~/.local/state/kosm/current.zon`, holding the kosmos name, its arguments and the config path. An apply with nothing to change is recorded too, since that kosmos is now the current one; a record that can't be saved is a warning and the exit status is unaffected, like a failing reload (D74). `kosm current` prints the record as a runnable command (`kosm apply frost --accent red`), adding `--config <dir>` only when the recorded config isn't the default. Tests point `XDG_STATE_HOME` at a temp directory.
- **D63. `kosm new` scaffolds the full directory.** `kosm new kosmos frost` creates `kosmoi/frost/` with `root.zig` (a commented starting kosmos), `build.zig` and `build.zig.zon`; `kosm new app` and `kosm new adapter` do the same in `apps/` and `adapters/`. Nobody writes build files by hand. A single-file kosmos, app or adapter (D62) is still valid for personal use; you just create the file yourself.
- **D86. What `kosm new` writes.** The name must be a Zig identifier (D51) other than `std`, `builtin` and `root`, and is refused, writing nothing, when it already names a local kosmos, app or adapter (file or directory) or an installed package (D50). `build.zig` and `build.zig.zon` come from the same code that keeps manifests up to date (D76). Each `root.zig` is a small working example with comments:
  - **kosmos:** a palette, a theme helper, a `from(theme)` building the apps and assigning a tweak, `kosmos()` and a `light()` variant. It uses the built-in `kosm_kitty`, so a config without it fails with the compile error naming the import.
  - **app:** an `App` with `file`, `format` and three colors following D27, `from(theme)`, and an `apply` writing a small inline `template`, with a commented-out `reload` (D74).
  - **adapter:** an `adapter` with its name, its `.<name>` extension, a `#` line comment and a `serialize` writing `key = value` lines.
- **D83. `kosm init` creates what is missing and never touches what exists.** It works in a missing, empty or partly set up directory (a Ktisis checkout that already holds `kosmoi/`): each of `build.zig`, `build.zig.zon`, `packages.zon`, `kosmoi/`, `apps/` and `adapters/` is created only when it is absent, and an existing file is never read for repair, edited or overwritten. It prints what it created, or that the project is already complete. While kosm lives in this repo (D67), a new `build.zig.zon` depends on `kosm` and on every built-in package by a `.path` relative to the config; the `kosm` binary records the repo's location when it is built.
- **D84. `kosm init` adds a starting kosmos.** When it creates `kosmoi/`, or finds it holding nothing but hidden entries (a `.gitkeep`), `init` writes `kosmoi/kyanos.zig`, the Kyanos port (kitty, zen, nvim). It is a plain file the user owns and edits; kosm never updates it. It ships in this repo and kosm's own tests compile it against the built-in apps, so it can't go stale. Another kosmos may replace it later.
- **D85. `kosm list [kosmos]`.** With no argument it prints every kosmos, local (from any of `kosmoi/`, `apps/` and `adapters/`, D87) or from a package, with its variants and where it comes from, then every installed package with what it provides. `kosm list frost` prints only frost and its variants, each with the apps its tree holds (`kitty: kosm_kitty.App`); `kosm list frost.iced` only that variant. It is built as one program, so a kosmos whose signatures don't compile fails `list` with that compile error, while applying other kosmoi still works (D45).
- **D46. Package commands wrap `zig fetch`.** No custom package format or registry. `build.zig.zon` stores only the resolved URL + hash, which loses "follow branch `main`", so kosm keeps that intent in `packages.zon` (`.{ .kosm_kitty = .{ .url = "git+https://...", .ref = "main" } }`, `.ref` left out to follow the default branch), and `update` re-runs `zig fetch --save=<name>` from it. A comment at the top of `packages.zon` says why it is not a duplicate of `build.zig.zon`.
  - **`add <url>[#ref]`** fetches the package without saving it to learn its manifest name (D51). A name already in `build.zig.zon` is an error pointing to `update`, since `zig fetch --save` would silently overwrite it. It then saves the package and checks it by building it against the config (`zig build -Dinspect=<name>`): it must compile there and provide at least one app, adapter or kosmos, and `add` reports everything it provides. `packages.zon` is written last.
  - **`remove <name>`** deletes the entry from `build.zig.zon` through `std.zig.Ast` byte ranges, leaving every other byte as it was, and from `packages.zon`. `kosm` itself can't be removed. Local imports of the package aren't checked: the next apply's compile error names the missing import.
  - **`update [name]`** re-fetches every package in `packages.zon`, or only `name`, and checks each like `add`. Dependencies missing from `packages.zon` (`.path` ones, `kosm` itself) are skipped and reported; naming one is an error.
  - Any failure after the fetch puts `build.zig.zon` back to its original bytes, so a failed command changes nothing. An interrupt (Ctrl-C) midway isn't covered.

## 11. Build order

Each step is usable on its own.

1. **Core data:** Color (OKLCH, formatting), Modifier, Variations, Palette + wheel resolution, Theme. Pure, with tests and no files.
2. **Packaging spike:** prove D43 (package imports + kosmos discovery + D19 params) on Zig 0.17. If it fails, redesign section 9 before going further.
3. **Writers:** `generate` + `template`, plus 3 built-in apps (kitty, one CSS app, nvim). Rice the real Frost end to end. Implement D36-D38 here.
4. **`block` writer.**
5. **`edit` writer:** tree-sitter runtime in core, then `kosm_json`, then `kosm_lua`.
6. `kosm add/remove/update`, app reloads (D59), `current`, `--set`.
7. **The rest of the CLI:** `kosm init`, `kosm new`, `kosm list`.
8. **Warnings and fixes:** core can warn without failing (gamut clipping, D48).
9. **Apps for the programs in use:** `kosm_ghostty`, `kosm_hyprland`, Zen's prefs through `kosm_userjs`.
10. **Kyanos for real:** the human's own config project rices their desktop.

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
