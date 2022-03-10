const std = @import("std");
const gl = @import("zgl");
const glfw = @import("glfw");
const nanovg = @import("nanovg");

const gjk = @import("gjk.zig");
const MinkowskiDifference = @import("minkowski.zig").MinkowskiDifference;
const Polygon = @import("Polygon.zig");
const World = @import("World.zig");
const Vec2 = std.meta.Vector(2, f64);

const M = MinkowskiDifference(Polygon, Polygon);

pub fn main() !void {
    try glfw.init(.{});
    defer glfw.terminate();

    const win = try glfw.Window.create(1280, 1024, "Physics", null, null, .{});
    defer win.destroy();
    try glfw.makeContextCurrent(win);

    const ctx = nanovg.Context.createGl3(.{});
    defer ctx.deleteGl3();

    const poly = Polygon.init(.{ 300, 300 }, &[_]Vec2{
        .{ 160, 0 },
        .{ 200, 110 },
        .{ 100, 380 },
        .{ 0, 110 },
        .{ 40, 0 },
    });

    var poly2 = Polygon.init(.{ 0, 0 }, &[_]Vec2{
        .{ -50, -50 },
        .{ 50, -50 },
        .{ 50, 50 },
        .{ -50, 50 },
    });

    gl.clearColor(0, 0, 0, 1);
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

        const mouse_i = try win.getCursorPos();
        const mouse = Vec2{
            mouse_i.xpos,
            mouse_i.ypos,
        };
        _ = mouse;
        poly2.offset = mouse;

        drawPoly(ctx, poly, 0x00ffffff);
        drawPoly(ctx, poly2, 0xffff00ff);
        const m = M{ .a = poly, .b = poly2 };
        drawMinkowski(ctx, m, 0xff00ffaa);
        drawPoint(ctx, gjk.minimumPoint(m, M.support) + mouse, 0x00ff00ff);

        ctx.endFrame();

        try win.swapBuffers();
        try glfw.pollEvents();
    }
}

fn drawMinkowski(ctx: *nanovg.Context, m: M, color: u32) void {
    ctx.beginPath();
    for (m.a.verts) |av| {
        for (m.b.verts) |bv| {
            const v = (av + m.a.offset) - (bv + m.b.offset);
            ctx.circle(
                @floatCast(f32, v[0]),
                @floatCast(f32, v[1]),
                4,
            );
        }
    }
    ctx.fillColor(nanovg.Color.hex(color));
    ctx.fill();
}

fn drawPoly(ctx: *nanovg.Context, poly: Polygon, color: u32) void {
    ctx.beginPath();
    const v0 = poly.verts[0] + poly.offset;
    ctx.moveTo(
        @floatCast(f32, v0[0]),
        @floatCast(f32, v0[1]),
    );
    for (poly.verts[1..]) |raw_vert| {
        const v = raw_vert + poly.offset;
        ctx.lineTo(
            @floatCast(f32, v[0]),
            @floatCast(f32, v[1]),
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
        const v = raw_vert + poly.offset;
        ctx.circle(
            @floatCast(f32, v[0]),
            @floatCast(f32, v[1]),
            3,
        );
    }
    ctx.fillColor(c);
    ctx.fill();
}

fn drawPoint(ctx: *nanovg.Context, p: Vec2, color: u32) void {
    ctx.beginPath();
    ctx.circle(
        @floatCast(f32, p[0]),
        @floatCast(f32, p[1]),
        5,
    );
    ctx.fillColor(nanovg.Color.hex(color));
    ctx.fill();
}

fn drawQuery(ctx: *nanovg.Context, q: Polygon.QueryResult, color: u32) void {
    ctx.beginPath();
    ctx.circle(
        @floatCast(f32, q.a[0]),
        @floatCast(f32, q.a[1]),
        5,
    );
    ctx.circle(
        @floatCast(f32, q.b[0]),
        @floatCast(f32, q.b[1]),
        5,
    );
    ctx.fillColor(nanovg.Color.hex(color));
    ctx.fill();

    ctx.beginPath();
    ctx.moveTo(
        @floatCast(f32, q.a[0]),
        @floatCast(f32, q.a[1]),
    );
    ctx.lineTo(
        @floatCast(f32, q.b[0]),
        @floatCast(f32, q.b[1]),
    );
    ctx.strokeColor(nanovg.Color.hex(color));
    ctx.stroke();
}
