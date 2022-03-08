//! Narrow-phase convex polygon collision
//! The implementations here are stupidly slow right now, will optimize later
//! when I can be bothered to actually read papers on this topic.

const std = @import("std");
const Vec2 = std.meta.Vector(2, f64);

verts: []const Vec2,

const Polygon = @This();

/// Vertices must be anti-clockwise.
/// Polygon must be convex.
pub fn init(verts: []const Vec2) Polygon {
    // Check anti-clockwise
    const ab = verts[0] - verts[1];
    const ac = verts[2] - verts[1];
    std.debug.assert(@reduce(.Add, Vec2{ ab[1], -ab[0] } * ac) > 0);

    return .{ .verts = verts };
}

/// Query distance, normal, and closest points between two polygons
pub fn queryPoint(self: Polygon, point: Vec2) QueryResult {
    var r = QueryResult{
        .distance = std.math.inf(f64),
        .normal = undefined,
        .a = undefined,
        .b = point,
    };

    // FIXME: O(n)
    for (self.verts) |v| {
        const normal = point - v;
        const sqdist = @reduce(.Add, normal * normal);
        if (sqdist < r.distance) {
            r.distance = sqdist;
            r.normal = normal;
            r.a = v;
        }
    }

    r.distance = @sqrt(r.distance);
    r.normal /= @splat(2, r.distance);

    // FIXME: O(n)
    var a = self.verts[self.verts.len - 1];
    for (self.verts) |b| {
        defer a = b;

        const ab = b - a;
        const normal = normalize(Vec2{ -ab[1], ab[0] });

        // Check distance
        const dist = @reduce(.Add, (point - a) * normal);
        if (@fabs(dist) >= r.distance) continue;

        // Check we're actually on the normal
        if (@reduce(.Add, (point - a) * ab) < 0) continue;
        if (@reduce(.Add, (point - b) * -ab) < 0) continue;

        r.distance = dist;
        r.normal = normal;
        r.a = point - @splat(2, dist) * normal;
    }

    return r;
}

/// Query distance, normal, and closest points between two polygons
pub fn queryPoly(self: Polygon, other: Polygon) QueryResult {
    const a = self.queryEdges(other);
    const b = other.queryEdges(self);
    const c = self.queryVerts(other);

    var r = QueryResult{
        .distance = a.distance,
        .normal = a.normal,
        .a = a.vert,
        .b = a.vert + @splat(2, a.distance) * a.normal,
    };
    if (c.distance < r.distance) {
        r = .{
            .distance = c.distance,
            .normal = c.normal,
            .a = c.vert,
            .b = c.vert + @splat(2, c.distance) * c.normal,
        };
    }
    if (b.distance < r.distance) {
        r = .{
            .distance = b.distance,
            .normal = -b.normal,
            .a = b.vert + @splat(2, b.distance) * b.normal,
            .b = b.vert,
        };
    }

    return r;
}
pub const QueryResult = struct {
    distance: f64, // Distance between the polygons
    normal: Vec2, // Normalized normal vector
    a: Vec2, // Close point on self
    b: Vec2, // Close point on other
};

// Query self's vertices against other's edges
fn queryEdges(self: Polygon, other: Polygon) SingleQueryResult {
    var result = SingleQueryResult{};
    // FIXME: O(n^2)
    var a = other.verts[other.verts.len - 1];
    for (other.verts) |b| {
        const ab = b - a;
        const normal = normalize(.{ -ab[1], ab[0] });
        for (self.verts) |v| {
            // Check distance
            const dist = @reduce(.Add, (v - a) * normal);
            if (@fabs(dist) >= result.distance) continue;

            // Check we're actually on the normal
            if (@reduce(.Add, (v - a) * ab) < 0) continue;
            if (@reduce(.Add, (v - b) * -ab) < 0) continue;

            result = .{
                .distance = @fabs(dist),
                // Flip sign because we want the normal from the vertex, not the edge
                .normal = if (dist < 0) normal else -normal,
                .vert = v,
            };
        }
        a = b;
    }
    return result;
}

// Query self's vertices against other's vertices
fn queryVerts(self: Polygon, other: Polygon) SingleQueryResult {
    var result = SingleQueryResult{};
    // FIXME: O(n^2)
    for (other.verts) |ov| {
        for (self.verts) |sv| {
            // Check distance
            const normal = ov - sv;
            const sqdist = @reduce(.Add, normal * normal);
            if (sqdist >= result.distance) continue;

            result = .{
                .distance = sqdist,
                .normal = normal,
                .vert = sv,
            };
        }
    }

    result.distance = @sqrt(result.distance);
    result.normal /= @splat(2, result.distance);
    return result;
}

const SingleQueryResult = struct {
    distance: f64 = std.math.inf(f64),
    normal: Vec2 = undefined,
    vert: Vec2 = undefined, // Closest vertex
};

fn normalize(v: Vec2) Vec2 {
    @setFloatMode(.Optimized);
    const mag_inv = 1 / @sqrt(@reduce(.Add, v * v));
    return v * @splat(2, mag_inv);
}
