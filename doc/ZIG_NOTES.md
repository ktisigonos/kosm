# Zig 0.17 notes

Purpose: stop agents (and humans) from repeating the same mistakes. Zig is pre-1.0 and its std and build APIs change between releases, so training data is often stale. The first entries were carried over from Agon, a sibling project on the same Zig.

## How to use this file

- **Read it before writing code.**
- **Append a line whenever you hit a Zig gotcha** (an API that moved, a compile error that surprised you, a build.zig quirk). Keep entries to 1-3 lines with a tiny example if it helps.
- Do not delete entries unless they are verified wrong.

## Where to look things up

- Toolchain verified: Zig 0.17.0 (`zig version`), 2026-11-05.
- Language reference: `doc/generated/zig/` (run `./fetch-docs.sh`; one file per chapter, search across the directory, open only small chapters whole).
- Zig std source: run `zig env` and use `.std_dir`; see AGENTS.md for the search commands.
- **`zig env` prints ZON, not JSON:** the AGENTS.md one-liner (`"std_dir": *"..."`) matches nothing. Use `zig env | grep -o '\.std_dir = "[^"]*"' | cut -d'"' -f2`. `std.builtin.Type` lives in `std/lang.zig`, not `builtin.zig`.
- Dependencies: `zig-pkg/<package>/` (the hash-named directory changes when a dependency is updated).

When unsure about any std function, grep the std source for its definition before using it.

## Gotchas

<!-- Add entries below. Format: - **topic:** what went wrong, and what is correct for 0.17. -->

### Language and comptime

- **Struct `@typeInfo` has no `.fields` in 0.17:** `@typeInfo(T).@"struct"` holds parallel slices `field_names`, `field_types`, `field_attrs` (plus `decl_names`); `@Struct(layout, backing, names, types, attrs)` builds one back.
- **Enum `@typeInfo` also uses parallel slices:** `@typeInfo(E).@"enum"` has `field_names` and `field_values` (comptime_int); `std.enums.values(E)` gives a `[]const E`.
- **Looping over `@typeInfo(T).@"struct".field_types` needs `inline for`:** a plain `for` indexes the slice at runtime ("values of type 'type' must be comptime-known"). Helpers computing over fields return `comptime_int` and use `comptime var`.
- **comptime tables:** a `const` built in a comptime block and returned as an anonymous struct literal (`break :blk .{ .items = items }`) keeps comptime fields, and taking `&table.items` at runtime fails with "runtime value contains reference to comptime var". Give the result a named struct type: `const final: Table = .{ ... }; break :blk final;`.
- **Array repeat `**` is gone:** `[_]u8{'a'} ** 4` fails with the misleading "binary operator '*' has whitespace on one side, but not the other". Use `const filler: [4]u8 = @splat('a');` (`@splat` takes one argument; the length comes from the result type) or `@memset` on a runtime buffer.
- **`@intFromEnum` is deprecated:** use `@backingInt` (enums, packed structs, packed unions) or `@bitCast`. The old name still compiles on 0.17.0.
- **`std.meta.Int` is gone:** build an integer type with `@Int(.unsigned, bits)`.
- **Optimize modes are lowercase:** `builtin.mode` compares against `.debug`/`.safe`/`.fast`/`.small`.
- **Builtins are not function values:** `@floor` / `@ceil` cannot be passed as a `fn (f32) f32`; pass a small enum and `switch` to the builtin.
- **A field may not share a name with a file-level declaration:** in a file-struct, `const scaling = @import(...)` plus a field `scaling` is "duplicate struct member name". File-level consts used only by tests count too; name test constants apart (`test_hue`).
- **A parameter may not shadow a declaration of its container, methods included:** `fn mix(color: Color, ...)` beside `pub fn color(...)` is "function parameter shadows declaration"; rename one.
- **A field of a typed struct literal does not parse:** `Params{}.blur` is "expected `;` after statement"; bind the literal first (`const params: Params = .{};`).
- **`&.default` does not give the address of the decl:** coercing to `*const T` makes a static copy, so `x == &T.default` is false. Compare the values.
- **Empty exhaustive enums are rejected:** an enum with no fields, only decls, fails with "empty exhaustive enums must be backed by 'noreturn'". Add `_,` to make it non-exhaustive.
- **Untyped file-level number constants break mixed division:** `const h = 2;` then `h / @tan(x)` at comptime is "ambiguous coercion of division operands"; give such constants a type (`const h: f32 = 2;`).
- **`@max` of comptime-known lengths takes the smallest fitting type:** `@max(a.len, b.len) + 2` with lengths 14 and 10 is a `u4`, so the `+ 2` overflows at comptime. Widen first: `@as(usize, @max(a.len, b.len)) + 2`.
- **`@abs` of a signed integer returns the unsigned type:** `@intCast` it back before mixing with signed values.
- **`@floatCast` from f64 to f32 never traps:** out-of-range values become +/-inf, so check `std.math.isFinite` after narrowing. A widened f32 keeps its exact binary value (`6.4` prints as `6.400000095367432`).

