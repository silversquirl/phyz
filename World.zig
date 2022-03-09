const std = @import("std");
const Polygon = @import("Polygon.zig");
const Vec2 = std.meta.Vector(2, f64);

const World = @This();

allocator: std.mem.Allocator,
bodies: std.ArrayListUnmanaged(Body) = .{},
gravity: Vec2 = .{ 0, 0 },
slop: f64 = 0.1, // Distance to which collision must be accurate

pub const Body = struct {
    kind: Kind = .dynamic,
    mass: f64 = 1.0, // Mass for the entire body
    pos: Vec2 = Vec2{ 0, 0 }, // Current position
    vel: Vec2 = Vec2{ 0, 0 }, // Current velocity
    force: Vec2 = Vec2{ 0, 0 }, // Instantaneous force (reset to 0 every tick)

    shapes: []Shape,

    pub const Kind = enum {
        dynamic,
        kinematic,
        static,
    };

    pub fn teleport(self: *Body, pos: Vec2) void {
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
            v(0.99) * self.vel +
            v(dt) * world.gravity +
            v(self.mass) * self.force;
        self.force = Vec2{ 0, 0 };

        const speed = @sqrt(@reduce(.Add, self.vel * self.vel));
        if (speed == 0) return;
        var direction = self.vel / v(speed);
        var distance = speed * dt;

        move: while (distance > world.slop) {
            var step = distance;
            // OPTIM: can skip re-testing non-critical shapes
            for (self.shapes) |*shape| {
                var q = world.moveQuery(shape, direction, step);
                if (q.distance <= world.slop) {
                    // TODO: friction, bounce

                    // Project velocity onto collided face
                    const axis = Vec2{ -q.normal[1], q.normal[0] };
                    const p = @reduce(.Add, axis * direction);
                    // Apply projected velocity to body
                    self.vel = axis * v(speed * p);
                    direction = if (p < 0) -axis else axis;
                    distance *= @fabs(p);

                    // Need to redo this step since everything's changed
                    continue :move;
                }

                std.debug.assert(q.distance <= step);
                step = q.distance;
            }

            const step_v = direction * v(step);
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
        point: Vec2,
        poly: Polygon,
    },

    pub fn initPoint(p: Vec2) Shape {
        return .{ .shape = .{ .point = p } };
    }
    pub fn initPoly(verts: []const Vec2) Shape {
        return .{ .shape = .{ .poly = Polygon.init(verts) } };
    }

    /// Move the shape by a vector offset.
    pub fn move(self: *Shape, offset: Vec2) void {
        switch (self.shape) {
            .point => |*p| p.* += offset,
            .poly => |*p| p.offset += offset,
        }
    }

    /// Get the distance and normal between two shapes.
    pub fn query(a: Shape, b: Shape) Query {
        var q = a.rawQuery(b);
        q.distance -= a.radius + b.radius;
        return q;
    }

    /// Get the distance and normal between two shapes.
    /// Does not account for radius.
    fn rawQuery(a: Shape, b: Shape) Query {
        switch (a.shape) {
            .point => |ap| switch (b.shape) {
                .point => |bp| {
                    const ab = bp - ap;
                    const distance = @sqrt(@reduce(.Add, ab * ab));
                    return .{
                        .distance = distance,
                        .normal = ab / v(distance),
                    };
                },

                .poly => |bp| {
                    const q = bp.queryPoint(ap);
                    return .{
                        .distance = q.distance,
                        .normal = -q.normal,
                    };
                },
            },

            .poly => |ap| {
                const q = switch (b.shape) {
                    .point => |bp| ap.queryPoint(bp),
                    .poly => |bp| ap.queryPoly(bp),
                };
                return .{
                    .distance = q.distance,
                    .normal = q.normal,
                };
            },
        }
    }

    pub const Query = struct {
        distance: f64,
        normal: Vec2,
    };
};

pub fn add(self: *World, body: Body) !void {
    try self.bodies.append(self.allocator, body);
}

pub fn tick(self: *World, dt: f64) void {
    for (self.bodies.items) |*body| {
        body.tick(self.*, dt);
    }
}

/// Query movement for a shape along a given vector.
/// Returns the safe movement distance, closest shape along the path (ish), and normal to that shape.
fn moveQuery(self: World, shape: *const Shape, direction: Vec2, distance: f64) MoveQuery {
    var result = MoveQuery{
        .distance = distance,
        .shape = null,
        .normal = Vec2{ 0, 0 },
    };

    // TODO: broad phase
    for (self.bodies.items) |body| {
        for (body.shapes) |*target| {
            if (shape == target) continue;

            _ = direction;
            const q = shape.query(target.*);
            if (q.distance < result.distance and // Closer than previous
                // true)
                @reduce(.Add, direction * q.normal) > 0) // Moving towards the collision
            {
                result = .{
                    .distance = q.distance,
                    .shape = target,
                    .normal = q.normal,
                };
            }
        }
    }

    return result;
}
const MoveQuery = struct {
    distance: f64,
    shape: ?*const Shape,
    normal: Vec2,
};

fn v(x: f64) Vec2 {
    return @splat(2, x);
}
