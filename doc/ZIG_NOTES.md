# Zig 0.17 notes

Purpose: stop agents (and humans) from repeating the same mistakes. Zig is pre-1.0 and its std and build APIs change between releases, so training data is often stale. The first entries were carried over from Agon, a sibling project on the same Zig.

## How to use this file

- **Read it before writing code.**
- **Append a line whenever you hit a Zig gotcha** (an API that moved, a compile error that surprised you, a build.zig quirk). Keep entries to 1-3 lines with a tiny example if it helps.
- Do not delete entries unless they are verified wrong.

## Where to look things up

- Toolchain verified: Zig 0.17.0 (`zig version`), 2026-11-05.
- Language reference: `doc/generated/zig/` (run `./fetch-docs.sh`; one file per chapter, search across the directory, open only small chapters whole).
- Zig std source: run `zig env` and use `.std_dir`; see `.agents/zig.md` for the search commands.
- **`zig env` prints ZON, not JSON:** a JSON-style pattern (`"std_dir": *"..."`) matches nothing. Use `zig env | grep -o '\.std_dir = "[^"]*"' | cut -d'"' -f2`. `std.builtin.Type` lives in `std/lang.zig`, not `builtin.zig`.
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
- **Locals and captures may not shadow a file-level declaration either:** a private `fn text(...)` makes every `var text` and `|text|` in the file "local variable shadows declaration"; give the function a longer name (`textValue`).
- **A field of a typed struct literal does not parse:** `Params{}.blur` is "expected `;` after statement"; bind the literal first (`const params: Params = .{};`).
- **`&.default` does not give the address of the decl:** coercing to `*const T` makes a static copy, so `x == &T.default` is false. Compare the values.
- **Empty exhaustive enums are rejected:** an enum with no fields, only decls, fails with "empty exhaustive enums must be backed by 'noreturn'". Add `_,` to make it non-exhaustive.
- **Float math at comptime burns the branch quota fast:** one sRGB -> OKLCH conversion (`std.math.pow`, `cbrt`) costs a few hundred backwards branches, and a file-level `const` literal evaluates all its calls under one quota, so five `kosm.hex` calls exceed the default 1000. A comptime helper sets its own `@setEvalBranchQuota` inside its `comptime` block; test it from a file-level `const` with many calls.
- **Untyped file-level number constants break mixed division:** `const h = 2;` then `h / @tan(x)` at comptime is "ambiguous coercion of division operands"; give such constants a type (`const h: f32 = 2;`).
- **`@max` of comptime-known lengths takes the smallest fitting type:** `@max(a.len, b.len) + 2` with lengths 14 and 10 is a `u4`, so the `+ 2` overflows at comptime. Widen first: `@as(usize, @max(a.len, b.len)) + 2`.
- **Indexing an empty array with a runtime index is a compile error**, even on a path that never runs: `var given: [0]bool` then `given[i]` is "cannot index into empty array". Return early under `if (comptime fields.len == 0)` so the rest is not analyzed.
- **A function's return type is analyzed before any check in its body:** `fn f(comptime t: T) @TypeOf(@field(t.file, t.name))` fails with Zig's own "no member named" before a friendlier `@compileError` inside can run. Do the check in a separate `comptime check(t);` statement first.
- **`@abs` of a signed integer returns the unsigned type:** `@intCast` it back before mixing with signed values.
- **Anonymous struct literals passed as `anytype` keep comptime fields:** `.{ .text = @embedFile("x"), .format = runtime_value }` gives `text` a comptime field (`@typeInfo(T).@"struct".field_attrs[i].@"comptime"`), so `comptime options.text` works next to runtime fields.
- **An anonymous struct literal inside an `anytype` argument does not coerce to a struct type later:** `options.format` from `.{ .format = .{ .boolean = .one_zero } }` is its own anonymous type, so `const own: Format = options.format;` fails. Require the typed value (`Format{ ... }`, `self.format`) and check it with `@FieldType(Options, "format") != Format` for a clear `@compileError`.
- **Result locations alias the target:** `node = .{ .key = key, .children = try dupe(Node, &.{node}) };` writes `.key` into `node` before `dupe` reads it, so the copy holds the new key. Compute the right-hand values into a `const` first.
- **`@floatCast` from f64 to f32 never traps:** out-of-range values become +/-inf, so check `std.math.isFinite` after narrowing. A widened f32 keeps its exact binary value (`6.4` prints as `6.400000095367432`).
- **`Union.tag` is the tag enum, not a union value:** `FontStyle.disabled` passed to an `anytype` parameter has the type `@typeInfo(FontStyle).@"union".tag_type`, so code checking for the union never sees it. Coerce first: `@as(FontStyle, .disabled)` (a typed field does this for you).
- **`{t}` prints an enum's tag name:** `writer.print("{t}", .{direction})` writes `up`, no `@tagName` needed.
- **`type` is a plain field name, `error` is not:** `zig fmt` turns `@"type": Color` and `.@"type"` into `type: Color` and `.type`, but `error` still needs `@"error"`.

