const std = @import("std");
const nvg = @import("deps/nanovg/build.zig");
const glfw = @import("deps/mach-glfw/build.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("main", "main.zig");

    exe.addIncludePath("deps/nanovg/examples/include");
    nvg.add(b, exe);

    glfw.link(b, exe, .{});
    exe.addPackagePath("glfw", "deps/mach-glfw/src/main.zig");

    exe.addPackagePath("zgl", "deps/zgl/zgl.zig");
    exe.linkLibC();
    exe.linkSystemLibrary("epoxy");

    exe.addPackagePath("phyz", "src/phyz.zig");

    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
