const std = @import("std");
const arch = @import("arch/arch.zig");
const Context = arch.Context;
const Allocator = @import("std").mem.Allocator;

const Timestamp = i64;

const MAIN_ID: usize = 0;
var MANAGER: ?Manager = null;

// TODO create a time module

/// get timestamp in microsecond
inline fn now() Timestamp {
    return std.time.microTimestamp();
}

/// a helper function to detect function return type
fn ResTypeOfFn(comptime function: anytype) type {
    return @typeInfo(@TypeOf(function)).Fn.return_type orelse void;
}

pub inline fn coInit(allocator: Allocator) !void {
    if (MANAGER == null) {
        MANAGER = try Manager.init(allocator);
    }
}

pub inline fn coDeinit() void {
    MANAGER.?.deinit();
}

pub inline fn coStart(comptime function: anytype, args: anytype, config: ?CoConfig) !*const CoHandle(ResTypeOfFn(function)) {
    const conf = config orelse CoConfig{};
    return MANAGER.?.coStart(function, args, conf);
}

pub inline fn coSleep(us: u32) !void {
    try MANAGER.?.coSleep(us);
}

pub inline fn yield() void {
    MANAGER.?.yield() catch |err| {
        std.debug.panic("[ERROR] in yield {s}", .{@errorName(err)});
    };
    return;
}

pub export fn mainCtxPtr() callconv(.C) *Context {
    return &MANAGER.?.getMainCCBPtr().context;
}

pub export fn currentCtxPtr() callconv(.C) *Context {
    return &MANAGER.?.getCurrentCCBPtr().context;
}

inline fn currentCCBPtr() *CCB {
    return MANAGER.?.getCurrentCCBPtr();
}

inline fn markCurFinished() void {
    MANAGER.?.markCurFinished();
}

/// default coroutine stack size
const DEFAULT_STACK_SIZE: usize = 128 * 1024;
pub const CoConfig = struct {
    /// a name of coroutine, providing debug info
    /// can be aquaire by `coThisName()` inside a coroutine
    name: []const u8 = "unnamed",
    stack_size: usize = DEFAULT_STACK_SIZE,
};

pub const CoError = error{
    /// a coroutine is terminated by accident
    UnexpectedTerminate,
    /// await on dead coroutine
    AwaitOnDeadCoroutine,
};

/// a handle to a coroutine
pub fn CoHandle(comptime Res: type) type {
    return struct {
        /// id for this Coroutine
        id: usize,
        /// a coroutine result
        /// aquire using cawait
        res: ?Res,
        allocator: Allocator,

        const Self = @This();

        pub fn Await(self: *const Self) !Res {
            while (true) {
                if (MANAGER.?.getCCBPtr(self.id)) |ccb_ptr| {
                    switch (ccb_ptr.status) {
                        .Active, .Sleep, .Frozen => yield(),
                        .Finished => {
                            defer self.deinit();
                            if (Res != void) {
                                const res = self.res.?;
                                try MANAGER.?.markCoDeadById(self.id);
                                return res;
                            } else {
                                return {};
                            }
                        },
                        .Dead => {
                            return CoError.AwaitOnDeadCoroutine;
                        },
                    }
                } else {
                    return CoError.UnexpectedTerminate;
                }
            }
        }

        fn init(id: usize, allocator: Allocator) !*Self {
            var self = try allocator.create(Self);

            self.id = id;
            self.allocator = allocator;
            self.res = null;

            return self;
        }

        inline fn deinit(self: *const Self) void {
            self.allocator.destroy(self);
        }
    };
}

