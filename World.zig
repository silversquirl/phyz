const std = @import("std");

const gjk = @import("gjk.zig");
const v = @import("v.zig");

const World = @This();

comptime {
    @setFloatMode(.Optimized);
}

allocator: std.mem.Allocator,
gravity: v.Vec2 = .{ 0, 0 },
slop: f64 = 0.1, // Distance to which collision must be accurate

active: std.MultiArrayList(Object) = .{},
static: std.ArrayListUnmanaged(Collider.Packed) = .{},
vertices: std.ArrayListUnmanaged(v.Vec2) = .{},

/// Free all memory associated with the world
pub fn deinit(self: *World) void {
    self.active.deinit(self.allocator);
    self.static.deinit(self.allocator);
    self.vertices.deinit(self.allocator);
}

pub fn addObject(
    self: *World,
    pos: v.Vec2,
    phys: Object.PhysicalProperties,
    collider: Collider,
) !void {
    const coll = try self.addCollider(collider);
    errdefer self.vertices.items.len -= collider.verts.len;

    try self.active.append(self.allocator, .{
        .pos = pos,
        .phys = phys,
        .collider = coll,
    });
    errdefer @compileError("TODO");
}

pub fn addStatic(self: *World, collider: Collider) !void {
    const coll = try self.addCollider(collider);
    errdefer self.vertices.items.len -= collider.verts.len;

    try self.static.append(self.allocator, coll);
    errdefer @compileError("TODO");
}

fn addCollider(self: *World, coll: Collider) !Collider.Packed {
    std.debug.assert(coll.radius > 0); // TODO: Zero radii are not yet supported (GJK would return zero)
    const vert_start = self.vertices.items.len;
    try self.vertices.appendSlice(self.allocator, coll.verts);
    return Collider.Packed{
        .radius = coll.radius,
        .vert_start = @intCast(u32, vert_start),
        .num_verts = @intCast(u32, coll.verts.len),
    };
}

pub fn colliders(self: *const World) ColliderIterator {
    return .{
        .active = self.active.slice(),
        .static = self.static.items,
        .vertices = self.vertices.items,
    };
}
pub const ColliderIterator = struct {
    active: std.MultiArrayList(Object).Slice,
    static: []const Collider.Packed,
    vertices: []const v.Vec2,
    idx: u32 = 0,

    pub fn next(self: *ColliderIterator) ?ColliderInfo {
        if (self.idx < self.active.len) {
            const coll = self.active.items(.collider)[self.idx];
            const pos = self.active.items(.pos)[self.idx];
            self.idx += 1;
            return ColliderInfo{
                .kind = .active,
                .pos = pos,
                .collider = coll.reify(self.vertices),
            };
        } else if (self.idx < self.active.len + self.static.len) {
            const coll = self.static[self.idx - self.active.len];
            self.idx += 1;
            return ColliderInfo{
                .kind = .static,
                .pos = v.v(0),
                .collider = coll.reify(self.vertices),
            };
        } else {
            return null;
        }
    }
};
pub const ColliderInfo = struct {
    kind: enum { active, static },
    pos: v.Vec2,
    collider: Collider,
};

pub fn tick(self: World, dt: f64) !void {
    const active = self.active.slice();

    // Apply drag and gravity
    for (active.items(.vel)) |*vel| {
        vel.* =
            v.v(0.99) * vel.* +
            v.v(dt) * self.gravity;
    }

    // Init movement amounts for each object
    var movement = try self.allocator.alloc(f64, active.len);
    defer self.allocator.free(movement);
    std.mem.set(f64, movement, dt);

    // Init collision list
    var collisions = std.ArrayList(CollisionResult).init(self.allocator);
    defer collisions.deinit();

    var done = false;
    while (!done) {
        done = true;

        //// Compute collisions and movement
        // OPTIM: only iterate objects that haven't converged
        for (active.items(.pos)) |pos, i| {
            const info = CollisionInfo{
                .pos = pos,
                .collider = active.items(.collider)[i]
                    .reify(self.vertices.items),
            };

            const vel = active.items(.vel)[i];
            const move = v.v(movement[i]) * vel;

            var min_fac: f64 = 1;

            // TODO: Collide with active objects

            // Collide with static colliders
            // TODO: broad phase
            var collided = false;
            for (self.static.items) |collider| {
                const norm = collide(info, .{
                    .pos = .{ 0, 0 },
                    .collider = collider.reify(self.vertices.items),
                });

                // Account for radii
                const r = info.collider.radius + collider.radius;
                // This is highly reduced and simplified math that offsets the collided face outwards by
                // the combined radii, then finds the intersection of the movement vector with that line
                const k = (r * v.mag(norm) - v.mag2(norm)) / v.dot(norm, move);

                if (k >= 0) {
                    if (k < min_fac) {
                        min_fac = k;
                    }

                    if (k * v.mag2(move) <= self.slop * self.slop) {
                        collided = true;
                        try collisions.append(.{
                            .norm = norm,
                            .obj = @intCast(u32, i),
                        });
                    }
                }
            }

            // Advance movement if no collision
            if (!collided) {
                const move_fac = 0.95 * min_fac;
                const move_vec = move * v.v(move_fac);
                active.items(.pos)[i] += move_vec;
                movement[i] *= 1 - move_fac;
            }

            if (collided or movement[i] > self.slop) {
                done = false;
            }
        }

        //// Resolve collisions
        for (collisions.items) |coll| {
            const vel = &active.items(.vel)[coll.obj];
            // Project velocity onto collided face
            const axis = v.conj(coll.norm);
            const p = v.dot(axis, vel.*) / v.dot(axis, axis);
            // Apply projected velocity to body
            vel.* = axis * v.v(p);
        }
        collisions.clearRetainingCapacity();
    }
}
const CollisionResult = struct {
    norm: v.Vec2,
    obj: u32,
};

/// Check collision between two colliders. Does not account for radii.
fn collide(a: CollisionInfo, b: CollisionInfo) v.Vec2 {
    const S = struct {
        a: CollisionInfo,
        b: CollisionInfo,
        fn support(pair: @This(), d: v.Vec2) v.Vec2 {
            // Minkowski difference
            const as = pair.a.collider.support(d) + pair.a.pos;
            const bs = pair.b.collider.support(-d) + pair.b.pos;
            return as - bs;
        }
    };
    return gjk.minimumPoint(S{ .a = a, .b = b }, S.support);
}
const CollisionInfo = struct {
    pos: v.Vec2,
    collider: Collider,
};

pub const Object = struct {
    pos: v.Vec2,
    vel: v.Vec2 = v.v(0),
    phys: PhysicalProperties,
    collider: Collider.Packed,

    pub const PhysicalProperties = struct {
        mass: f64 = 1.0,
        friction: f64 = 0.0,
        bounce: f64 = 0.0,
    };

    pub const MovementTick = struct {
        step: v.Vec2,
        total: v.Vec2,
    };
};

pub const Collider = struct {
    radius: f64 = 0.01,
    verts: []const v.Vec2 = &.{},

    /// Returns the furthest vertex in direction d.
    /// Does not account for radius.
    fn support(self: Collider, d: v.Vec2) v.Vec2 {

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

    pub const Packed = struct {
        radius: f64,
        vert_start: u32,
        num_verts: u32,

        pub fn reify(self: Packed, verts: []const v.Vec2) Collider {
            return .{
                .radius = self.radius,
                .verts = verts[self.vert_start .. self.vert_start + self.num_verts],
            };
        }
    };
};
