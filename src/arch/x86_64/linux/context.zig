// https://gitlab.com/x86-psABIs/x86-64-ABI/-/jobs/artifacts/master/raw/x86-64-ABI/abi.pdf?job=build
// Figure 3.4: Register Usage
pub const Context = extern struct {
    rbx: usize = 0, // 0
    r12: usize = 0, // 8
    r13: usize = 0, // 16
    r14: usize = 0, // 24
    r15: usize = 0, // 32
    rsp: usize = 0, // 40
    rbp: usize = 0, // 48
    rip: usize = 0, // 56

    const Self = @This();

    pub inline fn setStack(self: *Self, sp: usize) void {
        self.rsp = sp;
    }
};
