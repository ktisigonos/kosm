# Kosm — Open Questions

Answer inline under each question (`**A:** …`). Once one is answered, the
answer becomes a `D#` in [DESIGN.md](DESIGN.md) and the question is deleted.
An agent must not start on a section whose questions are still open.

Step 1 (core data) has **no open questions**. It can start.

---

## Blocking before step 3 (writers)

### Q4. Template syntax
Templates are needed for nvim colorschemes, fastfetch, etc.
- (a) Mustache-like: `{{ palette.red }}`, `{{ colors.links | hex }}`, rendered against the module's own fields. Readable in any file type.
- (b) Zig `std.fmt` style. You get no syntax highlighting for the target language, and it gets ugly fast.
- Loops/conditionals? Every feature added here is how Ricer-style engines balloon.
- *Recommendation:* (a), values + filters only, plus at most `{{#each …}}`.

**A:**

### Q5. Color formatting syntax
D42 has modules write `color.format("rgba({hex8})")`. The old spec had an enum-based form: `color.format("rgba({}, {}, {}, {})", .{ .r255, .g255, .b255, .a01 })`.
- String placeholders are shorter and readable.
- The enum form catches typos at compile time.
- *Recommendation:* the enum form (G8: completion and compile errors), plus a few shortcuts (`color.hex()`, `color.hex8()`, `color.rgba01()`).

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

## Can wait until step 5 (edit writer)

### Q9. Array elements in paths
D31's indices pick among *matches*. Separately: should a path be able to step *into* a list, e.g. `monitors[0].scale`? Or is that always the escape hatch (D34)?

**A:**
