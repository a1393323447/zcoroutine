# zcoroutine
`zcoroutine` is a simple coroutine library written in `Zig`.
# Api
## `coInit`
`coInit` / `coDeinit` is used to init / deinit the global coroutine manager.
```zig
pub fn coInit(allocator: Allocator) !void;
pub fn coDeinit() void;
```
example:
```zig
try coInit(arena.allocator());
defer coDeinit();
```
## `coStart`, `yield` and `Await`
`coStart` is used to start a coroutine and return a coroutine handle.

`yield` is used to switch to another coroutine if have one.

`Await` is a member method in CoHandle. It's used to wait for corresponding coroutine to finish running and get the return value.
```zig
/// default coroutine stack size
const DEFAULT_STACK_SIZE: usize = 128 * 1024;
pub const CoConfig = struct {
    /// a name of coroutine, providing debug info
    /// can be aquaire by `coThisName()` inside a coroutine
    name: []const u8 = "unnamed",
    stack_size: usize = DEFAULT_STACK_SIZE,
};

pub fn CoHandle(comptime Res: type) type {
    return struct {
        const Self = @This();
        pub fn Await(self: *const Self) !Res;
    }
}

pub fn coStart(comptime function: anytype, args: anytype, config: ?CoConfig) !*const CoHandle(ResTypeOfFn(function));
```
example:
```zig
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
const handle: *const CoHandle(usize) = try coStart(sayHi, .{ "Foo", i }, .{ .name = "sayHi" });
const sum = try handle.Await();
```