### std

- **`std.fs` is a deprecated shim - the filesystem lives in `std.Io`:** use `std.Io.Dir`/`std.Io.File`. Whole-file read: `std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(n))`; stdin: `std.Io.File.stdin().reader(io, &buf)` then `.interface`; buffered stdout: `std.Io.File.stdout().writer(io, &buf)` then `.interface` and `flush()`. All take an `Io`.
- **`std.fs.path` is a deprecated shim:** path helpers (`dirname`, `stem`, `basename`) live in `std.Io.Dir.path`.
- **`std.Io.Dir.cwd()` cannot iterate:** iterating it is *illegal behavior with no error*. Open a real handle with `openDir(io, ".", .{ .iterate = true })` first.
- **`std.Io.Dir` shape notes:** `openDir` rejects an empty sub_path; mkdir -p is `createDirPath(io, path)`; `writeFile(io, .{ .sub_path, .data })` does not create parent directories.
- **Atomic file replace is `Dir.createFileAtomic` + `File.Atomic.replace`:** pass `.replace = true` at creation or `replace` hits an assertion; `.make_path = true` creates missing folders. Always `deinit` it (it deletes the temp file when the write was abandoned). Write through `file.file.writer(io, &buf)`, whose `.err` holds the real error behind `error.WriteFailed`.
- **`std.Io.File.Permissions` differs per OS:** on POSIX it is a mode enum with `fromMode(0o600)`/`toMode`. `createFileAtomic` takes it as `.permissions`, and the replaced file gets the new mode, so copy the original file's mode when replacing a user's config.
- **0.17 `main` can take `std.process.Init`:** `pub fn main(init: std.process.Init) !u8` gives `init.gpa`, `init.io`, `init.arena`, and args via `init.minimal.args.toSlice(arena)`.
- **`std.posix.getenv` is gone:** use `std.c.getenv` (or the environ from `std.process.Init`).
- **`std.Options.debug_io` works in all build modes:** it is std.debug's own single-threaded `Io`. The program's real `Io` comes from `init.io`; tests use `std.testing.io`.
- **Two `Io`s, two stderr locks:** `std.debug.print` locks `debug_io`'s mutex, while `io.lockStderr` locks that `Io`'s own, so a stray `std.debug.print` can interleave with real output.
- **Stderr is Io-mediated:** plain `File.writeAll` is gone; use `std.debug.lockStderr(&buf)`, write via `stderr.file_writer.interface`, then `std.debug.unlockStderr()` (which flushes).
- **No clock functions in `std.time`:** monotonic time is `std.Io.Timestamp.now(io, .awake)`. The `Clock` enum is `real`, `awake`, `boot`, `cpu_process`, `cpu_thread`.
- **`std.Thread.Mutex` is gone:** the blocking lock is `std.Io.Mutex` (`.init`, `lock(io)` which can return `error.Canceled`, `lockUncancelable(io)`, `unlock(io)`).
- **`std.Io.Writer.Error` is only `error{WriteFailed}`:** helpers that both write and allocate need a combined error set.
- **`std.Io.Writer.Allocating`:** `Allocating.init(allocator)`, pass `&allocating.writer`, finish with `toOwnedSlice()` (and `deinit` on error paths).
- **`Reader.takeDelimiterExclusive` leaves stream state unmodified on `error.StreamTooLong`:** retrying immediately loops forever. Drain the line or read bytewise.
- **`{d}` prints `+` on positive signed integers only when a width is set:** `{d:>6}` of `i64` 0 gives `    +0`. Use unsigned types for non-negative values.
- **`Allocator.dupeZ` is gone:** use `allocator.dupeSentinel(u8, slice, 0)`.
- **`std.fmt.bufPrintZ` is gone:** use `std.mem.printSentinel(buf, fmt, args, 0)` for a `[:0]u8`.
- **`std.ascii.indexOf*` are now `find*`:** `findIgnoreCase`, `findIgnoreCasePos`.
- **`std.BoundedArray` is gone:** use a fixed array with a length, or an `std.ArrayList` with an allocator.
- **`std.EnumSet` has no `initEmpty`:** use the decl literal `.empty` (or `.full`, `initMany`, `initOne`).
- **`std.DynamicBitSetUnmanaged` is deprecated:** it is `std.bit_set.Dynamic` (`initEmpty(gpa, len)`, `deinit(gpa)`).

