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
