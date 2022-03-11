const std = @import("std");
const v = @import("v.zig");

offset: v.Vec2 = v.v(0),
verts: []const v.Vec2,

const Polygon = @This();

/// Vertices must be anti-clockwise.
/// Polygon must be convex.
pub fn init(offset: v.Vec2, verts: []const v.Vec2) Polygon {
    // Check anti-clockwise
    const ab = verts[0] - verts[1];
    const ac = verts[2] - verts[1];
    std.debug.assert(@reduce(.Add, v.Vec2{ ab[1], -ab[0] } * ac) > 0);

    return .{ .offset = offset, .verts = verts };
}

/// Returns the furthest vertex in direction d
pub fn support(self: Polygon, d: v.Vec2) v.Vec2 {
    // Start by sampling a few points
    var supp = Support.init(self, 0, d);
    _ = supp.improve(self, self.verts.len / 4, d);
    _ = supp.improve(self, self.verts.len / 2, d);
    _ = supp.improve(self, 3 * self.verts.len / 4, d);

    // Improve the guess
    while (supp.climb(self, d)) {}

    return self.verts[supp.idx] + self.offset;
}
const Support = struct {
    idx: usize,
    dot: f64,

    fn init(self: Polygon, idx: usize, d: v.Vec2) Support {
        return .{
            .idx = idx,
            .dot = v.dot(d, self.verts[idx]),
        };
    }

    fn improve(supp: *Support, self: Polygon, idx: usize, d: v.Vec2) bool {
        const new = Support.init(self, idx, d);
        if (new.dot > supp.dot) {
            supp.* = new;
            return true;
        } else {
            return false;
        }
    }

    fn climb(supp: *Support, self: Polygon, d: v.Vec2) bool {
        const li = if (supp.idx + 1 >= self.verts.len)
            0
        else
            supp.idx + 1;
        const ri = if (supp.idx == 0)
            self.verts.len - 1
        else
            supp.idx - 1;

        const l_good = supp.improve(self, li, d);
        const r_good = supp.improve(self, ri, d);
        return l_good or r_good;
    }
};
