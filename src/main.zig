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

fn sleepTest(s: u32) void {
    std.debug.print("[Trace] {d} Try to sleep {d} s.\n", .{s, (10 - s)});
    coSleep((10 - s) * 1000 * 1000) catch return;
    std.debug.print("[Trace] {d} wake up!\n", .{s});
}

fn sum(start: usize, end: usize) usize {
    var total: usize = 0;
    for (start..end) |v| {
        total += v;
        if (v % 1000 == 0) {
            std.debug.print("co {} yield\n", .{start});
            core.yield();
            std.debug.print("co {} yield return\n", .{start});
        }
    }

    return total;
}

fn child(id: usize) void {
    std.debug.print("[Trace] child {} start !\n", .{ id });
    std.debug.print("[Trace] Sleep for {}s\n", .{ id });
    core.coSleep(@intCast(1000 * 1000 * id)) catch return;
    std.debug.print("[Trace] child {} wake up\n", .{ id });
}

fn spawnChildren(allocator: std.mem.Allocator) void {
    var handles = std.ArrayList(*const CoHandle(void)).init(allocator);
    defer handles.deinit();

    for (0..10) |i| {
        const handle = coStart(child, .{@as(u32, @intCast(i))}, null) catch return;
        handles.append(handle) catch return;
    }

    for (handles.items) |handle| {
        handle.Await() catch return;
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // init coroutine manager
    try coInit(arena.allocator());
    defer coDeinit();

    var handles = std.ArrayList(*const CoHandle(void)).init(arena.allocator());
    defer handles.deinit();
    for (0..10) |i| {
        const handle = try coStart(sleepTest, .{@as(u32, @intCast(i))}, null);
        try handles.append(handle);
    }

    const spawn_handle = try coStart(spawnChildren, .{ arena.allocator() }, null);

    var sum_handles = std.ArrayList(*const CoHandle(usize)).init(arena.allocator());
    defer sum_handles.deinit();
    for (0..10) |i| {
        const handle = try coStart(sum, .{ i * 10000, (i + 1) * 10000 }, null);
        try sum_handles.append(handle);
    }

    try spawn_handle.Await();

    for (sum_handles.items, 0..) |handle, i| {
        const total = try handle.Await();
        std.debug.print("sum {} = {}\n", .{i*10000, total});
    }

    for (handles.items) |handle| {
        try handle.Await();
    }
}
