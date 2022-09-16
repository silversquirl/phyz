const std = @import("std");
const v = @import("v.zig");

// TODO: return normalized vector and magnitude, to allow determining normal even in the case of collisions

/// Returns the closest point to the origin.
pub fn minimumPoint(
    shape: anytype,
    comptime support: fn (@TypeOf(shape), d: v.Vec2) v.Vec2,
) v.Vec2 {
    var s_buf: [3]v.Vec2 = undefined;
    var s: []v.Vec2 = s_buf[0..1];
    s[0] = support(shape, .{ 1, 0 });
    var i: usize = 0;
    while (true) {
        if (@import("builtin").mode == .Debug) {
            i += 1;
            if (i > 1_000_000) {
                std.debug.panic("GJK failed to converge after 1 million iterations", .{});
            }
        }

        const normal = switch (s.len) {
            1 => -s[0],
            2 => blk: {
                const a = s[0];
                const ab = s[1] - a;
                break :blk v.tripleCross(ab, -a, ab);
            },
            else => return simplexMinimumPoint(s),
        };
        if (@reduce(.And, normal == v.v(0))) {
            return v.v(0);
        }
        const new_point = support(shape, normal);

        // std.debug.print("{d} {d} {d}\n", .{ new_point, s, normal });

        for (s) |sp| {
            if (v.close(sp, new_point, 1 << 48)) {
                return simplexMinimumPoint(s);
            }
        }

        s.len += 1;
        s[s.len - 1] = new_point;

        approachOrigin(&s);
    }
}

fn simplexMinimumPoint(s: []v.Vec2) v.Vec2 {
    switch (s.len) {
        0 => return v.v(0),
        1 => return s[0],
        2, 3 => { // Length 3 is used as a sentinel, but the value should be calculated along the AB line
            const a = s[0];
            const ab = s[1] - a;
            return a + ab * v.v(v.dot(ab, -a) / v.dot(ab, ab));
        },
        else => unreachable,
    }
}

/// Moves the simplex closer to the origin.
fn approachOrigin(s: *[]v.Vec2) void {
    switch (s.len) {
        2 => {
            const a = s.*[0];
            const b = s.*[1];
            const ab = b - a;
            if (v.dot(ab, -a) < 0) { // Voronoi A
                s.*.len = 1;
            } else if (v.dot(-ab, -b) < 0) { // Voronoi B
                s.*[0] = b;
                s.*.len = 1;
            } else { // Voronoi AB
                // No modification needed
            }
        },

        3 => {
            const a = s.*[0];
            const b = s.*[1];
            const c = s.*[2];

            const ab = b - a;
            const ac = c - a;
            const bc = c - b;

            // FIXME: this code is horrible; fix it

            // Check the last vertex first, to ensure we converge even with degenerate simplices
            if (v.dot(-ac, -c) < 0 and v.dot(-bc, -c) < 0) { // Voronoi C
                s.*[0] = c;
                s.*.len = 1;
            } else if (v.dot(-ab, -b) < 0 and v.dot(bc, -b) < 0) { // Voronoi B
                s.*[0] = b;
                s.*.len = 1;
            } else if (v.dot(ab, -a) < 0 and v.dot(ac, -a) < 0) { // Voronoi A
                s.*.len = 1;
            } else if (v.dot(v.tripleCross(ac, ab, ab), -a) >= 0 and // Voronoi AB
                v.dot(ab, -a) >= 0 and v.dot(-ab, -b) >= 0)
            {
                // If we've hit this case, we need to stop as we'll just infinite loop
                // We use length 3 as a sentinel value, so do nothing
            } else if (v.dot(v.tripleCross(-ab, bc, bc), -b) >= 0 and // Voronoi BC
                v.dot(bc, -b) >= 0 and v.dot(-bc, -c) >= 0)
            {
                s.*[0] = c;
                s.*.len = 2;
            } else if (v.dot(v.tripleCross(ab, ac, ac), -a) >= 0 and // Voronoi CA
                v.dot(ac, -a) >= 0 and v.dot(-ac, -c) >= 0)
            {
                s.*[1] = c;
                s.*.len = 2;
            } else { // Voronoi ABC (inside the triangle)
                s.*.len = 0;
            }
        },

        else => unreachable,
    }
}
