# Review list

Decisions an agent took while the human was away (2026-11-10 onwards), one line each, newest
step last. Overturn any of them: say which, and it is changed in a follow-up commit. Delete
this file once everything in it is reviewed.

## Where things are

- Every package is a repository of its own beside kosm: `~/Projects/Zig/kosm_<name>`, branch
  `master`, `origin` set to `https://git.nnstdios.com/nnra6864/kosm_<name>`. None is pushed, and
  kosm itself is not pushed either.
- Packages pin kosm and each other by commit and hash. An unpushed commit builds because its
  archive was fetched into Zig's cache first (`doc/ZIG_NOTES.md`), so never amend or rebase a
  commit another manifest pins.
- To publish: create one empty repository per package on the forge, then `git push origin master`
  in kosm and `git push -u origin master` in each package directory. After that
  `zig build test -Dnetwork` in kosm checks a config made by the real `kosm init`.

## 13a. Packages in their own repositories

- The split branches (`git subtree split`) were cloned into the sibling repositories and then
  deleted from kosm's repository; each package got a `.gitignore` for Zig's caches.
- An app's package exports the adapter it writes with as `<name>_adapter` (`lua_adapter`,
  `css_adapter`, `userjs_adapter`).
- `kosm init` writes Kyanos only together with a new manifest, since an existing manifest may
  lack the official packages it imports.
- `zig build test -Dnetwork` is a test that needs the network and the pushed repositories; it is
  skipped otherwise.

## Your config project

- `~/.config/kosm/build.zig.zon` and `packages.zon` now list kosm and the 11 packages, pinned to
  the local commits (your `kosm` is this repository's build, which no longer ships packages, so
  Krystallos did not build). Checked with `kosm apply krystallos --diff` only. The old files are
  not kept; `git diff` in your dotfiles shows the change.
- Zig's own cache (`~/.cache/zig`) was given each pinned package, so the config builds before
  anything is pushed.

## 13b. Keyboard layouts

- The core type is `kosm.Keyboard`: `layouts` (each `.layout` and an optional `.variant`), `model`,
  `options`, `rules`. It builds XKB's comma lists, the one form Hyprland, sway, `setxkbmap`, the
  `XKB_DEFAULT_*` variables and KDE's `kxkbrc` all take. GNOME's `layout+variant` spelling is left
  until an app needs it.
- `kosm_hyprland` gets one field, `keyboard`, filling `input.kb_*` where they are null. No
  variant at all writes no `kb_variant`.
- A name with a comma or a space, or an empty layout or option, fails the apply.
- Found on the way: a package built on its own ended up with two copies of kosm once it pinned a
  newer kosm than its adapter package. The one-copy rule now covers a package's own build too
  (`build/unify.zig`), so bumping one pin never forces bumping every package.

## 13c. Showing a kosmos' colors

- The command is `kosm colors <kosmos>`. It prints every public `kosm.Palette` constant at the
  top of the kosmos' file (root.zig for a directory kosmos), the way adapters are found; a kosmos
  declaring none gets an error saying so. Krystallos keeps its palette in `values.zig`, so its
  root.zig needs `pub const palette = values.palette;` to be shown.
- It shows black, white, gray and the 12 hues, with `mixed` after each one the palette does not
  set. Variations are not shown: they need a theme, which a kosmos builds inside its functions.
- Blocks are background-colored spaces (truecolor), drawn only when kosm's stdout is a terminal.

## 13d. Shell completions

- `kosm completions fish|bash|zsh` prints a script; its header says where to install it. Each
  script only calls a hidden `kosm complete -- <words>`, which prints the candidates, so what
  completes is decided in one place and tested in Zig.
- Kosmos names come from the config's lister, and a kosmos' `--param` flags and `--set` paths
  from its runner, asked through the environment variable `KOSM_COMPLETIONS` (the interface
  number went from 1 to 2). The first Tab on a kosmos builds its runner, so it can take seconds.
- After `--config` the shell completes directories itself; a parameter's value is not completed.
- Checked by hand: `bash -n` and `fish -n` accept their scripts, and `kosm complete` answers for
  Krystallos. zsh is not installed here, so its script has never run. Tests cover commands,
  packages and a config that does not build; kosmos names and params are covered by the
  runner's unit tests, not yet by an end-to-end test through a built config.

## 13e. One background opacity for every app

- It lives on the theme: `theme.background_alpha` (0..1, default 1), assigned after
  `kosm.Theme.from`. The palette's black was not used: in light mode the background is white, and
  a translucent black would also be a translucent foreground.
- `theme.asBackground(color)` scales a color's alpha by it; each app's `from` calls it on the
  color it picks as its background, so a palette black that already carries alpha still works.
- kitty and ghostty needed no new field: their `background_opacity` already follows the
  background's alpha. Zen's `background` (and the `button` raised from it) carries the alpha.
  `kosm_nvim.transparent` is the one new derived switch: null turns into `true` when `base00`
  is not opaque.
- Hyprland gets nothing: its `misc.background_color` is the color behind every window. Zen's
  page background pref (`browser.display.background_color`) also stays opaque.
- Kyanos still sets its alpha by hand; the starting kosmos is replaced in 13o.

## 13f. Curves, easings and Hyprland animations

- Core: `kosm.Curve` is a union of `.bezier` (`x1, y1, x2, y2`, as CSS's `cubic-bezier`) and
  `.spring` (`mass` 1, `stiffness`, `damping`). The easings are declarations on it, so a kosmos
  writes `.ease_out_expo`: CSS's `linear`, `ease`, `ease_in`, `ease_out`, `ease_in_out`, and
  `ease_in_*`, `ease_out_*`, `ease_in_out_*` for sine, quad, cubic, quart, quint, expo, circ and
  back. Elastic and bounce have no bezier, so they are left out.
- `kosm_hyprland` gets two fields named after Hyprland's calls: `curve` (named curves) and
  `animation` (one entry per leaf). `animation` sits next to the existing `animations` section
  (`animations.enabled`); say if you want other names.
- An animation names its curve by string, as Hyprland does; the app writes it under `bezier` or
  `spring` by what the curve is. `default` is Hyprland's own bezier and needs no definition.
- The generated module's shape: the calls first, then `return { ... }` as before, so the block
  `hl.config(require("kosm"))` and reading single values from the module still work. A new
  `hyprland` adapter in the package writes it, using the `lua` adapter for values.
- Leaves are an enum in Zig spelling (32 leaves, `fade_glow` included); `Hyprland
  --verify-config` accepted every one and the generated module. That flag is a way to check
  generated Hyprland config without touching the running session.
- Hyprland reads a spring's `damping` and also the misspelling `dampening` your curves.lua
  uses; kosm writes `damping`.
- With the `.edit` target, set curves or animations fail the apply: kosm never adds calls.
