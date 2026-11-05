# Kosm - Open Questions

Answer inline under each question (`**A:** ...`). Once one is answered, the
answer becomes a `D#` in [DESIGN.md](DESIGN.md) and the question is deleted.
An agent must not start on a section whose questions are still open.

Steps 1 and 2 are done. Answered in v0.5: Q6 (D56, D59), Q7 (D57), Q8 (D58),
Q10 (D50), Q11 (D51), Q12 (D52), Q13 (D53, D54), Q14 (D55), Q4 (D60).
Step 3 has no open questions.

---

## Blocking step 6 (CLI completion)

### Q15. Sharing: a kosmos is the unit
A rice is what people share (like nvim colorschemes or base16 schemes: one repo per
theme), so **each kosmos is its own package**, named after the rice, not its author.

- **A kosmos is a file or a directory** in `kosmoi/`:
  - `kosmoi/frost.zig`: a private one-file kosmos. Nothing else needed.
  - `kosmoi/nord/` with a `root.zig`: a kosmos that can be shared. Files inside it
    import each other relatively (`@import("colors.zig")`), because the whole
    directory is one Zig module. Templates can live next to it.
- **A shared kosmos needs one extra file, its `build.zig.zon`** (name + the app
  packages it uses), and **no `build.zig`** (a dependency without one is allowed,
  verified in the 0.17 std). Kosm writes and updates it (`kosm share nord`, or
  automatically on build, from the packages `nord` imports), so nobody edits it.
- **Publishing:** push `kosmoi/nord/` as its own git repo.
- **Installing:** `kosm add git+https://github.com/someone/nord#main`, then
  `kosm apply nord`, `kosm apply nord.iced`, or wrap it in your own kosmos with
  `@import("nord").build(...)` and tweak it (D4). The import name is the rice's name.
- **Sharing a base works the same way:** a base is just a kosmos (it picks apps),
  so `@import("someone_base")` is possible too.
- A local kosmos and an installed one with the same name is an error naming both.
- The whole-config route (`--path .config/kosm`) is dropped: it shares someone's
  personal apps and paths along with the rice.

This replaces D50's "unique across everything" with: names are unique among your
local kosmoi, local apps and installed packages; files inside a directory kosmos
are private to it.

Is that right? And which do you prefer for the `build.zig.zon`: written on demand by
`kosm share nord`, or kept up to date automatically on every build?

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
