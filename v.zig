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

/// (x, y) -> (-y, x)
pub inline fn conj(a: Vec2) Vec2 {
    return .{ -a[1], a[0] };
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

/// Rotate vector a by rotating the vector (1, 0) to vector b
pub inline fn rotate(a: Vec2, b: Vec2) Vec2 {
    // This is just a complex number multiply
    const p = a * Vec2{ b[0], b[0] };
    const q =
        Vec2{ a[1], a[0] } *
        Vec2{ b[1], b[1] } *
        Vec2{ -1, 1 };
    return p + q;
}

/// Compute approximate equality between vectors or floats
/// See here for more info: https://randomascii.wordpress.com/2012/02/25/comparing-floating-point-numbers-2012-edition/
pub inline fn close(a: anytype, b: anytype, ulp_threshold: u63) bool {
    switch (@TypeOf(a, b)) {
        f64 => {
            if (a == b) return true;
            if (std.math.signbit(a) != std.math.signbit(b)) return false;
            const ulps = @bitCast(i64, a) - @bitCast(i64, b);
            return ulps <= ulp_threshold and -ulps <= ulp_threshold;
        },

        Vec2 => {
            if (@reduce(.And, a == b)) return true;
            const signs =
                @bitCast(std.meta.Vector(2, u64), a) ^
                @bitCast(std.meta.Vector(2, u64), b);
            if (@reduce(.Or, signs) >> 63 != 0) {
                return false;
            }
            const ulps =
                @bitCast(std.meta.Vector(2, i64), a) -
                @bitCast(std.meta.Vector(2, i64), b);
            const thres_v = @splat(2, @as(i64, ulp_threshold));
            return @reduce(.And, ulps <= thres_v) and @reduce(.And, -ulps <= thres_v);
        },

        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(a, b)) ++ " for v.close"),
    }
}

test "close float" {
    const values = [_]f64{
        0.49999999999999988897769753748434595763683319091796875,
        0.499999999999999944488848768742172978818416595458984375,
        0.5,
        0.50000000000000011102230246251565404236316680908203125,
        0.5000000000000002220446049250313080847263336181640625,
    };
    try std.testing.expect(close(values[2], values[1], 1));
    try std.testing.expect(close(values[2], values[3], 1));

    try std.testing.expect(!close(values[2], values[0], 1));
    try std.testing.expect(!close(values[2], values[4], 1));

    try std.testing.expect(close(values[2], values[1], 2));
    try std.testing.expect(close(values[2], values[3], 2));

    try std.testing.expect(close(values[2], values[0], 2));
    try std.testing.expect(close(values[2], values[4], 2));
}

test "close vec" {
    const values = [_]f64{
        0.49999999999999988897769753748434595763683319091796875,
        0.499999999999999944488848768742172978818416595458984375,
        0.5,
        0.50000000000000011102230246251565404236316680908203125,
        0.5000000000000002220446049250313080847263336181640625,
    };
    const vecs = [_]Vec2{
        .{ values[0], values[0] },
        .{ values[0], values[1] },
        .{ values[1], values[1] },
        .{ values[1], values[2] },
        .{ values[2], values[2] },
        .{ values[2], values[3] },
        .{ values[3], values[3] },
        .{ values[3], values[4] },
        .{ values[4], values[4] },
    };

    try std.testing.expect(close(vecs[4], vecs[2], 1));
    try std.testing.expect(close(vecs[4], vecs[3], 1));
    try std.testing.expect(close(vecs[4], vecs[5], 1));
    try std.testing.expect(close(vecs[4], vecs[6], 1));

    try std.testing.expect(!close(vecs[4], vecs[0], 1));
    try std.testing.expect(!close(vecs[4], vecs[1], 1));
    try std.testing.expect(!close(vecs[4], vecs[7], 1));
    try std.testing.expect(!close(vecs[4], vecs[8], 1));

    try std.testing.expect(close(vecs[4], vecs[2], 2));
    try std.testing.expect(close(vecs[4], vecs[3], 2));
    try std.testing.expect(close(vecs[4], vecs[5], 2));
    try std.testing.expect(close(vecs[4], vecs[6], 2));

    try std.testing.expect(close(vecs[4], vecs[0], 2));
    try std.testing.expect(close(vecs[4], vecs[1], 2));
    try std.testing.expect(close(vecs[4], vecs[7], 2));
    try std.testing.expect(close(vecs[4], vecs[8], 2));
}
