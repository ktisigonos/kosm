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
