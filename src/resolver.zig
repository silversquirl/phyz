const std = @import("std");
const phyz = @import("phyz.zig");
const v = phyz.v;
const World = phyz.World;

pub const slide = struct {
    pub fn resolve(active: World.ObjectList, collisions: []const World.CollisionResult) void {
        for (collisions) |coll| {
            const vel = &active.items(.vel)[coll.obj];
            // Project velocity onto collided face
            const axis = v.conj(coll.norm);
            const p = v.dot(axis, vel.*) / v.dot(axis, axis);
            // Apply projected velocity to body
            vel.* = axis * v.v(p);
        }
    }
};

pub fn bounce(elastic: f64) Bounce {
    return .{ .elastic = elastic };
}
pub const Bounce = struct {
    elastic: f64,

    pub fn resolve(self: Bounce, active: World.ObjectList, collisions: []const World.CollisionResult) void {
        for (collisions) |coll| {
            const vel = &active.items(.vel)[coll.obj];
            // Mirror projected velocity around normal
            const mirror = v.v(2 * v.dot(vel.*, coll.norm) / v.mag2(coll.norm)) * coll.norm - vel.*;
            vel.* = -mirror * v.v(self.elastic);
        }
    }
};
