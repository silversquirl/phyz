const std = @import("std");
const v = @import("v.zig");

const SpatialHash = @This();

const max_bin_size = 128;

bin_size: f64 = 100.0,
map: std.ArrayHashMapUnmanaged(u32, std.ArrayListUnmanaged(u32), Context, false) = .{},

// OPTIM: rasterizing polygons may be faster than using a bounding box, as it results in less false positives during querying
pub fn add(self: *SpatialHash, allocator: std.mem.Allocator, box: v.Box, value: u32) !void {
    std.debug.assert(@reduce(.And, box.min < box.max));

    var resize = false;
    var it = BoxIterator.init(self.bin_size, box);
    while (it.next()) |hash| {
        const gop = try self.map.getOrPut(allocator, hash);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }

        if (std.mem.indexOfScalar(u32, gop.value_ptr.items, value) == null) {
            // FIXME: undo these insertions if an error occurs
            try gop.value_ptr.append(allocator, value);
            if (gop.value_ptr.items.len > max_bin_size) {
                resize = true;
            }
        }
    }

    if (resize) {
        // TODO: resize boxes
    }
}

pub fn remove(self: *SpatialHash, box: v.Box, value: u32) void {
    var it = BoxIterator.init(self.bin_size, box);
    while (it.next()) |hash| {
        if (self.map.get(hash)) |bin| {
            if (std.mem.indexOfScalar(u32, bin.items, value)) |idx| {
                bin.swapRemove(idx);
            }
        }
    }
}

/// May return duplicates
/// add and remove invalidate this iterator
pub fn get(self: *const SpatialHash, box: v.Box) Iterator {
    return .{
        .hash = self,
        .box = BoxIterator.init(self.bin_size, box),
    };
}

pub const Iterator = struct {
    hash: *const SpatialHash,
    box: BoxIterator,
    bin: []const u32 = &.{},

    pub fn next(self: *Iterator) ?u32 {
        while (self.bin.len == 0) {
            const hash = self.box.next() orelse {
                return null;
            };
            if (self.hash.map.get(hash)) |bin| {
                self.bin = bin.items;
            }
        }

        const result = self.bin[0];
        self.bin.len -= 1;
        self.bin.ptr += 1;

        return result;
    }
};

pub fn deinit(self: *SpatialHash, allocator: std.mem.Allocator) void {
    for (self.map.values()) |*bin| {
        bin.deinit(allocator);
    }
    self.map.deinit(allocator);
}

const BoxIterator = struct {
    minx: i64,
    max: [2]i64,
    pos: [2]i64,

    pub fn init(bin_size: f64, box: v.Box) BoxIterator {
        const qmin = @floor(box.min / v.v(bin_size));
        const qmax = @ceil(box.max / v.v(bin_size));

        const min = [2]i64{
            @floatToInt(i64, qmin[0]),
            @floatToInt(i64, qmin[1]),
        };
        const max = [2]i64{
            @floatToInt(i64, qmax[0]),
            @floatToInt(i64, qmax[1]),
        };

        return BoxIterator{
            .minx = min[0],
            .max = max,
            .pos = min,
        };
    }

    pub fn next(self: *BoxIterator) ?u32 {
        if (self.pos[1] >= self.max[1]) {
            return null;
        }

        const result = hashPos(self.pos);
        self.pos[0] += 1;

        if (self.pos[0] >= self.max[0]) {
            self.pos[0] = self.minx;
            self.pos[1] += 1;
        }

        return result;
    }

    fn hashPos(pos: [2]i64) u32 {
        return @truncate(u32, std.hash.Wyhash.hash(0, std.mem.asBytes(&pos)));
    }
};

const Context = struct {
    pub inline fn hash(_: Context, k: u32) u32 {
        return k;
    }
    pub inline fn eql(_: Context, a: u32, b: u32, _: usize) bool {
        return a == b;
    }
};