### Tests

- **Tests in imported files need a reference:** a `pub const foo = @import("foo.zig")` re-export is lazily analyzed, so `foo.zig`'s tests are silently never run. Put `test { std.testing.refAllDecls(@This()); }` in the module root and check the summary counts.
- **A function no test calls is never compiled:** `zig build test` can pass while `zig build` fails. Always run both.
- **`refAllDecls` is not recursive and does not lay out every type:** `refAllDeclsRecursive` no longer exists; force layouts with `@sizeOf(T)` on types you depend on. On big APIs it can hit the branch quota; put `@setEvalBranchQuota(100_000)` before it.
- **Tests run in random order** (the runner takes a `--seed`): tests sharing state must set and restore it themselves.
- **`+- run test w` plus `failed command:` is not a failure:** the build runner prints a passing step that wrote to stderr this way. Check the `Build Summary` line and the exit code.
- **Never delete files inside `.zig-cache/o/`:** the cache manifests still point at them and cached steps then fail with no useful message. Remove the whole `.zig-cache` or nothing.

### Build system and packages

- **`zig fetch` takes a branch as `#name`, not `?ref=name`:** `git+https://host/repo?ref=main` ignores the query and pins the default branch with no error. Fetch `git+https://host/repo#main`; `--save` then writes `?ref=main#<commit>`. (Relevant to D46.)
- **Module names in dependencies:** a package's module is fetched under the name its own `build.zig` passed to `b.addModule`, and the consumer aliases it freely via `mod.addImport("name", dep.module("root"))`.
- **Dependency scripts run eagerly:** every non-lazy dependency's `build.zig` runs on every `zig build`, even when nothing imports it. `.lazy = true` only defers fetching.
- **Lazy compilation prunes unused modules:** a module the root never references is dropped entirely, including its link flags. Force it in with `comptime { _ = @import("name"); }`.
- **`std.Build`: `b.getInstallPath()` no longer exists**, which breaks third-party build scripts written for older Zig.
- **`LazyPath.getPath` is gone:** for a file in a dependency use `dep.builder.root.joinString(b.allocator, "sub/path")`.
- **Build `Run` args have `2` variants:** `addFileArg2(lp, .{})`, `addOutputFileArg2(name, .{})`, `addDepFileOutputArg2(name, .{})`; the old ones are deprecated.
- **`@embedFile` only reaches files inside the importing module's root directory:** have `build.zig` copy the file next to a generated root (`b.addWriteFiles()`) and import that.
- **C sources (e.g. tree-sitter):** `b.addTranslateC` on a one-line header including the library's headers gives Zig bindings; add the library's include tree and `linkLibrary` it on the module `createModule` returns. `TranslateC.linkSystemLibrary` runs pkg-config for a system library.
- **`addConfigHeader` with a `false` value still defines the macro:** only `null` leaves it undefined; map options with `if (flag) true else null`.
- **`-include` in C flags needs an absolute path:** a bare file name fails with "checking cache failed: file_open FileNotFound".
- **`zig cc` fuses multiply-adds by default** (`-ffp-contract=on`); pass `-ffp-contract=off` to C code that relies on exact rounding.
- **`__builtin_cpu_supports` does not link:** Zig's compiler-rt has no `__cpu_model`.
- **`zig build --fork=path` needs a `build.zig.zon` there:** for a plain C package, try local changes with a temporary `.path` in the root's `build.zig.zon`.
