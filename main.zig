const std = @import("std");
const gl = @import("zgl");
const glfw = @import("glfw");
const nanovg = @import("nanovg");

const Polygon = @import("Polygon.zig");
const Vec2 = std.meta.Vector(2, f64);

pub fn main() !void {
    try glfw.init(.{});
    defer glfw.terminate();

    const win = try glfw.Window.create(1280, 1024, "Physics", null, null, .{});
    defer win.destroy();
    try glfw.makeContextCurrent(win);

    const ctx = nanovg.Context.createGl3(.{});
    defer ctx.deleteGl3();

    gl.clearColor(0, 0, 0, 1);

    const poly_a = Polygon.init(&[_]Vec2{
        .{ 100, 500 },
        .{ 400, 500 },
        .{ 500, 700 },
        .{ 200, 700 },
    });
    var poly_b_verts = [_]Vec2{
        .{ 200, 100 },
        .{ 300, 100 },
        .{ 250, 190 },
    };
    const poly_b = Polygon.init(&poly_b_verts);

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

        {
            drawPoly(ctx, poly_a, 0xffff00ff);
            const q = poly_a.queryPoint(mouse);
            drawQuery(ctx, q, 0xff00ffff);
        }
        {
            drawPoly(ctx, poly_b, 0x00ffffff);
            const q = poly_b.queryPoint(mouse);
            drawQuery(ctx, q, 0x00ff00ff);
        }
        {
            var q = poly_b.queryPoly(poly_a);
            drawQuery(ctx, q, 0xff0000ff);
        }

        {
            // Apply gravity
            // TODO: timescale
            const gravity = Vec2{ 0, 5 };
            const slop = 0.1;
            var remaining = gravity;
            while (true) {
                const sqmag = @reduce(.Add, remaining * remaining);
                if (sqmag <= 0) break;

                var move = remaining;

                const q = poly_b.queryPoly(poly_a);
                if (q.distance <= slop) {
                    break;
                }
                if (sqmag > q.distance * q.distance) {
                    move *= @splat(2, q.distance / @sqrt(sqmag));
                }
                remaining -= move;

                for (poly_b_verts) |*v| {
                    v.* += move;
                }
            }
        }

        ctx.endFrame();

        try win.swapBuffers();
        try glfw.pollEvents();
    }
}

fn drawPoly(ctx: *nanovg.Context, poly: Polygon, color: u32) void {
    ctx.beginPath();
    ctx.moveTo(
        @floatCast(f32, poly.verts[0][0]),
        @floatCast(f32, poly.verts[0][1]),
    );
    for (poly.verts[1..]) |v| {
        ctx.lineTo(
            @floatCast(f32, v[0]),
            @floatCast(f32, v[1]),
        );
    }
    ctx.closePath();
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
