const x86_64 = @import("x86_64/lib.zig");
const native_arch = @import("builtin").target.cpu.arch;

const Arch = @import("std").Target.Cpu.Arch;

pub const Context: type = switch (native_arch) {
    Arch.x86_64 => x86_64.Context,
    else => @compileError("unsupport arch " ++ @tagName(native_arch)),
};

pub extern fn switchCtx(cur :*Context,  next: *Context) callconv(.C) void;
pub extern fn switchToNext(next: *Context) callconv(.C) noreturn;
pub extern fn initCall(wapper_ptr: usize, type_safe_fn_addr: usize) callconv(.C) void;
