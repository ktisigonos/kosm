# Kosm - Open Questions

Answer inline under each question (`**A:** ...`). Once one is answered, the
answer becomes a `D#` in [DESIGN.md](DESIGN.md) and the question is deleted.
An agent must not start on a section whose questions are still open.

Steps 1 and 2 are done. Answered in v0.5: Q6 (D56, D59), Q7 (D57), Q8 (D58),
Q10 (D50), Q11 (D51), Q12 (D52), Q13 (D53, D54), Q14 (D55).

---

## Blocking step 3 (writers)

### Q4. Template placeholder syntax
Ricer's `ricer.col.red` was clean; its only flaw was not knowing where a name ended.
Proposal: keep the prefix and make the end unambiguous, with two forms.

- **Bare:** `kosm.palette.red`. The prefix `kosm.` is what marks a placeholder, so
  nothing else in the file is ever touched. The name ends at the first character
  that can't continue a path. Since a template is rendered against the app's own
  typed fields, a name glued to text (`kosm.roundingpx`) is not a silent mistake:
  it's an error, "unknown field `roundingpx`, did you mean `{kosm.rounding}px`?" (G6).
- **Braced:** `{kosm.palette.red}` for when text follows directly: `{kosm.rounding}px`.
  The end is the `}`. Only a `{` directly followed by `kosm.` counts, so JSON, CSS,
  Lua and mustache braces are left alone.
- Color formats are trailing components, as in Ricer: `kosm.palette.red.hex8`,
  `{kosm.colors.links.red_255}` (the D47 component names).
- Per template, an app may change the prefix word (`.prefix = "theme"`) or the
  brace pair (`.open = "<", .close = ">"`) for the rare file where `kosm.` or `{kosm.`
  genuinely occurs.
- Templates shipped inside a package are checked at compile time against the
  app's fields, so a typo in a template is a compile error.
- Scanning is cheap: one substring search for `kosm.` per file.

Loops/conditionals stay out of v1. Is this the shape you want?

**A:**

## Blocking step 6 (CLI completion)

### Q15. Sharing kosmoi as packages
Kosmoi you write live as files in your config. To share them, they need to be a package.
Proposal: **a package has the same layout as the config project** (`apps/`, `kosmoi/`,
optionally adapters), built by the same kosm build helper. Then:
- your whole Ktisis kosm config is publishable as a package as it is;
- someone else's kosmoi are imported like any package, `@import("kosm_nord").frost.iced()`,
  so you can wrap one in your own kosmos and tweak it (D4);
- they can also be applied directly: `kosm apply kosm_nord.frost.iced`;
- no sub-projects inside your own config are needed. If you want to develop one
  kosmos as its own package before publishing it, Zig's path dependencies
  (`.path = "kosmoi/nord"`) already allow that.

Is that right?

**A:**

### Q16. How apps reload their program (D59)
`apply` runs before anything is written, so an app can't reload its program itself.
Something has to run after the commit. Options:
- (a) An app has a field like `reload: ?[]const []const u8 = &.{ "pkill", "-USR1", "kitty" }`, which kosm runs after the commit, and which you can override or set to `null`.
- (b) An app may define `pub fn reload(self) !void`, which kosm calls after the commit. That's more flexible, but it's code running with real side effects.
- Only apps whose files actually changed reload?

**A:**

## Can wait until step 5 (edit writer)

### Q9. Array elements in paths
D31's indices pick among *matches*. Separately: should a path be able to step *into* a list, e.g. `monitors[0].scale`? Or is that always the escape hatch (D34)?

**A:**
