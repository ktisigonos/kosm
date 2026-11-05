# Kosm — Open Questions

Answer inline under each question (`**A:** …`). Once one is answered, the
answer becomes a `D#` in [DESIGN.md](DESIGN.md) and the question is deleted.
An agent must not start on a section whose questions are still open.

Steps 1 and 2 are done. Q10-Q14 came out of the packaging spike (step 2) and block step 3.

---

## Blocking before step 3 (writers)

### Q4. Template syntax
Templates are needed for nvim colorschemes, fastfetch, etc.
- (a) Mustache-like: `{{ palette.red }}`, `{{ colors.links | hex }}`, rendered against the module's own fields. Readable in any file type.
- (b) Zig `std.fmt` style. You get no syntax highlighting for the target language, and it gets ugly fast.
- Loops/conditionals? Every feature added here is how Ricer-style engines balloon.
- *Recommendation:* (a), values + filters only, plus at most `{{#each …}}`.

**A:**

### Q6. Per-host differences
nous, egregoros, ergasterion and synekdemos have different apps and paths. With kosmos-as-function, the options are:
- (a) Kosmos functions get the host via a param (`Params.host` filled automatically from the hostname) and branch on it.
- (b) A separate base per host (`base_nous.zig`), and a kosmos picks one.
- (c) Kosm passes the host to every module's `from`, and modules skip themselves if they aren't installed there.
- Reload hooks: declared by each module (`pkill -USR1 kitty`, `hyprctl reload`), overridable by assignment like any other field?

**A:**

### Q7. Include lines
`generate` writes `~/.config/kitty/kosm.conf`, but kitty.conf needs `include kosm.conf` once.
- (a) `output.ensureLine(file, "include kosm.conf")`. Idempotent, but it's an *insert*, which D28 forbids for keys.
- (b) Never insert. Error with "add `include kosm.conf` to kitty.conf".
- *Recommendation:* (b), plus `kosm apply --fix` that does (a) after asking.

**A:**

### Q8. Backups
Ricer made `.backup` files. Your dotfiles are in git, and D36 makes applies atomic. Are backups still wanted, opt-in, or is `--diff` enough?

**A:**

### Q10. How kosmoi import each other
The spike showed `@import("base.zig")` cannot work when every kosmoi file is its own module (Zig: "file exists in modules 'kosmos:base' and 'kosmos:frost'"), and every file must be a module so kosm can find its kosmoi without copying them (copies would break D45's error locations).
- (a) Import by name: `@import("base")`, like packages. Works in the spike (cyclic imports are fine). Local modules are imported the same way: `@import("hypr_defs")`. Names must not collide; kosm errors if they do.
- (b) `kosm init` writes a fixed root file at the config root; kosm regenerates it whenever `kosmoi/` changes. Keeps relative imports, but writes into the config dir.
- *Recommendation:* (a), and update the section 5 examples.

**A:**

### Q11. Package names
A package's own `.name` in its `build.zig.zon` must be a bare identifier (`kosm_hyprland`; Zig rejects `kosm-hyprland`). The module name and the consumer's dependency key may contain dashes (`zig fetch --save=kosm-hyprland` works).
- (a) Keep `@import("kosm-hyprland")`: the manifest is `.name = .kosm_hyprland`, the module is `kosm-hyprland`, and `kosm add` saves under the module name. 
- (b) Use underscores everywhere: `@import("kosm_hyprland")`.
- *Recommendation:* (a), it keeps G9's readable names; `kosm add` maps `_` to `-`.

**A:**

### Q12. One kosm for every package
Each package pins its own `kosm` by hash; two copies give "expected type 'Theme', found 'Theme'". The spike fixes this by re-pointing every package's `kosm` import (and imports of any other package the config has) to the config's copy, so a package always compiles against the user's kosm. An incompatible package then fails to compile with a normal error.
- Accept this as part of D43? Or should `kosm add` also refuse packages whose pinned kosm differs?
- *Recommendation:* accept, and later have `kosm add` warn when the pinned kosm differs.

**A:**

### Q13. What counts as a kosmos, and as a module
`kosm.Modifier` has `pub fn apply(Color) Color`, so D18's "any field whose type has `pub fn apply`" would treat modifiers as modules. The spike uses:
- module: a struct with `pub fn apply(self, *kosm.Output) !void`;
- kosmos (D17): a `pub fn` taking nothing or one struct whose fields all have defaults (that is what makes it `Params`), returning (possibly via `!`) a struct that contains at least one module. So `frostTheme(palette)` and `build(theme)` are skipped.
- *Recommendation:* write both into D17/D18 as they are.

**A:**

### Q14. Params details (D19)
- Colors by palette name (`--accent sky`): which palette? The kosmos builds its palette itself, so kosm cannot know it before calling. Options: (a) only hex in v1, (b) a `kosm.ColorChoice` type holding hex or a `Palette.Hue` that the kosmos resolves against its own palette with one call.
- Flag spelling: `--border_size` (the field name) or `--border-size`?
- *Recommendation:* (b) and `--border-size`, accepting both spellings.

**A:**

## Can wait until step 5 (edit writer)

### Q9. Array elements in paths
D31's indices pick among *matches*. Separately: should a path be able to step *into* a list, e.g. `monitors[0].scale`? Or is that always the escape hatch (D34)?

**A:**
