const std = @import("std");
const gl = @import("zgl");
const glfw = @import("glfw");
const nanovg = @import("nanovg");

const v = @import("v.zig");
const MinkowskiDifference = @import("minkowski.zig").MinkowskiDifference;
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
    defer {
        for (world.bodies.items) |body| {
            allocator.free(body.shapes);
        }
        world.deinit();
    }

    _ = try world.add(.{
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

    const body_b = try world.add(.{
        .shapes = try allocator.dupe(World.Shape, &.{
            World.Shape.initPoly(.{ 0, 0 }, &[_]v.Vec2{
                .{ 0, 0 },
                .{ 100, 0 },
                .{ 50, 90 },
            }),
        }),
    });
    body_b.teleport(.{ 400, 100 });

    const body_c = try world.add(.{
        .shapes = try allocator.dupe(World.Shape, &.{
            World.Shape.initPoly(.{ 0, 0 }, &[_]v.Vec2{
                .{ 0, 90 },
                .{ 50, 0 },
                .{ 100, 90 },
            }),
        }),
    });
    body_c.teleport(.{ 600, 100 });

    const body_d = try world.add(.{
        .shapes = try allocator.dupe(World.Shape, &.{
            World.Shape.initPoint(.{ 0, 0 }, 30),
        }),
    });
    body_d.teleport(.{ 700, 50 });

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
            0xffff00ff,
            0x00ffffff,
            0xff00ffff,
            0x00ff00ff,
            0xff0000ff,
        };
        for (world.bodies.items) |body, i| {
            for (body.shapes) |shape| {
                drawShape(ctx, shape, colors[i]);
            }
        }

        world.tick(1 / 60.0);

        ctx.endFrame();

        try win.swapBuffers();
        try glfw.pollEvents();
    }
}

const M = MinkowskiDifference(
    Polygon,
    Polygon.support,
    Polygon,
    Polygon.support,
);
fn drawMinkowski(ctx: *nanovg.Context, off: v.Vec2, m: M, color: u32) void {
    const c = nanovg.Color.hex(color);
    ctx.beginPath();
    ctx.circle(
        @floatCast(f32, off[0]),
        @floatCast(f32, off[1]),
        8,
    );
    ctx.strokeColor(c);
    ctx.stroke();

    ctx.beginPath();
    for (m.a.verts) |av| {
        for (m.b.verts) |bv| {
            const vert = (av + m.a.offset) - (bv + m.b.offset) + off;
            ctx.circle(
                @floatCast(f32, vert[0]),
                @floatCast(f32, vert[1]),
                4,
            );
        }
    }
    ctx.fillColor(c);
    ctx.fill();
}

fn drawShape(ctx: *nanovg.Context, shape: World.Shape, color: u32) void {
    switch (shape.shape) {
        .point => |p| if (shape.radius == 0) {
            drawPoint(ctx, p, color);
        } else {
            ctx.beginPath();
            ctx.circle(
                @floatCast(f32, p[0]),
                @floatCast(f32, p[1]),
                @floatCast(f32, shape.radius),
            );
            var c = nanovg.Color.hex(color);
            ctx.strokeColor(c);
            ctx.stroke();
            c.a *= 0.5;
            ctx.fillColor(c);
            ctx.fill();
        },
        .poly => |p| drawPoly(ctx, p, color),
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
    var c = nanovg.Color.hex(color);
    ctx.strokeColor(c);
    ctx.stroke();
    c.a *= 0.5;
    ctx.fillColor(c);
    ctx.fill();

    ctx.beginPath();
    for (poly.verts) |raw_vert| {
        const vert = raw_vert + poly.offset;
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
