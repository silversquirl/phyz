const std = @import("std");
const gl = @import("zgl");
const glfw = @import("glfw");
const nanovg = @import("nanovg");

const actuator = @import("actuator.zig");
const resolver = @import("resolver.zig");
const v = @import("v.zig");
const World = @import("World.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try glfw.init(.{});
    defer glfw.terminate();

    const win = try glfw.Window.create(1280, 1024, "Physics", null, null, .{});
    defer win.destroy();
    try glfw.makeContextCurrent(win);

    win.setKeyCallback(keyCallback);

    const ctx = nanovg.Context.createGl3(.{});
    defer ctx.deleteGl3();

    gl.clearColor(0, 0, 0, 1);

    const rate = 1.0 / 1.0;
    var world = World{ .allocator = allocator, .tick_time = rate / 60.0 };
    defer world.deinit();

    var physics = actuator.composite(.{
        actuator.drag(0.55),
        actuator.gravity(.{ 0, 1000 }),
    });

    _ = try world.addStatic(.{ .verts = &[_]v.Vec2{
        .{ 100, 500 },
        .{ 400, 500 },
        .{ 500, 700 },
        .{ 200, 700 },
    } });
    _ = try world.addStatic(.{ .verts = &[_]v.Vec2{
        .{ 1000, 800 },
        .{ 1000, 900 },
        .{ 400, 900 },
        .{ 400, 800 },
    } });

    _ = try world.addObject(.{ 400, 100 }, .{ .verts = &[_]v.Vec2{
        .{ 0, 0 },
        .{ 100, 0 },
        .{ 50, 90 },
    } });

    _ = try world.addObject(.{ 500, 100 }, .{ .radius = 50, .verts = &[_]v.Vec2{
        .{ 0, 90 },
        .{ 50, 0 },
        .{ 100, 90 },
    } });

    _ = try world.addObject(.{ 730, 30 }, .{ .radius = 30, .verts = &[_]v.Vec2{.{ 0, 0 }} });

    const font = ctx.createFontMem("Aileron", @embedFile("deps/nanovg/examples/Aileron-Regular.otf"), false);

    var frame: usize = 0;
    while (!win.shouldClose()) {
        const size = try win.getSize();
        const fbsize = try win.getFramebufferSize();

        gl.viewport(0, 0, size.width, size.height);
        gl.clear(.{ .color = true });

        ctx.beginFrame(
            @intToFloat(f32, size.width),
            @intToFloat(f32, size.height),
            @intToFloat(f32, fbsize.width) /
                @intToFloat(f32, size.width),
        );

        {
            var buf: [128]u8 = undefined;
            ctx.fontFaceId(font);
            ctx.fontSize(24);
            _ = ctx.text(4, 24, try std.fmt.bufPrint(&buf, "{}", .{frame}));
            frame += 1;
        }

        {
            const colors = [_]u32{
                0x00ffffff,
                0xff00ffff,
                0x00ff00ff,
                0xff0000ff,
            };
            var it = world.colliders();
            var i: usize = 0;
            while (it.next()) |c| : (i = (i + 1) % colors.len) {
                drawCollider(ctx, c.pos, c.collider, switch (c.kind) {
                    .static => 0xeeff0066,
                    .active => colors[i],
                });
            }
        }

        {
            const slice = world.active.slice();
            for (slice.items(.pos)) |pos, i| {
                drawVector(ctx, pos, slice.items(.vel)[i], 0xffffff80);
            }
        }

        physics.apply(world);
        try world.tick(resolver.bounce(0.9));

        ctx.endFrame();

        try win.swapBuffers();
        try glfw.pollEvents();
    }
}

fn drawCollider(ctx: *nanovg.Context, pos: v.Vec2, c: World.Collider, color: u32) void {
    var clr = nanovg.Color.hex(color);
    ctx.strokeColor(clr);
    clr.a *= 0.5;
    ctx.fillColor(clr);

    ctx.beginPath();
    for (c.verts) |raw_vert, i| {
        const vprev = c.verts[if (i == 0) c.verts.len - 1 else i - 1];
        const vnext = c.verts[if (i + 1 == c.verts.len) 0 else i + 1];

        const out = v.conj(vprev - raw_vert);
        const out_next = v.conj(raw_vert - vnext);

        const a0 = std.math.atan2(
            f32,
            @floatCast(f32, out[1]),
            @floatCast(f32, out[0]),
        );
        var a1 = std.math.atan2(
            f32,
            @floatCast(f32, out_next[1]),
            @floatCast(f32, out_next[0]),
        );
        if (a1 == a0) a1 += std.math.tau;

        const vert = raw_vert + pos;
        ctx.arc(
            @floatCast(f32, vert[0]),
            @floatCast(f32, vert[1]),
            @floatCast(f32, c.radius),
            a0,
            a1,
            .cw,
        );
    }
    ctx.closePath();
    ctx.stroke();
    ctx.fill();

    ctx.beginPath();
    for (c.verts) |raw_vert| {
        const vert = raw_vert + pos;
        ctx.circle(
            @floatCast(f32, vert[0]),
            @floatCast(f32, vert[1]),
            3,
        );
    }
    ctx.fill();
}

fn drawPoint(ctx: *nanovg.Context, p: v.Vec2, color: u32) void {
    ctx.beginPath();
    ctx.circle(
        @floatCast(f32, p[0]),
        @floatCast(f32, p[1]),
        5,
    );
    ctx.fillColor(nanovg.Color.hex(color));
    ctx.fill();
}

fn drawVector(ctx: *nanovg.Context, start: v.Vec2, dir: v.Vec2, color: u32) void {
    const end = start + dir;
    const d = (end - start) * v.v(0.1);
    const arrow0 = end + v.rotate(.{ -1, 0.5 }, d);
    const arrow1 = end + v.rotate(.{ -1, -0.5 }, d);

    ctx.beginPath();
    ctx.moveTo(
        @floatCast(f32, start[0]),
        @floatCast(f32, start[1]),
    );
    ctx.lineTo(
        @floatCast(f32, end[0]),
        @floatCast(f32, end[1]),
    );
    ctx.lineTo(
        @floatCast(f32, arrow0[0]),
        @floatCast(f32, arrow0[1]),
    );
    ctx.moveTo(
        @floatCast(f32, end[0]),
        @floatCast(f32, end[1]),
    );
    ctx.lineTo(
        @floatCast(f32, arrow1[0]),
        @floatCast(f32, arrow1[1]),
    );
    ctx.strokeColor(nanovg.Color.hex(color));
    ctx.stroke();
}

fn keyCallback(win: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = win;
    _ = scancode;
    _ = mods;

    switch (key) {
        .u => switch (action) {
            .release => glfw.swapInterval(1) catch {},
            .press => glfw.swapInterval(0) catch {},
            .repeat => {},
        },
        else => {},
    }
}
