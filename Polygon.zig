const std = @import("std");
const v = @import("v.zig");

offset: v.Vec2 = .{ 0, 0 },
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
    var max_dot = -std.math.inf(f64);
    var max_v: v.Vec2 = undefined;
    // TODO: binary search
    for (self.verts) |vert| {
        const dot = v.dot(d, vert);
        if (dot > max_dot) {
            max_dot = dot;
            max_v = vert;
        }
    }
    return max_v + self.offset;
}
