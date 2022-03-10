//! Vector math
const std = @import("std");

comptime {
    @setFloatMode(.Optimized);
}

pub const Vec2 = std.meta.Vector(2, f64);

/// Turn a scalar into a vector
pub inline fn v(s: f64) Vec2 {
    return @splat(2, s);
}

/// Find the dot product of two vectors
pub inline fn dot(a: Vec2, b: Vec2) f64 {
    return @reduce(.Add, a * b);
}

/// Find 1/|a|
pub inline fn invMag(a: Vec2) f64 {
    return 1 / @sqrt(dot(a, a));
}

/// Normalize a vector
pub inline fn normalize(a: Vec2) Vec2 {
    return a * v(invMag(a));
}

/// Compute (a x b) x c
///
/// Useful for computing perpendicular vectors:
///  - ((a x b) x a) is perpendicular to a, pointing towards b
///  - ((b x a) x a) is perpendicular to a, pointing away from  b
pub inline fn tripleCross(a: Vec2, b: Vec2, c: Vec2) Vec2 {
    const k = a * @shuffle(f64, b, b, [2]i32{ 1, 0 });
    return .{
        c[1] * (k[1] - k[0]),
        c[0] * (k[0] - k[1]),
    };
}
