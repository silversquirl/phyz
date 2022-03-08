// Stupid simple polygon rasterizer
const std = @import("std");
const qoi = @import("qoi");

const Vec2 = std.meta.Vector(2, f64);
const Polygon = @import("Polygon.zig");

fn rasterize(img: qoi.Image, poly: Polygon, color: [4]u8) void {
    const wscale = 2 / @intToFloat(f64, img.header.width);
    const hscale = 2 / @intToFloat(f64, img.header.height);

    var y: usize = 0;
    while (y < img.header.height) : (y += 1) {
        var x: usize = 0;
        while (x < img.header.width) : (x += 1) {
            const p = Vec2{
                @intToFloat(f64, x) * wscale - 1,
                1 - @intToFloat(f64, y) * hscale,
            };

            var a = poly.verts[poly.verts.len - 1];
            const fill = for (poly.verts) |b| {
                // If the dot product with the normal is positive, the point is outside the polygon
                const t = perpCw(b - a);
                if (@reduce(.Add, t * (p - a)) > 0) {
                    break false;
                }

                a = b;
            } else true;

            if (fill) {
                img.pixels[y * img.header.width + x] = color;
            }
        }
    }
}

fn point(img: qoi.Image, pos: Vec2, color: [4]u8) void {
    const wscale = @intToFloat(f64, img.header.width) / 2;
    const hscale = @intToFloat(f64, img.header.height) / 2;

    const cx = @floatToInt(i33, (pos[0] + 1) * wscale);
    const cy = @floatToInt(i33, (1 - pos[1]) * hscale);

    var o: i33 = -4;
    while (o <= 4) : (o += 1) {
        const x0 = std.math.cast(usize, cx) catch continue;
        const y0 = std.math.cast(usize, cy) catch continue;
        const x1 = std.math.cast(usize, cx + o) catch continue;
        const y1 = std.math.cast(usize, cy + o) catch continue;
        img.pixels[y0 * img.header.width + x1] = color;
        img.pixels[y1 * img.header.width + x0] = color;
    }
}

// Perpendicular vector in the clockwise direction
fn perpCw(v: Vec2) Vec2 {
    return Vec2{ v[1], -v[0] };
}

pub fn main() !void {
    const header = qoi.Header{
        .width = 1024,
        .height = 1024,
        .channels = .rgba,
        .colorspace = .linear,
    };
    const img = qoi.Image{
        .header = header,
        .pixels = try std.heap.page_allocator.alloc([4]u8, header.width * header.height),
    };
    defer std.heap.page_allocator.free(img.pixels);
    std.mem.set([4]u8, img.pixels, .{ 0, 0, 0, 255 });

    const poly_a = Polygon.init(&[_]Vec2{
        .{ -1, -1 },
        .{ 1, -1 },
        .{ -0.5, 0 },
    });
    // const poly_b = Polygon.init(&[_]Vec2{
    //     .{ -0.25, -0.25 },
    //     .{ 0, -0.5 },
    //     .{ 0.25, -0.25 },
    //     .{ 0.25, 0.25 },
    //     .{ 0, 0.5 },
    //     .{ -0.25, 0.25 },
    // });
    const poly_c = Polygon.init(&[_]Vec2{
        .{ -0.7, 0.1 },
        .{ -0.65, 0.25 },
        .{ -0.8, 0.2 },
    });

    rasterize(img, poly_a, .{ 255, 0, 0, 255 });
    // rasterize(img, poly_b, .{ 0, 255, 255, 255 });
    rasterize(img, poly_c, .{ 0, 255, 0, 255 });

    const q = poly_c.queryPoly(poly_a);
    std.debug.print("{}\n", .{q});
    point(img, q.a, .{ 0, 255, 255, 255 });
    point(img, q.b, .{ 255, 0, 255, 255 });
    const q2 = poly_a.queryPoint(.{ -1, 0 });
    point(img, q2.a, .{ 255, 255, 0, 255 });

    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    try qoi.write(bw.writer(), img.header, img.pixels);
    try bw.flush();
}
