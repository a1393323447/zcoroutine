const std = @import("std");
const testing = std.testing;
const core = @import("core.zig");

pub const yield = core.yield;
pub const coInit = core.coInit;
pub const coStart = core.coStart;
pub const coSleep = core.coSleep;
pub const coDeinit = core.coDeinit;
pub const CoHandle = core.CoHandle;
pub const CoConfig = core.CoConfig;

fn sleep_test(s: u32) void {
    std.debug.print("[Trace] {d} Try to sleep {d} s.\n", .{s, (100 - s)});
    coSleep((100 - s) * 1000 * 1000) catch return;
    std.debug.print("[Trace] {d} wake up!\n", .{s});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // init coroutine manager
    try coInit(arena.allocator());
    defer coDeinit();

    var handles = std.ArrayList(*const CoHandle(void)).init(arena.allocator());
    defer handles.deinit();

    for (0..100) |i| {
        const handle = try coStart(sleep_test, .{@intCast(u32, i)}, null);
        try handles.append(handle);
    }

    for (handles.items) |handle| {
        try handle.Await();
    }
}