const CCB = struct {
    context: Context = Context{},

    id: usize,
    name: []const u8 = "unnamed",

    start_time: Timestamp,
    elapsed: i64 = 0,
    status: Status = Status.Active,

    handle_addr: usize = 0,

    /// stack space of this coroutine
    /// must align to 16 bit
    stack: []align(16) u8,

    pub const Status = enum(usize) {
        /// the coroutine is ready or running
        Active = 0,
        Sleep = 1,
        /// the coroutine is frozen and waiting for waken by a waker
        Frozen = 2,
        /// the coroutine is finished, but is not marked as Dead by coAwait
        /// and is removed from the waiting list which means it would not be wake up again
        Finished = 3,
        /// the coroutine is marked as Dead by coAwait, waiting for destory
        /// (free its stack space and itself)
        Dead = 4,
    };

    const Self = @This();

    pub fn init(
        self: *Self,
        allocator: Allocator,
        id: usize,
        config: CoConfig,
    ) !void {
        // allocate a stack space for this coroutine
        // need to align stack space to 16
        std.debug.assert(config.stack_size % 16 == 0);
        const stack = try allocator.alignedAlloc(u8, 16, config.stack_size);
        self.stack = stack;
        
        // init context
        self.context = Context{};
        // then we need to allocate a ptr space for keeping this coroutine's handle ptr
        const sp = @ptrToInt(stack.ptr) + stack.len;
        self.context.setStack(sp);

        self.id = id;
        self.name = config.name;
        
        self.elapsed = 0;
        self.start_time = now();
        
        self.status = Status.Active;
    }

    pub fn compare(_: void, lhs: *Self, rhs: *Self) std.math.Order {
        return std.math.order(lhs.elapsed, rhs.elapsed);
    }

    pub inline fn tick(self: *Self, t_now: Timestamp) void {
        self.elapsed = t_now - self.start_time;
    }

    inline fn deinit(self: *const Self, allocator: Allocator) void {
        allocator.free(self.stack);
    }
};

pub fn ArgsWrapper(comptime Args: type) type {
    return struct {
        args: Args,
    };
}

fn TypeSafeCallTable(comptime Args: type, comptime Res: type, comptime function: anytype) type {
    return struct {
        const Self = @This();

        pub inline fn getAddr() usize {
            return @ptrToInt(&Self.call);
        }

        fn call(wrapper: *ArgsWrapper(Args))callconv(.C)  void {
            const res = @call(.auto, function, wrapper.args);
            if (Res != void) {
                // handle is allocacted on heap, so this pointer is still vaild
                var h = @intToPtr(*CoHandle(Res), currentCCBPtr().handle_addr);
                // now the coroutine return we sure that we now in this coroutine's ctx
                // that means:
                // this is *current* coroutine
                // if the res is a value type, it can safely copy from stack
                // if the res is a pointer type, it should point to space on heap
                // or on its stack, which is also valid
                h.res = res;
            }
            // then we need to mark this coroutine(*current* coroutine) as Finished
            markCurFinished();
            // yield to anthor coroutine and never return
            yield();

            unreachable;
        }
    };
}

