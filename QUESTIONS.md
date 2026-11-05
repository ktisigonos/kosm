# Kosm - Open Questions

Answer inline under each question (`**A:** ...`). Once one is answered, the
answer becomes a `D#` in [DESIGN.md](DESIGN.md) and the question is deleted.
An agent must not start on a section whose questions are still open.

Steps 1 and 2 are done. Answered in v0.5: Q6 (D56, D59), Q7 (D57), Q8 (D58),
Q10 (D50), Q11 (D51), Q12 (D52), Q13 (D53, D54), Q14 (D55), Q4 (D60, D61), Q15 (D50, D62).
Step 3 has no open questions.

---

## Blocking step 6 (CLI completion)

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
