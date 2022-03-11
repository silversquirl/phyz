const std = @import("std");

const gjk = @import("gjk.zig");
const v = @import("v.zig");
const MinkowskiDifference = @import("minkowski.zig").MinkowskiDifference;
const Polygon = @import("Polygon.zig");

const World = @This();

allocator: std.mem.Allocator,
bodies: std.ArrayListUnmanaged(Body) = .{},
gravity: v.Vec2 = .{ 0, 0 },
slop: f64 = 0.1, // Distance to which collision must be accurate

pub const Body = struct {
    kind: Kind = .dynamic,
    mass: f64 = 1.0, // Mass for the entire body
    pos: v.Vec2 = v.Vec2{ 0, 0 }, // Current position
    vel: v.Vec2 = v.Vec2{ 0, 0 }, // Current velocity
    force: v.Vec2 = v.Vec2{ 0, 0 }, // Instantaneous force (reset to 0 every tick)

    shapes: []Shape,

    pub const Kind = enum {
        dynamic,
        kinematic,
        static,
    };

    pub fn teleport(self: *Body, pos: v.Vec2) void {
        const d = pos - self.pos;
        self.pos = pos;
        for (self.shapes) |*shape| {
            shape.move(d);
        }
    }

    /// Tick body physics
    fn tick(self: *Body, world: World, dt: f64) void {
        @setFloatMode(.Optimized);
        switch (self.kind) {
            .dynamic => {},
            .kinematic => return, // TODO
            .static => return,
        }

        self.vel =
            v.v(0.99) * self.vel +
            v.v(dt) * world.gravity +
            v.v(self.mass) * self.force;
        self.force = v.Vec2{ 0, 0 };

        const speed = @sqrt(@reduce(.Add, self.vel * self.vel));
        if (speed == 0) return;
        var direction = self.vel / v.v(speed);
        var distance = speed * dt;

        var i: usize = 0;
        move: while (distance > world.slop) {
            if (@import("builtin").mode == .Debug) {
                i += 1;
                if (i > 1_000_000) {
                    std.debug.panic("Body {*} failed to converge after 1 million iterations", .{self});
                }
            }

            var step = distance;
            // OPTIM: can skip re-testing non-critical shapes
            for (self.shapes) |*shape| {
                var q = world.moveQuery(shape, direction, step);
                if (q.distance <= world.slop) {
                    // TODO: friction, bounce

                    // Project velocity onto collided face
                    const axis = v.Vec2{ -q.normal[1], q.normal[0] };
                    const p = v.dot(axis, direction);
                    // Apply projected velocity to body
                    self.vel = axis * v.v(speed * p);
                    direction = if (p < 0) -axis else axis;
                    distance *= @fabs(p);

                    // Need to redo this step since everything's changed
                    continue :move;
                }

                std.debug.assert(q.distance <= step);
                step = q.distance * 0.99;
            }

            const step_v = direction * v.v(step);
            distance -= step;
            self.pos += step_v;
            // OPTIM: offset shapes by body position at query time instead?
            //        Less nice for third-party shape testing, so probably not worth.
            //        Also this is literally a few vector writes, so not exactly slow.
            for (self.shapes) |*shape| {
                shape.move(step_v);
            }
        }
    }
};

pub const Shape = struct {
    radius: f64 = 0.0,
    friction: f64 = 0.0,
    bounce: f64 = 0.0,

    shape: union(enum) {
        point: v.Vec2,
        poly: Polygon,
    },

    pub fn initPoint(p: v.Vec2, rad: f64) Shape {
        return .{ .radius = rad, .shape = .{ .point = p } };
    }
    pub fn initPoly(offset: v.Vec2, verts: []const v.Vec2) Shape {
        return .{ .shape = .{ .poly = Polygon.init(offset, verts) } };
    }

    /// Move the shape by a vector offset.
    pub fn move(self: *Shape, offset: v.Vec2) void {
        switch (self.shape) {
            .point => |*p| p.* += offset,
            .poly => |*p| p.offset += offset,
        }
    }

    pub fn support(self: Shape, d: v.Vec2) v.Vec2 {
        const p = switch (self.shape) {
            .point => |p| p,
            .poly => |p| p.support(d),
        };
        return p + v.normalize(d) * v.v(self.radius);
    }

    /// Get the vector distance between two shapes.
    pub fn query(a: Shape, b: Shape) v.Vec2 {
        const M = MinkowskiDifference(
            Shape,
            Shape.support,
            Shape,
            Shape.support,
        );
        return gjk.minimumPoint(M{ .a = b, .b = a }, M.support);
    }
};

pub fn deinit(self: *World) void {
    self.bodies.deinit(self.allocator);
}

pub fn add(self: *World, body: Body) !*Body {
    try self.bodies.append(self.allocator, body);
    return &self.bodies.items[self.bodies.items.len - 1];
}

pub fn tick(self: *World, dt: f64) void {
    for (self.bodies.items) |*body| {
        body.tick(self.*, dt);
    }
}

/// Query movement for a shape along a given vector.
/// Returns the safe movement distance, closest shape along the path (ish), and normal to that shape.
fn moveQuery(self: World, shape: *const Shape, direction: v.Vec2, distance: f64) MoveQuery {
    var result = MoveQuery{
        .distance = distance * distance,
        .shape = null,
        .normal = v.Vec2{ 0, 0 },
    };

    // TODO: broad phase
    for (self.bodies.items) |body| {
        for (body.shapes) |*target| {
            if (shape == target) continue;

            const vec = shape.query(target.*);
            if (v.dot(vec, vec) < result.distance and // Closer than previous
                v.dot(vec, direction) > std.math.epsilon(f64)) // Moving towards the collision
            {
                result = .{
                    .distance = v.dot(vec, vec),
                    .shape = target,
                    .normal = -vec,
                };
            }
        }
    }

    result.distance = @sqrt(result.distance);
    result.normal /= v.v(result.distance);
    return result;
}
const MoveQuery = struct {
    distance: f64,
    shape: ?*const Shape,
    normal: v.Vec2,
};
