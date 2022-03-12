const std = @import("std");
const gl = @import("zgl");
const glfw = @import("glfw");
const nanovg = @import("nanovg");

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

    const ctx = nanovg.Context.createGl3(.{});
    defer ctx.deleteGl3();

    gl.clearColor(0, 0, 0, 1);

    var world = World{
        .allocator = allocator,
        .gravity = .{ 0, 1000 },
    };
    defer world.deinit();

    try world.addStatic(0, &[_]v.Vec2{
        .{ 100, 500 },
        .{ 400, 500 },
        .{ 500, 700 },
        .{ 200, 700 },
    });
    try world.addStatic(0, &[_]v.Vec2{
        .{ 1000, 800 },
        .{ 1000, 900 },
        .{ 400, 900 },
        .{ 400, 800 },
    });

    try world.addObject(.{ 400, 100 }, .{}, 0, &[_]v.Vec2{
        .{ 0, 0 },
        .{ 100, 0 },
        .{ 50, 90 },
    });

    try world.addObject(.{ 600, 100 }, .{}, 0, &[_]v.Vec2{
        .{ 0, 90 },
        .{ 50, 0 },
        .{ 100, 90 },
    });

    try world.addObject(.{ 700, 50 }, .{}, 30, &[_]v.Vec2{.{ 0, 0 }});

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
                .static => 0xaaaaaaff,
                .active => colors[i],
            });
        }

        try world.tick(1 / 60.0);

        ctx.endFrame();

        try win.swapBuffers();
        try glfw.pollEvents();
    }
}

fn drawCollider(ctx: *nanovg.Context, pos: v.Vec2, poly: World.Collider, color: u32) void {
    // TODO: radius

    ctx.beginPath();
    const v0 = poly.verts[0] + pos;
    ctx.moveTo(
        @floatCast(f32, v0[0]),
        @floatCast(f32, v0[1]),
    );
    for (poly.verts[1..]) |raw_vert| {
        const vert = raw_vert + pos;
        ctx.lineTo(
            @floatCast(f32, vert[0]),
            @floatCast(f32, vert[1]),
        );
    }
    ctx.closePath();
    var c = nanovg.Color.hex(color);
    ctx.strokeColor(c);
    ctx.stroke();
    c.a *= 0.5;
    ctx.fillColor(c);
    ctx.fill();

    ctx.beginPath();
    for (poly.verts) |raw_vert| {
        const vert = raw_vert + pos;
        ctx.circle(
            @floatCast(f32, vert[0]),
            @floatCast(f32, vert[1]),
            3,
        );
    }
    ctx.fillColor(c);
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
    const arrow0 = end + v.rotate(v.Vec2{ -1, 0.5 }, d);
    const arrow1 = end + v.rotate(v.Vec2{ -1, -0.5 }, d);

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
