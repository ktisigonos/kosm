//! Spreads independent work over the machine's cores. Kosm's own; apps reach it through
//! `Output.parallel`.

const std = @import("std");

/// How many workers `run` starts for `item_count` items: one per core, never more than items.
pub fn workerCount(item_count: usize) usize {
    const cores = std.Thread.getCpuCount() catch 1;
    return @max(1, @min(item_count, cores));
}

/// Calls `work(context, worker, item)` once for every `item` below `item_count`, spread over
/// `workerCount(item_count)` workers, and returns when every call has returned. `worker` is
/// below `workerCount(item_count)`; one worker never runs two calls at once, so state indexed
/// by it needs no lock. Each worker takes the next item in order.
pub fn run(io: std.Io, item_count: usize, context: anytype, comptime work: fn (@TypeOf(context), usize, usize) void) void {
    if (item_count == 0) return;
    const Context = @TypeOf(context);
    const Shared = struct {
        next: std.atomic.Value(usize) = .init(0),
        item_count: usize,
        context: Context,

        fn loop(shared: *@This(), worker: usize) void {
            while (true) {
                const item = shared.next.fetchAdd(1, .monotonic);
                if (item >= shared.item_count) return;
                work(shared.context, worker, item);
            }
        }
    };
    var shared: Shared = .{ .item_count = item_count, .context = context };
    var group: std.Io.Group = .init;
    for (0..workerCount(item_count)) |worker| group.async(io, Shared.loop, .{ &shared, worker });
    group.await(io) catch |err| switch (err) {
        // Kosm runs on plain threads, never as an `Io` task, so nothing can cancel it.
        error.Canceled => unreachable,
    };
}

const testing = std.testing;

test "run calls work once for every item, each worker below the worker count" {
    const count = 1000;
    var calls: [count]std.atomic.Value(u32) = @splat(.init(0));
    var bad_worker: std.atomic.Value(bool) = .init(false);
    const Context = struct {
        calls: *[count]std.atomic.Value(u32),
        bad_worker: *std.atomic.Value(bool),

        fn work(context: @This(), worker: usize, item: usize) void {
            if (worker >= workerCount(count)) context.bad_worker.store(true, .monotonic);
            _ = context.calls[item].fetchAdd(1, .monotonic);
        }
    };
    run(testing.io, count, Context{ .calls = &calls, .bad_worker = &bad_worker }, Context.work);
    for (&calls) |*call| try testing.expectEqual(1, call.load(.monotonic));
    try testing.expect(!bad_worker.load(.monotonic));
}

test "run with no items calls nothing" {
    const Context = struct {
        fn work(_: @This(), _: usize, _: usize) void {
            unreachable; // no item, no call
        }
    };
    run(testing.io, 0, Context{}, Context.work);
}
