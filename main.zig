const std = @import("std");
const gl = @import("zgl");
const glfw = @import("glfw");
const nanovg = @import("nanovg");

const v = @import("v.zig");
const Polygon = @import("Polygon.zig");
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

    const body_a = try world.add(.{
        .kind = .static,
        .shapes = try allocator.dupe(World.Shape, &.{
            World.Shape.initPoly(.{ 0, 0 }, &[_]v.Vec2{
                .{ 100, 500 },
                .{ 400, 500 },
                .{ 500, 700 },
                .{ 200, 700 },
            }),
            World.Shape.initPoly(.{ 0, 0 }, &[_]v.Vec2{
                .{ 1000, 800 },
                .{ 1000, 900 },
                .{ 400, 900 },
                .{ 400, 800 },
            }),
        }),
    });
    defer allocator.free(body_a.shapes);

    const body_b = try world.add(.{
        .shapes = try allocator.dupe(World.Shape, &.{
            World.Shape.initPoly(.{ 0, 0 }, &[_]v.Vec2{
                .{ 0, 0 },
                .{ 100, 0 },
                .{ 50, 90 },
            }),
        }),
    });
    defer allocator.free(body_b.shapes);
    body_b.teleport(.{ 400, 100 });

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

        for (body_a.shapes) |shape| {
            drawPoly(ctx, shape.shape.poly, 0xffff00ff);
        }
        for (body_b.shapes) |shape| {
            drawPoly(ctx, shape.shape.poly, 0x00ffffff);
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
        const vert = raw_vert + poly.offset;
        ctx.lineTo(
            @floatCast(f32, vert[0]),
            @floatCast(f32, vert[1]),
        );
    }
    ctx.closePath();
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