### std

- **`std.fs` is a deprecated shim - the filesystem lives in `std.Io`:** use `std.Io.Dir`/`std.Io.File`. Whole-file read: `std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(n))`; stdin: `std.Io.File.stdin().reader(io, &buf)` then `.interface`; buffered stdout: `std.Io.File.stdout().writer(io, &buf)` then `.interface` and `flush()`. All take an `Io`.
- **`std.fs.path` is a deprecated shim:** path helpers (`dirname`, `stem`, `basename`) live in `std.Io.Dir.path`.
- **`std.Io.Dir.cwd()` cannot iterate:** iterating it is *illegal behavior with no error*. Open a real handle with `openDir(io, ".", .{ .iterate = true })` first.
- **`readFileAlloc` of a path under a regular file is `error.NotDir`, not `FileNotFound`:** treat only `FileNotFound` as "missing". To make only a later write fail in a test, use a read-only folder (`setFilePermissions(io, "locked", .fromMode(0o500), .{})`): reading a missing file there still gives `FileNotFound`.
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
- **`std.fmt.allocPrint` is deprecated:** use `allocator.print(format, args)`.
- **Custom formatting is a `format` method plus `{f}`:** `pub fn format(self: T, writer: *std.Io.Writer) std.Io.Writer.Error!void`, printed with `"{f}"`; `std.meta.hasMethod(T, "format")` detects it. A union switch can capture both payload and tag: `inline else => |payload, tag|`.
- **Running a command takes an `Io`:** `std.process.spawn(io, .{ .argv = argv, .stdout = .ignore })` then `child.wait(io)` gives a `Child.Term` union (`exited`, `signal`, ...); `term.success()` checks for exit 0, and `Term` prints itself with `{f}` ("exited with code 1"). A missing program is `error.FileNotFound` from `spawn`.
- **ZON with arbitrary keys:** `std.zon.parse.fromSlice` needs fixed field names. Parse with `std.zig.Ast.parse(.., .{ .mode = .zon })` and `std.zig.ZonGen.generate`, walk `Zoir.Node.Index.root.get(&zoir).struct_literal` (`names[i].get(&zoir)`, `vals.at(i)`), and parse each value with `std.zon.parse.fromZoir(T, .{ .node = ... })`, which fills the usual `Diagnostics`. `fromZoir(struct {}, .{ .ignore_unknown_fields = true })` on the root reports syntax errors. `getAstNode` plus `ast.firstToken`/`lastToken`/`tokenStart` give an entry's byte range.
- **`std.BoundedArray` is gone:** use a fixed array with a length, or an `std.ArrayList` with an allocator.
- **`std.EnumSet` has no `initEmpty`:** use the decl literal `.empty` (or `.full`, `initMany`, `initOne`).
- **`std.DynamicBitSetUnmanaged` is deprecated:** it is `std.bit_set.Dynamic` (`initEmpty(gpa, len)`, `deinit(gpa)`).

- **`output.template` reads every `kosm.` in the text as a placeholder,** prose included ("written by kosm. Its" fails to compile with "unknown field"), and has no escape. Reword prose, and pass literal names that must contain `kosm.` (pref names) as fields of the template's app.

### Tests

