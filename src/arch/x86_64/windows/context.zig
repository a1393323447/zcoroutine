// https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention?view=msvc-170#callercallee-saved-registers
pub const Context = extern struct {
    rbx: usize = 0, // 0
    r12: usize = 0, // 8
    r13: usize = 0, // 16
    r14: usize = 0, // 24
    r15: usize = 0, // 32
    rdi: usize = 0, // 40
    rsi: usize = 0, // 48
    rsp: usize = 0, // 56
    rbp: usize = 0, // 64
    rip: usize = 0, // 72

    xmm6: f128 = 0, // 80
    xmm7: f128 = 0, // 96
    xmm8: f128 = 0, // 112
    xmm9: f128 = 0, // 128
    xmm10: f128 = 0, // 144
    xmm11: f128 = 0, // 160
    xmm12: f128 = 0, // 176
    xmm13: f128 = 0, // 192
    xmm14: f128 = 0, // 208
    xmm15: f128 = 0, // 224

    const Self = @This();

    pub inline fn setStack(self: *Self, sp: usize) void {
        self.rsp = sp;
    }
};
