const std = @import("std");
const gl = @import("zgl");
const glfw = @import("glfw");
const nanovg = @import("nanovg");

const Polygon = @import("Polygon.zig");
const World = @import("World.zig");
const Vec2 = std.meta.Vector(2, f64);

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

    const body_a = World.Body{
        .kind = .static,
        .shapes = try allocator.dupe(World.Shape, &.{
            World.Shape.initPoly(&[_]Vec2{
                .{ 100, 500 },
                .{ 400, 500 },
                .{ 500, 700 },
                .{ 200, 700 },
            }),
            World.Shape.initPoly(&[_]Vec2{
                .{ 1000, 800 },
                .{ 1000, 900 },
                .{ 400, 900 },
                .{ 400, 800 },
            }),
        }),
    };
    try world.add(body_a);

    var body_b = World.Body{
        .shapes = try allocator.dupe(World.Shape, &.{
            World.Shape.initPoly(&[_]Vec2{
                .{ 200, 100 },
                .{ 300, 100 },
                .{ 250, 190 },
            }),
        }),
    };
    body_b.teleport(.{ 200, 0 });
    try world.add(body_b);

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

        // const mouse_i = try win.getCursorPos();
        // const mouse = Vec2{
        //     mouse_i.xpos,
        //     mouse_i.ypos,
        // };

        for (body_a.shapes) |shape| {
            drawPoly(ctx, shape.shape.poly, 0xffff00ff);
        }
        for (body_b.shapes) |shape| {
            drawPoly(ctx, shape.shape.poly, 0x00ffffff);
        }
        for (body_a.shapes) |sa| {
            for (body_b.shapes) |sb| {
                var q = sb.shape.poly.queryPoly(sa.shape.poly);
                drawQuery(ctx, q, 0xff0000ff);
            }
        }

        world.tick(1 / 60.0);

        ctx.endFrame();

        try win.swapBuffers();
        try glfw.pollEvents();
    }
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
