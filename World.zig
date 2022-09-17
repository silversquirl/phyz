const std = @import("std");

const collision = @import("collision.zig");
const gjk = @import("gjk.zig");
const v = @import("v.zig");
const SpatialHash = @import("SpatialHash.zig");

const World = @This();

comptime {
    @setFloatMode(.Optimized);
}

allocator: std.mem.Allocator,
tick_time: f64 = 1.0 / 60.0, // Tick length in seconds
slop: f64 = 0.1, // Distance to which collision must be accurate

active: std.MultiArrayList(Object) = .{},
static: std.ArrayListUnmanaged(PackedCollider) = .{},
vertices: std.ArrayListUnmanaged(v.Vec2) = .{},

static_hash: SpatialHash = .{},

/// Free all memory associated with the world
pub fn deinit(self: *World) void {
    self.active.deinit(self.allocator);
    self.static.deinit(self.allocator);
    self.vertices.deinit(self.allocator);

    self.static_hash.deinit(self.allocator);
}

pub fn addObject(
    self: *World,
    pos: v.Vec2,
    collider: collision.Collider,
) !u32 {
    const coll = try self.addCollider(collider);
    errdefer self.vertices.items.len -= collider.verts.len;

    try self.active.append(self.allocator, .{
        .pos = pos,
        .collider = coll,
    });
    errdefer @compileError("TODO");

    return @intCast(u32, self.active.len) - 1;
}

pub fn addStatic(self: *World, collider: collision.Collider) !u32 {
    const coll = try self.addCollider(collider);
    errdefer self.vertices.items.len -= collider.verts.len;

    const id = @intCast(u32, self.static.items.len);
    try self.static.append(self.allocator, coll);
    errdefer _ = self.static.pop();

    try self.static_hash.add(self.allocator, coll.box, id);
    errdefer @compileError("TODO");

    return id;
}

fn addCollider(self: *World, coll: collision.Collider) !PackedCollider {
    std.debug.assert(coll.radius > 0); // TODO: Zero radii are not yet supported (GJK would return zero)
    const vert_start = self.vertices.items.len;
    try self.vertices.appendSlice(self.allocator, coll.verts);
    return .{
        .radius = coll.radius,
        .vert_start = @intCast(u32, vert_start),
        .num_verts = @intCast(u32, coll.verts.len),
        .box = coll.box(),
    };
}

pub fn colliders(self: World) ColliderIterator {
    return .{
        .active = self.active.slice(),
        .static = self.static.items,
        .vertices = self.vertices.items,
    };
}
pub const ColliderIterator = struct {
    active: ObjectList,
    static: []const PackedCollider,
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
    collider: collision.Collider,
};

pub fn closestStatic(self: World, pos: v.Vec2, max_distance: f64) ?SearchResult {
    return self.searchStatic(SearchClosest, pos, max_distance, {});
}
const SearchClosest = struct {
    pub const Context = void;

    /// Return closest point on collider
    pub fn findPoint(origin: v.Vec2, coll: collision.Collider, _: void) ?v.Vec2 {
        return collision.closestPoint(origin, coll);
    }

    pub const BinIterator = struct {
        center: [2]i64,
        radius: u63,
        context: void,
        index: u64 = 0,

        pub fn next(self: *BinIterator) ?[2]i64 {
            if (self.radius == 0) {
                if (self.index == 0) {
                    self.index += 1;
                    return self.center;
                } else {
                    return null;
                }
            }

            if (self.index >> 2 > self.radius * 2) {
                return null;
            }

            const idx = @intCast(u62, self.index >> 2);
            const quad = @truncate(u4, self.index);
            self.index += 1;

            var pos = [2]i64{
                self.radius,
                self.radius,
            };

            pos[quad & 1] -= idx;
            if (quad & 2 != 0) {
                pos[0] *= -1;
                pos[1] *= -1;
            }

            pos[0] += self.center[0];
            pos[1] += self.center[1];

            return pos;
        }
    };
};

