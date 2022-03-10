const std = @import("std");
const v = @import("v.zig");

pub fn MinkowskiDifference(
    comptime A: type,
    comptime supportA: fn (A, v.Vec2) v.Vec2,
    comptime B: type,
    comptime supportB: fn (A, v.Vec2) v.Vec2,
) type {
    return struct {
        a: A,
        b: B,

        const Self = @This();
        pub fn support(self: Self, d: v.Vec2) v.Vec2 {
            return supportA(self.a, d) - supportB(self.b, -d);
        }
    };
}
