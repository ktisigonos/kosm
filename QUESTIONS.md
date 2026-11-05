# Kosm - Open Questions

Answer inline under each question (`**A:** ...`). Once one is answered, the
answer becomes a `D#` in [DESIGN.md](DESIGN.md) and the question is deleted.
An agent must not start on a section whose questions are still open.

Steps 1 and 2 are done. Answered in v0.5: Q6 (D56, D59), Q7 (D57), Q8 (D58),
Q10 (D50), Q11 (D51), Q12 (D52), Q13 (D53, D54), Q14 (D55), Q4 (D60).
Step 3 has no open questions.

---

## Blocking step 6 (CLI completion)

### Q15. Sharing kosmoi as packages
Your kosmoi and apps are plain files, never sub-projects. The config project has
exactly one `build.zig` and one `build.zig.zon`, both written by `kosm init` and never
hand-edited, and those two files already make the whole config a Zig package. So
sharing is "share the config":

- **Config is its own repo:** others run `kosm add git+https://github.com/you/kosm-config#main --name you`.
  Zig fetches it and its dependencies (the app packages your kosmoi use) as usual.
- **Config lives inside a dotfiles repo** (yours: `~` is the repo, the config is at
  `.config/kosm`, one branch per host): `kosm add git+https://github.com/you/dotfiles#nous --path .config/kosm --name you`.
  Zig can fetch a repo with no `build.zig.zon` at its root; a dependency without a
  `build.zig` is allowed (verified in the 0.17 std: `run_build` is optional). Zig won't
  see the nested `build.zig.zon`, so `kosm add` reads it and adds the app packages it
  lists to your config (one copy each, as D52 needs anyway). `packages.zon` records
  the `--path` for `kosm update`.
- **Just one kosmos:** copy the file into your `kosmoi/`. No package involved.

What you get after `kosm add`: `@import("you").frost.iced()` to wrap and tweak it
in your own kosmos (D4), or `kosm apply you.frost.iced` directly. Their local apps
come along too.

This needs one change to D50: kosmoi and local-app names only have to be unique
*within* one package. A package's own `@import("base")` resolves inside that
package, and other packages are reached through the package name, so your `base`
and theirs never collide.

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
