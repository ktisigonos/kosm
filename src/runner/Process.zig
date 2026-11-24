//! What std's start code sets up for `main(init: std.process.Init)`, except that a debug or safe
//! build's allocator records no stack trace for each allocation. Every memory check stays, but
//! the traces doubled a debug apply, and loading the debug information for the first one cost
//! every run of a runner about 0.09 s.

const Process = @This();

const std = @import("std");
const builtin = @import("builtin");

safe_allocator: std.heap.SafeAllocator,
arena: std.heap.ArenaAllocator,
threaded: std.Io.Threaded,
environ_map: std.process.Environ.Map,

/// As std's start code chooses, so a fast or small build runs without the checks.
const uses_safe_allocator = switch (builtin.mode) {
    .debug, .safe => true,
    .fast, .small => false,
};

/// Sets up `process` in place and returns the `Init` a `main` is given. `process` must not
/// move until `stop`.
pub fn start(process: *Process, minimal: std.process.Init.Minimal) !std.process.Init {
    process.safe_allocator = .init(std.heap.page_allocator, .{ .stack_trace_frames = 0 });
    const gpa = process.allocator();
    process.arena = .init(std.heap.page_allocator);
    errdefer process.arena.deinit();
    process.threaded = .init(gpa, .{ .argv0 = .init(minimal.args), .environ = minimal.environ });
    errdefer process.threaded.deinit();
    process.environ_map = try minimal.environ.createMap(gpa);
    errdefer process.environ_map.deinit();
    return .{
        .minimal = minimal,
        .arena = &process.arena,
        .gpa = gpa,
        .io = process.threaded.io(),
        .environ_map = &process.environ_map,
        .preopens = try .init(process.arena.allocator()),
    };
}

/// Frees what `start` set up. Leaks are logged, as std's start code does, and change nothing else.
pub fn stop(process: *Process) void {
    process.environ_map.deinit();
    process.threaded.deinit();
    process.arena.deinit();
    if (uses_safe_allocator) _ = process.safe_allocator.deinit();
}

fn allocator(process: *Process) std.mem.Allocator {
    if (uses_safe_allocator) return process.safe_allocator.allocator();
    return if (builtin.link_libc) std.heap.c_allocator else std.heap.smp_allocator;
}
