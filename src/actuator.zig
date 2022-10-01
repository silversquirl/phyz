const std = @import("std");
const phyz = @import("phyz.zig");
const v = phyz.v;
const World = phyz.World;

pub fn gravity(vector: v.Vec2) Gravity {
    return .{ .vector = vector };
}
pub const Gravity = struct {
    vector: v.Vec2,

    pub fn apply(self: Gravity, world: World) void {
        const delta = v.v(world.tick_time) * self.vector;
        for (world.active.items(.vel)) |*vel| {
            vel.* += delta;
        }
    }
};

pub fn drag(factor: f64) Drag {
    return .{ .factor = factor };
}
pub const Drag = struct {
    factor: f64,
    _cache: struct {
        factor: f64 = std.math.nan(f64),
        tick_time: f64 = std.math.nan(f64),
        tick_factor: f64 = std.math.nan(f64),
    } = .{},

    pub fn apply(self: *Drag, world: World) void {
        if (self._cache.factor != self.factor or
            self._cache.tick_time != world.tick_time)
        {
            self._cache = .{
                .factor = self.factor,
                .tick_time = world.tick_time,
                .tick_factor = std.math.pow(f64, self.factor, world.tick_time),
            };
        }

        const fac = v.v(self._cache.tick_factor);
        for (world.active.items(.vel)) |*vel| {
            vel.* *= fac;
        }
    }
};

pub fn composite(actuators: anytype) Composite(@TypeOf(actuators)) {
    return .{ .actuators = actuators };
}
pub fn Composite(comptime Actuators: type) type {
    return struct {
        actuators: Actuators,

        pub fn apply(self: *@This(), world: World) void {
            inline for (comptime std.meta.fieldNames(Actuators)) |field| {
                @field(self.actuators, field).apply(world);
            }
        }
    };
}