const Manager = struct {
    next_unused_id: usize = 1,

    ccb_container: CCBContainer,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const ccb_container = try CCBContainer.init(allocator);
        return Self{
            .ccb_container = ccb_container,
            .allocator = allocator,
        };
    }

    pub inline fn deinit(self: *Self) void {
        self.ccb_container.deinit();
    }

    pub inline fn getMainCCBPtr(self: *Self) *CCB {
        return self.ccb_container.getMainCCBPtr();
    }

    pub inline fn getCurrentCCBPtr(self: *Self) *CCB {
        return self.ccb_container.cur_ccb;
    }

    pub inline fn markCurFinished(self: *Self) void {
        self.ccb_container.cur_ccb.status = .Finished;
    }

    pub inline fn markCoDeadById(self: *Self, target_id: usize) !void {
        try self.ccb_container.markDead(target_id);
    }

    pub inline fn getCCBPtr(self: *Self, target_id: usize) ?*CCB {
        return self.ccb_container.binarySearchCCB(target_id);
    }

    pub fn coStart(
        self: *Self, 
        comptime function: anytype, 
        args: anytype, 
        config: CoConfig) !*const CoHandle(ResTypeOfFn(function)) {
        const Args = @TypeOf(args);
        const Res = ResTypeOfFn(function);
        // emplace a new ccb in cbb_container and inc next_id
        const new_ccb_ptr: *CCB = try self.ccb_container.emplace(self.next_unused_id, config);
        self.next_unused_id += 1;

        // alloc a handle for new coroutine
        const handle_ptr = try CoHandle(ResTypeOfFn(function)).init(new_ccb_ptr.id, self.allocator);
        // regist handle on ccb
        new_ccb_ptr.handle_addr = @ptrToInt(handle_ptr);
        // wrap args in a struct to get their address
        const args_wapper = ArgsWrapper(Args){
            .args = args,
        };

        // update main
        const main_ccb = self.getMainCCBPtr();
        const t_now = now();
        main_ccb.tick(t_now);
        try self.ccb_container.addToWaitlist(main_ccb);
        // move to next
        self.ccb_container.cur_ccb = new_ccb_ptr;

        const type_safe_fn_addr = TypeSafeCallTable(Args, Res, function).getAddr();
        arch.initCall(@ptrToInt(&args_wapper), type_safe_fn_addr);

        return handle_ptr;
    }

    pub fn coSleep(self: *Self, us: u32) !void {
        const t_now = now();
        const cur_ccb = self.getCurrentCCBPtr();
        cur_ccb.tick(t_now);
        cur_ccb.status = .Sleep;
        const wake_at = t_now + @intCast(Timestamp, us);
        try self.ccb_container.addToSleeplist(cur_ccb.id, wake_at);
        if (self.ccb_container.moveToNext(t_now)) |next_ccb| {
            if (next_ccb.id == cur_ccb.id) {
                return;
            }
            arch.switchCtx(&cur_ccb.context, &next_ccb.context);
        } else {
            std.time.sleep(@intCast(u64, us * std.time.ns_per_us));
        }
    }

    pub fn yield(self: *Self) !void {
        const t_now = now();
        const cur_ccb = self.getCurrentCCBPtr();
        if (self.ccb_container.moveToNext(t_now)) |next_ccb| {
            if (cur_ccb.status == .Active) {
                cur_ccb.tick(t_now);
                try self.ccb_container.addToWaitlist(cur_ccb);
            }
            arch.switchCtx(&cur_ccb.context, &next_ccb.context);
        }
        return;
    }
};