pub fn searchStatic(
    self: World,
    comptime strategy: type,
    origin: v.Vec2,
    max_distance: f64,
    context: strategy.Context,
) ?SearchResult {
    if (self.static.items.len == 0) {
        return null;
    }

    // OPTIM: iterate all statics if there are only a few
    //        This may be significantly faster in some situations because the full alg is O(n) on distance

    const origin_bin = self.static_hash.posToBin(origin);

    var min_d: f64 = max_distance * max_distance;
    var min_p: ?SearchResult = null;

    var found_closer_bin = true;
    var radius: u63 = 0;
    while (found_closer_bin) : (radius += 1) {
        found_closer_bin = false;

        var it = strategy.BinIterator{
            .center = origin_bin,
            .radius = radius,
            .context = context,
        };

        while (it.next()) |bin_pos| {
            if (min_d <= self.static_hash.binBox(bin_pos).distanceSquared(origin)) {
                continue;
            } else {
                found_closer_bin = true;
            }

            if (self.static_hash.getBin(bin_pos)) |bin| {
                for (bin) |idx| {
                    const coll = self.static.items[idx];
                    if (min_d <= coll.box.distanceSquared(origin)) {
                        continue;
                    }

                    const point = strategy.findPoint(
                        origin,
                        coll.reify(self.vertices.items),
                        context,
                    ) orelse continue;

                    if (@reduce(.And, point == origin)) {
                        return .{
                            .idx = idx,
                            .point = origin,
                        };
                    }

                    const dist2 = v.mag2(point - origin);
                    if (min_d > dist2) {
                        min_d = dist2;
                        min_p = .{
                            .idx = idx,
                            .point = point,
                        };
                    }
                }
            }
        }
    }

    std.debug.assert(std.math.isFinite(min_d));
    return min_p;
}
pub const SearchResult = struct {
    idx: u32,
    point: v.Vec2,
};

pub fn tick(self: World, resolver: anytype) !void {
    const active = self.active.slice();

    // Init movement amounts for each object
    var movement = try self.allocator.alloc(f64, active.len);
    defer self.allocator.free(movement);
    std.mem.set(f64, movement, self.tick_time);

    // Init collision list
    var collisions = std.ArrayHashMap(
        CollisionResult,
        void,
        CollisionResult.Context,
        false,
    ).init(self.allocator);
    defer collisions.deinit();

    var done = false;
    while (!done) {
        done = true;

        //// Compute collisions and movement
        // OPTIM: only iterate objects that haven't converged
        for (active.items(.pos)) |pos, i| {
            const coll = active.items(.collider)[i];
            const info = collision.OffsetCollider{
                .pos = pos,
                .collider = coll.reify(self.vertices.items),
            };

            const vel = active.items(.vel)[i];
            const move = v.v(movement[i]) * vel;
            const box = coll.box.add(pos).expand(move);

            var min_fac: f64 = 1;

            // TODO: Collide with active objects

            // Collide with static colliders
            var it = self.static_hash.get(box);
            var collided = false;
            while (it.next()) |static_id| {
                const collider = self.static.items[static_id];
                if (!box.collides(collider.box)) {
                    continue;
                }

                const norm = gjk.minimumPoint(collision.MinkowskiDifference{
                    .a = info,
                    .b = .{
                        .pos = .{ 0, 0 },
                        .collider = collider.reify(self.vertices.items),
                    },
                });

                // Account for radii
                const r = info.collider.radius + collider.radius;
                // This is highly reduced and simplified math that offsets the collided face outwards by
                // the combined radii, then finds the intersection of the movement vector with that line
                const k = (r * v.mag(norm) - v.mag2(norm)) / v.dot(norm, move);

                if (k >= 0 and k <= 1) {
                    if (k < min_fac) {
                        min_fac = k;
                    }

                    if (k * v.mag2(move) <= self.slop * self.slop) {
                        collided = true;
                        try collisions.put(.{
                            .norm = norm,
                            .obj = @intCast(u32, i),
                            .static = @intCast(u32, static_id),
                        }, {});
                    }
                }
            }

            if (collided) {
                // We hit something; try again next step
                done = false;
            } else {
                // Advance movement
                const move_fac = 0.9999 * min_fac;
                const move_vec = move * v.v(move_fac);
                active.items(.pos)[i] += move_vec;
                movement[i] *= 1 - move_fac;

                if (movement[i] * v.mag2(vel) > self.slop * self.slop) {
                    // More movement to do
                    done = false;
                }
            }
        }

        //// Resolve collisions
        if (collisions.count() > 0) {
            std.debug.assert(!done);
            resolver.resolve(self, active, @as([]const CollisionResult, collisions.keys()));
            collisions.clearRetainingCapacity();
        }
    }
}
pub const CollisionResult = struct {
    norm: v.Vec2,
    obj: u32,
    static: u32,

    const Context = struct {
        pub fn eql(_: Context, a: CollisionResult, b: CollisionResult, _: usize) bool {
            return a.static == b.static;
        }
        pub fn hash(_: Context, r: CollisionResult) u32 {
            return @truncate(u32, std.hash.Wyhash.hash(0, std.mem.asBytes(&r.static)));
        }
    };
};

pub const Object = struct {
    pos: v.Vec2,
    vel: v.Vec2 = v.v(0),
    collider: PackedCollider,

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
pub const ObjectList = std.MultiArrayList(Object).Slice;

pub const PackedCollider = struct {
    radius: f64,
    vert_start: u32,
    num_verts: u32,
    box: v.Box,

    pub fn reify(self: PackedCollider, verts: []const v.Vec2) collision.Collider {
        return .{
            .radius = self.radius,
            .verts = verts[self.vert_start .. self.vert_start + self.num_verts],
        };
    }
};
