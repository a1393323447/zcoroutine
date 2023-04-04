const OsTag = @import("std").Target.Os.Tag;
const linux = @import("linux/context.zig");
const windows = @import("windows/context.zig");

const os = @import("builtin").target.os.tag;

pub const Context: type = switch (os) {
    OsTag.linux => linux.Context,
    OsTag.windows => windows.Context,
    else => @compileError("unsupport os " ++ @tagName(os)),
};