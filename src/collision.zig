const std = @import("std");
const phyz = @import("phyz.zig");
pub const gjk = @import("collision/gjk.zig");
const v = phyz.v;

pub fn closestPoint(origin: v.Vec2, offset: v.Vec2, coll: Collider) v.Vec2 {
    const vertex = gjk.minimumPoint(OffsetCollider{
        .pos = offset - origin,
        .collider = coll,
    });
    if (v.mag2(vertex) < coll.radius * coll.radius) {
        return origin;
    }
    // Adjust for radius
    const point = vertex + v.v(coll.radius) * v.normalize(-vertex);
    return origin + point;
}

pub const OffsetCollider = struct {
    pos: v.Vec2,
    collider: Collider,

    pub fn support(self: OffsetCollider, d: v.Vec2) v.Vec2 {
        return self.collider.support(d) + self.pos;
    }
};

pub const MinkowskiDifference = struct {
    a: OffsetCollider,
    b: OffsetCollider,

    pub fn support(self: MinkowskiDifference, d: v.Vec2) v.Vec2 {
        return self.a.support(d) - self.b.support(-d);
    }
};

pub const Collider = struct {
    radius: f64 = 0.01,
    verts: []const v.Vec2 = &.{},

    pub fn box(self: Collider) v.Box {
        var min = v.v(std.math.inf(f64));
        var max = -min;
        for (self.verts) |vert| {
            min = @minimum(min, vert);
            max = @maximum(max, vert);
        }

        // Expand by radius in every direction
        min -= v.v(self.radius);
        max += v.v(self.radius);

        std.debug.assert(@reduce(.And, min < max));

        return .{ .min = min, .max = max };
    }

    /// Returns the furthest vertex in direction d.
    /// Does not account for radius.
    pub fn support(self: Collider, d: v.Vec2) v.Vec2 {

        // Start by sampling a few points
        var supp = Support.init(self.verts, 0, d);
        _ = supp.improve(self.verts, self.verts.len / 4, d);
        _ = supp.improve(self.verts, self.verts.len / 2, d);
        _ = supp.improve(self.verts, 3 * self.verts.len / 4, d);

        // Improve the guess
        while (supp.climb(self.verts, d)) {}

        return self.verts[supp.idx];
    }

    const Support = struct {
        idx: usize,
        dot: f64,

        fn init(verts: []const v.Vec2, idx: usize, d: v.Vec2) Support {
            return .{
                .idx = idx,
                .dot = v.dot(d, verts[idx]),
            };
        }

        fn improve(supp: *Support, verts: []const v.Vec2, idx: usize, d: v.Vec2) bool {
            const new = Support.init(verts, idx, d);
            if (new.dot > supp.dot) {
                supp.* = new;
                return true;
            } else {
                return false;
            }
        }

        fn climb(supp: *Support, verts: []const v.Vec2, d: v.Vec2) bool {
            const li = if (supp.idx + 1 >= verts.len)
                0
            else
                supp.idx + 1;
            const ri = if (supp.idx == 0)
                verts.len - 1
            else
                supp.idx - 1;

            const l_good = supp.improve(verts, li, d);
            const r_good = supp.improve(verts, ri, d);
            return l_good or r_good;
        }
    };
};
