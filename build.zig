const std = @import("std");
const LazyPath = std.Build.LazyPath;
const Arch = std.Target.Cpu.Arch;
const OsTag = std.Target.Os.Tag;

const native_os = @import("builtin").target.os.tag;
const native_arch = @import("builtin").target.cpu.arch;

var asm_file_str_buffer = std.mem.zeroes([100]u8);

fn target_asm(arch: Arch, os: OsTag) []const u8 {
    return std.fmt.bufPrint(&asm_file_str_buffer, "src/arch/{s}/{s}/core.S", .{
        @tagName(arch), @tagName(os)
    }) catch |err| std.debug.panic("[Error] Failed to generate asm file path!\nerr: {s}", .{
        @errorName(err)
    });
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    const target_asm_path = target_asm(target.cpu_arch orelse native_arch, target.os_tag orelse native_os);

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zcoroutine", .{
        .source_file = .{ .path = "src/core.zig" },
        .dependencies = &[_]std.Build.ModuleDependency{},
    });

    const lib = b.addStaticLibrary(.{
        .name = "zcoroutine",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.addAssemblyFile(LazyPath.relative(target_asm_path));
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zcoroutine",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addAssemblyFile(LazyPath.relative(target_asm_path));
    exe.strip = false;
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing.
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