const CCBContainer = struct {
    /// a pointer to current ccb
    cur_ccb: *CCB,
    /// a dyn array that store the actual coroutine control block data
    /// ccb.id will consist in accending order
    ccb_data: []CCB,
    /// total num of cbbs
    size: usize = 1,
    /// the num of alive(Active and Finished) ccb
    alive: usize = 1,
    /// a priority dequeue that manage ccb by their elapsed time
    /// a coroutine waitlist
    waitlist: WaitList,
    /// a priority dequeue that manage sleep ccb by their wake_at time
    sleeplist: SleepList,
    
    allocator: Allocator,

    const INIT_CAP: usize = 8;
    
    const SleepCCB = struct {
        id: usize,
        wake_at: Timestamp,
        pub fn compare(_:void, a: @This(), b: @This()) std.math.Order {
            return std.math.order(a.wake_at, b.wake_at);
        }
    };
    const Self = @This();
    const SleepList = std.PriorityDequeue(SleepCCB, void, SleepCCB.compare);
    const WaitList = std.PriorityDequeue(*CCB, void, CCB.compare);
    

    pub fn init(allocator: Allocator) !Self {
        const ccb_data: []CCB = try allocator.alloc(CCB, INIT_CAP);
        // init main ccb
        const main_ccb: *CCB = &ccb_data[0];
        try main_ccb.init(allocator, MAIN_ID, CoConfig{
            .name = "main",
            // allocate a dummy stack for main
            .stack_size = 0,
        });
        const waitlist = WaitList.init(allocator, {});
        const sleeplist = SleepList.init(allocator, {});
        return Self {
            .cur_ccb = main_ccb,
            .ccb_data = ccb_data,
            .waitlist = waitlist,
            .sleeplist = sleeplist,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.waitlist.deinit();
        const len = self.size;
        for (self.ccb_data[0..len]) |ccb| {
            ccb.deinit(self.allocator);
        }
        self.allocator.free(self.ccb_data);
    }

    pub inline fn getMainCCBPtr(self: *Self) *CCB {
        std.debug.assert(self.ccb_data[0].id == MAIN_ID);
        return &self.ccb_data[0];
    }

    pub inline fn addToWaitlist(self: *Self, ccb_ptr: *CCB) !void {
        try self.waitlist.add(ccb_ptr);
    }

    pub inline fn addToSleeplist(self: *Self, id: usize, wake_at: Timestamp) !void {
        const sleep_ccb = SleepCCB {
            .id = id,
            .wake_at = wake_at,
        };
        try self.sleeplist.add(sleep_ccb);
    }

    pub fn moveToNext(self: *Self, t_now: Timestamp) ?*CCB {
        // first we try to wake up the sleep coroutine
        const DELTA: Timestamp = -1000;
        var op_sleep_ccb: ?*CCB = null;
        var wake_at: Timestamp = 0;
        if (self.sleeplist.peekMin()) |sleep_ccb| {
            const diff = t_now - sleep_ccb.wake_at;
            if (diff >= DELTA) {
                // remove this coroutine from sleeplist
                _ = self.sleeplist.removeMin();
                if (self.binarySearchCCB(sleep_ccb.id)) |next_ccb_ptr| {
                    self.cur_ccb = next_ccb_ptr;
                    // recored the sleep ccb we find
                    op_sleep_ccb = next_ccb_ptr;
                    wake_at = sleep_ccb.wake_at;
                    return next_ccb_ptr;
                }
            }
        }
        // then we search on waitlist
        if (self.waitlist.removeMinOrNull()) |next_ccb_ptr| {
            self.cur_ccb = next_ccb_ptr;
            return next_ccb_ptr;
        }

        // if no ccb on wait list and we found a sleep ccb
        // then we wait for the sleep ccb
        if (op_sleep_ccb) |sleep_ccb| {
            const us_sleep = now() - wake_at;
            const nano_sleep = std.math.max(0, us_sleep) * std.time.ns_per_us;
            std.time.sleep(@intCast(u32, nano_sleep));
            return sleep_ccb;
        }

        return null;
    }

    /// emplace a CCB in ccb_data
    /// return a ptr to new CCB if success
    pub fn emplace(self: *Self, id: usize, config: CoConfig) !*CCB {
        try self.ensureUnusedCapacity(1);
        const new_ccb_ptr = &self.ccb_data[self.size];
        try new_ccb_ptr.init(self.allocator, id, config);
        self.size += 1;
        self.alive += 1;

        return new_ccb_ptr;
    }

    /// search a CCB with target_id
    pub fn binarySearchCCB(self: *Self, target_id: usize) ?*CCB {
        var left: isize = 0;
        var right: isize = @intCast(isize, self.size) - 1;
        while (left <= right) {
            const mid = @divTrunc(right - left, 2) + left;
            const mid_idx = @intCast(usize, mid);
            const m_id = self.ccb_data[mid_idx].id;
            if (m_id < target_id) {
                left = mid + 1;
            } else if (m_id == target_id) {
                const idx = @intCast(usize, mid);
                return &self.ccb_data[idx];
            } else {
                right = mid - 1;
            }
        }

        return null;
    }

    /// mark a coroutine with given id as Dead, update the alive num.
    /// if alive num < 1/3 * size then remove the dead corotine from ccb_data
    ///
    /// if ccb_data does not contain a ccb with given id,
    /// this function make no effects
    pub fn markDead(self: *Self, id: usize) !void {
        if (self.binarySearchCCB(id)) |target_ccb| {
            // set coroutine status
            target_ccb.status = .Dead;
            // update alive num
            self.alive -= 1;
            const limit = self.size / 3; // maybe overflow
            if (self.alive < limit) {
                try self.removeAllDead();
            }
        }
    }

    /// remove dead coroutine from ccb_data
    fn removeAllDead(self: *Self) !void {
        const limit = self.ccb_data.len / 4;
        const cur_id = self.cur_ccb.id;
        if (self.alive < limit) {
            try self.removeDeadWithAlloc();
        } else {
            self.removeDeadInPlace();
        }
        std.debug.assert(self.alive == self.size);
        // remap to waitlist
        try self.remapToWaitlist(cur_id);
    }

    /// remove dead coroutine and move alive coroutine to new space
    ///
    /// 1. alloc new space for alive coroutine (cap = alive * 1.5)
    /// 2. copy alive coroutine to new space uisng two pointer alg,
    ///    deinit dead coroutine
    /// 3. free old space and set ccb_data to new space
    /// 4. updata the size
    fn removeDeadWithAlloc(self: *Self) !void {
        const new_space_size = self.alive * 3 / 2; // maybe overflow
        const new_space = try self.allocator.alloc(CCB, new_space_size);
        // copy alive coroutine to new space uisng two pointer alg
        // and deinit dead coroutine
        var new_idx: usize = 0;
        for (self.ccb_data[0..self.size]) |ccb| {
            if (ccb.status == .Dead) {
                ccb.deinit(self.allocator);
            } else {
                new_space[new_idx] = ccb;
                new_idx += 1;
            }
        }
        // free old space and set ccb_data to new space
        self.allocator.free(self.ccb_data);
        self.ccb_data = new_space;
        // updata the size
        self.size = new_idx;
    }

    /// remove dead coroutine inplace using two pointer alg
    ///
    /// 1. remove dead coroutine using two poiner alg
    /// 2. deinit dead coroutine while doing 1
    /// 3. update the size
    fn removeDeadInPlace(self: *Self) void {
        var alive_idx: usize = 0;
        for (self.ccb_data[0..self.size]) |ccb| {
            if (ccb.status == .Dead) {
                ccb.deinit(self.allocator);
            } else {
                self.ccb_data[alive_idx] = ccb;
                alive_idx += 1;
            }
        }
        self.size = alive_idx;
    }

    fn ensureUnusedCapacity(self: *Self, unused_cap: usize) !void {
        if (self.ccb_data.len >= self.size + unused_cap) {
            return;
        }
        // record cur id for remapTowaitlist
        const cur_id = self.cur_ccb.id;
        // need to allocate new space
        const new_cap = self.ccb_data.len * 2;
        var new_ccb_space = try self.allocator.alloc(CCB, new_cap);
        std.mem.copy(CCB, new_ccb_space, self.ccb_data[0..self.size]);

        self.allocator.free(self.ccb_data);
        self.ccb_data = new_ccb_space;

        // now all ccb ptrs in waitlist is no longer valid
        // we need to add the new ccb ptrs to it
        try self.remapToWaitlist(cur_id);
    }

    /// when this function be called. we know that ccb_data is change
    /// that means:
    /// 1. cur_ptr may not be valid
    /// 2. ptr in waitlist may not be valid
    /// 
    /// so we need to remap the ptr to waitlist  and set cur_ptr and 
    /// we don't want cur ptr be added to queue
    /// 
    /// note that we cannot relay on self.cur_ccb because it may not be valid anymore
    fn remapToWaitlist(self: *Self, cur_id: usize) !void {
        self.waitlist.len = 0;
        for (0..self.size) |idx| {
            const ccb_ptr = &self.ccb_data[idx];
            if (ccb_ptr.id == cur_id) {
                self.cur_ccb = ccb_ptr;
                continue;
            }
            if (ccb_ptr.status == .Active) {
                try self.addToWaitlist(ccb_ptr);
            } 
        }
    }
};
