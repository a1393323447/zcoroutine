const std = @import("std");
const testing = std.testing;
const core = @import("core.zig");

pub const yield = core.yield;
pub const coInit = core.coInit;
pub const coStart = core.coStart;
pub const coDeinit = core.coDeinit;
pub const CoHandle = core.CoHandle;
pub const CoConfig = core.CoConfig;

fn sayHi(name: []const u8, num: usize) usize {
    var sum: usize = 0;
    const cnt = (100 - num) * 100;

    for (0..cnt) |i| {
        if (i % 1000 == 0) {
            std.debug.print("{d} yield {d}...\n", .{num, i});
            yield();
        }
        sum += i;
    }
    
    std.debug.print("Hi {s}:{d} your res is = {d}\n", .{name, num, sum});
    return sum;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // init coroutine manager
    try coInit(arena.allocator());
    defer coDeinit();

    var handles = std.ArrayList(*const CoHandle(usize)).init(arena.allocator());
    defer handles.deinit();

    for (0..100) |i| {
        const handle: *const CoHandle(usize) = try coStart(sayHi, .{ "Yang", i }, .{ .name = "sayHi" });
        try handles.append(handle);
    }

    for (handles.items, 0..handles.items.len) |handle, i| {
        const sum = try handle.Await();
        std.debug.print("sum {d} = {d}\n", .{i, sum});
    }
}
