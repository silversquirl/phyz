const std = @import("std");
const v = @import("v.zig");

/// Returns the closest point to the origin.
pub fn minimumPoint(
    shape: anytype,
    comptime support: fn (@TypeOf(shape), d: v.Vec2) v.Vec2,
) v.Vec2 {
    var s_buf: [3]v.Vec2 = undefined;
    var s: []v.Vec2 = s_buf[0..1];
    s[0] = support(shape, .{ 1, 0 });
    var closest = s[0];
    while (true) {
        const new_point = support(shape, -closest);
        for (s) |sp| {
            if (@reduce(.And, sp == new_point)) {
                return closest;
            }
        }

        s.len += 1;
        s[s.len - 1] = new_point;

        closest = approachOrigin(&s);
        if (@reduce(.And, closest == v.v(0))) {
            return closest;
        }
    }
}

/// Moves the simplex closer to the origin.
/// Returns the closest point to the origin.
fn approachOrigin(s: *[]v.Vec2) v.Vec2 {
    switch (s.len) {
        2 => {
            const a = s.*[0];
            const b = s.*[1];
            const ab = b - a;
            if (v.dot(ab, -a) < 0) { // Voronoi A
                s.len = 1;
                return a;
            } else if (v.dot(-ab, -b) < 0) { // Voronoi B
                s.*[0] = b;
                s.len = 1;
                return b;
            } else { // Voronoi AB
                return a + ab * v.v(v.dot(ab, -a) / v.dot(ab, ab));
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

            if (v.dot(ab, -a) < 0 and v.dot(ac, -a) < 0) { // Voronoi A
                s.len = 1;
                return a;
            } else if (v.dot(-ab, -b) < 0 and v.dot(bc, -b) < 0) { // Voronoi B
                s.*[0] = b;
                s.len = 1;
                return b;
            } else if (v.dot(-ac, -c) < 0 and v.dot(-bc, -c) < 0) { // Voronoi C
                s.*[0] = c;
                s.len = 1;
                return c;
            } else if (v.dot(v.tripleCross(ac, ab, ab), -a) >= 0 and // Voronoi AB
                v.dot(ab, -a) >= 0 and v.dot(-ab, -b) >= 0)
            {
                s.len = 2;
                return a + ab * v.v(v.dot(ab, -a) / v.dot(ab, ab));
            } else if (v.dot(v.tripleCross(-ab, bc, bc), -b) >= 0 and // Voronoi BC
                v.dot(bc, -b) >= 0 and v.dot(-bc, -c) >= 0)
            {
                s.*[0] = c;
                s.len = 2;
                return b + bc * v.v(v.dot(bc, -b) / v.dot(bc, bc));
            } else if (v.dot(v.tripleCross(ab, ac, ac), -a) >= 0 and // Voronoi AC
                v.dot(ac, -a) >= 0 and v.dot(-ac, -c) >= 0)
            {
                s.*[1] = c;
                s.len = 2;
                return a + ac * v.v(v.dot(ac, -a) / v.dot(ac, ac));
            } else { // Voronoi ABC (inside the triangle)
                s.len = 0;
                return v.v(0);
            }
        },

        else => unreachable,
    }
}
