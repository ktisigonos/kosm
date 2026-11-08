# Zig rules

Rules for every Zig project, on top of `general.md`. The Zig version is pinned per project via `minimum_zig_version` in `build.zig.zon`; it is always a tagged release, never master.

## Looking things up

Zig is pre-1.0 and its std and build APIs change between releases (hard rule 13). Never rely on memory for a std API.

- **Notes file:** `doc/ZIG_NOTES.md` holds the gotchas for the pinned version. Read it before coding, append a line when you hit one.
- **Language reference:** `doc/generated/zig/`, one file per chapter (run `./fetch-docs.sh` to create it). Chapters under about 300 lines may be read whole.
- **std source:** found via `zig env` (its `.std_dir` field). Do not hard-code the path. `zig env` prints ZON, not JSON. Read the doc comment and signature at the hit, and the file's `test` blocks for usage.
- **Dependencies:** fetched packages live under `zig-pkg/`, one directory each. Their docs are the doc comments in the Zig bindings, then the headers and `docs/` of any wrapped C sources.

```sh
ls doc/generated/zig/                              # chapter list
rg -n "pattern" doc/generated/zig/                 # search all chapters with file and line
wc -l doc/generated/zig/<file>.md                  # check a chapter's size before opening it
sed -n '120,200p' doc/generated/zig/<file>.md      # read lines 120 to 200 only
rg -n "pub fn name" "$(zig env | grep -o '\.std_dir = "[^"]*"' | cut -d'"' -f2)"   # std source
ls zig-pkg/                                        # fetched packages
rg -n "pub fn parse" zig-pkg/<package>/src/        # find the API and its doc comment
rg -n "pattern" zig-pkg/<package>/ -g '*test*'     # usage examples in the package's tests
```

## Dependencies

A dependency change (hard rule 5) names the exact `zig fetch --save=<name> <url>` to run, or the `build.zig.zon` entries to delete. Once approved, wire it up in `build.zig`. Never touch `build.zig.zon` dependencies without that approval. Where `build.zig` can enforce a boundary by limiting a module's imports, it does (hard rule 7).

## Code style

Follow idiomatic Zig and the official Zig style guide.

- **Casing:** types `PascalCase`; functions `camelCase`; variables, fields, parameters `snake_case`; enum values `snake_case`; namespace files `snake_case.zig`.
- **File per struct.** A struct gets its own file named `PascalCase.zig`, written as a file-level struct (`const Color = @This();` with fields at the top). Files that are collections of functions or constants are namespaces in `snake_case.zig`.
- **Errors:** error sets and `try`. `catch unreachable` and `@panic` only for genuine invariants, with a comment.
- **Memory:** pass allocators explicitly. Every struct that allocates has `init`/`deinit`; ownership is documented. No hidden global allocators.
- **Comments:** inline comments are `//`; doc comments are `///` in the style of the Zig standard library. Package roots (`root.zig`) carry a one-line `//!` header.
- **Formatting:** run `zig fmt` on everything you touch.

## Testing

Use Zig's built-in `test` blocks at the bottom of the file they test. Run with `zig build test`. File tests use `std.testing.tmpDir`.

Build and verify with `zig fmt`, `zig build`, `zig build test`, then check the test summary count: a file only re-exported through a lazily analyzed `@import` runs none of its tests (see `doc/ZIG_NOTES.md`).