- **Tests in imported files need a reference:** a `pub const foo = @import("foo.zig")` re-export is lazily analyzed, so `foo.zig`'s tests are silently never run. Put `test { std.testing.refAllDecls(@This()); }` in the module root and check the summary counts.
- **A function no test calls is never compiled:** `zig build test` can pass while `zig build` fails. Always run both.
- **`refAllDecls` is not recursive and does not lay out every type:** `refAllDeclsRecursive` no longer exists; force layouts with `@sizeOf(T)` on types you depend on. On big APIs it can hit the branch quota; put `@setEvalBranchQuota(100_000)` before it.
- **A test that runs `zig build` on other files is cached on its own inputs only:** editing just `build/config_project.zig` leaves `run test cached`, so a check of that file never reruns. Change the test file too (or the cache key) before trusting a pass.
- **Tests run in random order** (the runner takes a `--seed`): tests sharing state must set and restore it themselves.
- **`+- run test w` plus `failed command:` is not a failure:** the build runner prints a passing step that wrote to stderr this way. Check the `Build Summary` line and the exit code.
- **Never delete files inside `.zig-cache/o/`:** the cache manifests still point at them and cached steps then fail with no useful message. Remove the whole `.zig-cache` or nothing.

### Build system and packages

- **0.17 caches the configure phase:** `build.zig` is not rerun when nothing it declared changed. A build script that lists a directory must call `b.dependOnDirectoryContents(b.path("kosmoi"))` (or `b.graph.poisonCache()`), or new files go unseen. Open the directory via `std.Io.Dir.cwd().openDir(b.graph.io, b.root.joinString(b.allocator, "kosmoi"), .{ .iterate = true })`.
- **Package `.name` must be a bare identifier:** `.name = .@"kosm-sample"` is "name must be a valid bare zig identifier". Dashes work only in the consumer's key: `zig fetch --save=kosm-sample <url>` writes `.@"kosm-sample" = .{ ... }`, and the module name in `b.addModule("kosm-sample", ...)` is free.
- **`zig fetch --save` of a local tarball path writes `.path = "x.tar.gz"`:** use a `file:///abs/x.tar.gz` URL to get a real `.url` + `.hash` entry.
- **A file can be the root of only one module:** if `kosmoi/base.zig` is a module root and `kosmoi/frost.zig` does `@import("base.zig")`, the build fails with "file exists in modules 'a' and 'b'". Import it by module name instead; cyclic module imports are fine.
- **Each pinned copy of a package is a separate module:** a package built against another `kosm` hash gives "expected type 'Theme', found 'Theme'". `module.addImport(name, other)` overwrites an existing entry in `module.import_table`, so a root build can re-point a dependency's import to its own copy.
- **A dependency's `build.zig` is importable from `build.zig`:** `@import("kosm").addConfigProject(b, @import("build.zig.zon"))` works, and `@import("build.zig.zon")` without a result type is an anonymous struct whose `.dependencies` field names can be walked with `inline for`.
- **`@typeName` of a file struct is relative to its module, not its package:** `packages/kosm_kitty/App.zig` is just `"App"`. To print it as the user imports it (`kosm_kitty.App`), search the package root's decls for the type.
- **`decl_names` lists only `pub` declarations:** private functions in a file never show up when walking `@typeInfo(File).@"struct".decl_names`.

