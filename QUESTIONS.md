# Kosm - Open Questions

Answer inline under each question (`**A:** ...`). Once one is answered, the
answer becomes a `D#` in [DESIGN.md](DESIGN.md) and the question is deleted.
An agent must not start on a section whose questions are still open.

Steps 1 and 2 are done. Answered in v0.5: Q6 (D56, D59), Q7 (D57), Q8 (D58),
Q10 (D50), Q11 (D51), Q12 (D52), Q13 (D53, D54), Q14 (D55), Q4 (D60, D61), Q15 (D50, D62), Q17 (D68, D70), Q16 (D74), Q9 (D77).

---

## Q18. How does an app reach values inside function bodies?

Paths never see code inside function bodies (D30): a Hyprland keybind callback such as
`hl.bind("SUPER + F1", function () hl.config({...}) end)` in `gamemode.lua` is invisible, since
it runs later, not when the file loads. Should an app be able to reach those values at all, and
if so how? Options: through the escape hatch (D34, D80), through an option on the selection
(`output.edit(.{ ..., .functions = true })`), or not at all in v1. Nothing built so far depends on
the answer.

**A:**
