# Kosm - Open Questions

Answer inline under each question (`**A:** ...`). Once one is answered, the
answer becomes a `D#` in [DESIGN.md](DESIGN.md) and the question is deleted.
An agent must not start on a section whose questions are still open.

Steps 1 and 2 are done. Answered in v0.5: Q6 (D56, D59), Q7 (D57), Q8 (D58),
Q10 (D50), Q11 (D51), Q12 (D52), Q13 (D53, D54), Q14 (D55), Q4 (D60, D61), Q15 (D50, D62).
Step 3 has no open questions.

---

## Blocking step 3d (color spaces and formatting)

### Q17. What D68 and D69 look like in code
Directions are decided (D68, D69); the shapes are not.
- Modifiers (D68): (a) one optional part per space, `hovered.hsv = .{ .value = 0.1 }`, `.hsl = .{ .lightness = -0.05 }`, `.cmyk = ...`, applied in a fixed order after the OKLCH deltas; or (b) one `space` field plus generic deltas, `.{ .space = .hsv, .deltas = .{ 0, 0, 0.1 } }`. (a) completes better (G8); (b) is shorter. Are deltas absolute (`+0.1`) or also relative (`*1.1`)? Which spaces in v1 (HSV, HSL, CMYK, RGB, linear RGB, LAB, ...)?
- Formatting (D69): extend `ColorFormat` with uppercase components (`.hex_upper`) and add a sibling `kosm.ValueFormat` (bool spelling, float precision) that a file's options and the adapter default carry like D61? Or one `kosm.Format` holding colors and everything else?

**A:**

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