- **`zig fetch` takes a branch as `#name`, not `?ref=name`:** `git+https://host/repo?ref=main` ignores the query and pins the default branch with no error. Fetch `git+https://host/repo#main`; `--save` then writes `?ref=main#<commit>`. (Matters for `kosm add` and `kosm update`.)
- **Module names in dependencies:** a package's module is fetched under the name its own `build.zig` passed to `b.addModule`, and the consumer aliases it freely via `mod.addImport("name", dep.module("root"))`.
- **Dependency scripts run eagerly:** every non-lazy dependency's `build.zig` runs on every `zig build`, even when nothing imports it. `.lazy = true` only defers fetching.
- **Lazy compilation prunes unused modules:** a module the root never references is dropped entirely, including its link flags. Force it in with `comptime { _ = @import("name"); }`.
- **`b.args` is gone:** forward `zig build run -- ...` arguments with `run.addPassthruArgs()`.
- **A `.path` dependency must be relative to the build root:** an absolute `.path = "/home/..."` is "expected path relative to build root; found absolute path".
- **Failing a build from `build.zig` with a message:** `b.getInstallStep().dependOn(&b.addFail(message).step)` prints the message under the failed step; no panic needed.
- **`std.Build`: `b.getInstallPath()` no longer exists**, which breaks third-party build scripts written for older Zig.
- **`LazyPath.getPath` is gone:** for a file in a dependency use `dep.builder.root.joinString(b.allocator, "sub/path")`.
- **Build `Run` args have `2` variants:** `addFileArg2(lp, .{})`, `addOutputFileArg2(name, .{})`, `addDepFileOutputArg2(name, .{})`; the old ones are deprecated.
- **`@embedFile` only reaches files inside the importing module's root directory:** have `build.zig` copy the file next to a generated root (`b.addWriteFiles()`) and import that.
- **C sources (e.g. tree-sitter):** `b.addTranslateC` on a one-line header including the library's headers gives Zig bindings; add the library's include tree and `linkLibrary` it on the module `createModule` returns. `TranslateC.linkSystemLibrary` runs pkg-config for a system library.
- **`addConfigHeader` with a `false` value still defines the macro:** only `null` leaves it undefined; map options with `if (flag) true else null`.
- **`-include` in C flags needs an absolute path:** a bare file name fails with "checking cache failed: file_open FileNotFound".
- **`zig cc` fuses multiply-adds by default** (`-ffp-contract=on`); pass `-ffp-contract=off` to C code that relies on exact rounding.
- **`__builtin_cpu_supports` does not link:** Zig's compiler-rt has no `__cpu_model`.
- **A package needs no `build.zig`, only a `build.zig.zon`:** fetched by path or archive, its manifest still drives transitive fetches. The consumer reads its files with `dep.path("root.zig")` and reaches its dependencies with `dep.builder.dependency("name", .{})`. (`b.lazyImport` of such a package is a compile error: there is no build.zig to import.)
- **`zig fetch --save` needs a `build.zig` in the cwd or a parent:** to edit a zon-only manifest, write it directly and get the hash from plain `zig fetch <url>` (last line of output).
- **A package hash starts with its manifest name:** `zig fetch <url>` (no `--save`) prints `kosm_kitty-0.1.0-<hash>`, so the name is known before anything is saved. `zig fetch --save` silently overwrites an existing entry of that name.
- **`zig fetch` takes a plain `.tar` by `file:///abs/x.tar`:** `std.tar.Writer` (`.{ .underlying_writer = w }`, `writeFileBytes`, `finishPedantically`) builds one in a test. `ZIG_GLOBAL_CACHE_DIR` keeps fetched packages out of `~/.cache/zig`.
- **A dependency whose `build.zig` declares no `standardTargetOptions`/`standardOptimizeOption`** prints `invalid option: "target"` (plus a stack trace) when the consumer passes `.target`/`.optimize` to `b.dependency`, yet the build still succeeds.
- **Every manifest needs a valid `.fingerprint`:** it is tied to the package name; `0x0` fails with "invalid fingerprint", and the error prints the value to use for a new package. Never change it once published.
- **A package fingerprint is `crc32(name) << 32 | id`:** `id` is a random u32 other than 0 and `0xffffffff` (`std.hash.Crc32.hash(name)`); it is generated in the compiler, not std. `Dir.walkSelectively` + `enter` walks a tree while skipping folders, in no defined order.
- **`zig build --fork=path` needs a `build.zig.zon` there:** for a plain C package, try local changes with a temporary `.path` in the root's `build.zig.zon`.
- **tree-sitter's own `build.zig` (v0.26.13, v0.27.1) fails on 0.17** (`addCSourceFile` moved to the module), and every dependency's build script is compiled, so depending on its git repo breaks the whole build. Fetch the crates.io archive instead (`https://static.crates.io/crates/tree-sitter/tree-sitter-<v>.crate`): the same C runtime with no `build.zig`. Compile `src/lib.c` with `include/` and `src/` as include paths.
- **`zig fetch` strips an archive's single top-level directory:** the crate's `tree-sitter-0.26.13/src/lib.c` is `dep.path("src/lib.c")`.
- **Grammar repos (tree-sitter-json, -lua, -hyprlang) have no `build.zig.zon` or `build.zig`:** they fetch as `N-V-__8AA...` hashes and their generated `src/parser.c` (plus `src/scanner.c` when present) is compiled by the consumer.
- **A translate-C header needs no file in the repo:** `b.addWriteFiles().add("api.h", "#include <tree_sitter/api.h>\n")` gives the `LazyPath` for `addTranslateC`.
- **`zig build --fork=<dir>` replaces a dependency by name and fingerprint, never fetching it:** it matches only url + hash dependencies (the hash carries the name and fingerprint id), so a `.path` dependency is never forked, and a fork that matches nothing fails the build ("fork ... matched no kosm packages"). The forked package's `build.zig` is the one `@import("kosm")` loads. The path must be absolute: a relative `--fork=../x` crashes the build runner (reached unreachable code).
- **A `.path` dependency inside a forked package fails** with "expected path relative to build root; found absolute path", and a package listing a subdirectory as a `.path` dependency that depends back on it with `.path = "../.."` fails once fetched ("file exists in modules"). Expose such sub-packages as modules of the parent's own build instead.
- **`zig fetch --save` of a git URL pins the commit:** it writes `git+https://host/repo#<sha>`, while plain `zig fetch` prints only the hash. To get Zig's resolved url without touching the real manifest, run `--save` in a throwaway project (it needs a `build.zig` and a `build.zig.zon`) and read the entry back. `zig fetch --save` of a local directory writes its absolute path as `.url`.
- **`zig fetch --save` over an existing `.path` entry keeps the `.path` key:** it writes the url (or the absolute directory) into `.path` with no hash, and the build then fails with "expected path relative to build root". Delete the entry first to get `.url` + `.hash`.
- **A package hash depends only on the files its `.paths` keep:** `git archive <commit>` fetched as `file:///abs/x.tar` gives the same hash as `git+https://host/repo#<commit>`, so a url + hash entry for a commit can be written before the commit is pushed, and a package already in the cache under that hash builds offline.
- **Array hash maps grow before they look:** `put` and `getOrPut` reserve capacity first, so replacing a value while iterating `map.keys()` / `map.values()` can free those slices. `Module.addImport` is such a `put`; loop by index and read `keys()[index]` each time.
- **Files a build script reads by hand need registering:** a `build.zig` reading a manifest with `std.Io.Dir.cwd()` must call `b.dependOnFileContents(b.path(...))`, or the cached configure phase keeps the old contents.
- **A test that runs `zig build` on other projects is cached like any test:** its run step reruns only when the test binary changes, so a broken file it builds can hide behind a cached pass. Set `has_side_effects = true` on that `Run` step.
- **`std.process.executableDirPathAlloc(io, allocator)`** gives the running binary's directory with symlinks followed (`/proc/self/exe` on Linux).
- **ZLS 0.17 reads modules from the build's compile steps:** a module made with `b.createModule` that no step reachable from a top-level step compiles is invisible, so its imports never resolve in the editor. `zig build --print-configuration` shows what ZLS gets; a `check` step of `b.addObject(.{ .name, .root_module })` per module fixes it. ZLS can't pass `--fork`.
- **`std.mem.indexOf` at comptime runs out of branch quota fast:** on a few hundred bytes of text it passes the default 1000 backwards branches. Build expected test strings at runtime (`std.mem.replaceOwned` on an arena) instead of raising `@setEvalBranchQuota`.
- **A `b.option([]const []const u8, ...)` is repeated on the command line:** `-Dinspect=a -Dinspect=b` gives `.{ "a", "b" }` in order; a single `-Dinspect=a` gives a one-item list.
- **Debug builds on x86_64 Linux already use Zig's own backend:** forcing `.use_llvm = true` made a kosmos runner take 15.7 s instead of 2.9 s. `-fincremental` without `--watch` was slower (5.2 s), and `.strip = true` saved only about 8%.
- **Every `zig build` configures the whole dependency tree:** with about 30 packages that costs about 0.35 s even when everything is cached, so one build doing N things beats N builds.
