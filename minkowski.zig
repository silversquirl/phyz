const std = @import("std");
const v = @import("v.zig");

pub fn MinkowskiDifference(comptime A: type, comptime B: type) type {
    return struct {
        a: A,
        b: B,

        const Self = @This();
        pub fn support(self: Self, d: v.Vec2) v.Vec2 {
            return self.a.support(d) - self.b.support(-d);
        }
    };
}
