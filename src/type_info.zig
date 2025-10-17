const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const lib = @import("./root.zig");
const utils = @import("./utils.zig");

const Self = @This();

pub const Id = u64;
pub const Layout = struct {
    size: usize,
    alignment: Alignment,

    pub inline fn size_rounded_up_to_align(self: Layout) usize {
        return self.size % self.alignment.toByteUnits();
    }

    pub inline fn pad_to_align(self: Layout) Layout {
        return Layout{
            .size = self.size + self.size_rounded_up_to_align(),
            .alignment = self.alignment,
        };
    }

    pub inline fn repeat_exact(self: Layout, n: usize) Layout {
        return Layout{
            .size = self.size * n,
            .alignment = self.alignment,
        };
    }

    pub inline fn repeat(self: Layout, n: usize) Layout {
        return self.pad_to_align().repeat_exact(n);
    }
};
pub const Hook = struct {
    dtor: *const fn (context: *anyopaque, allocator: Allocator) void = Default.dtor,
    copy: *const fn (dest: *anyopaque, src: *const anyopaque, len: usize, allocator: Allocator) void = Default.copy,

    const Default = struct {
        fn dtor(_: *anyopaque, _: Allocator) void {}
        fn copy(dest: *anyopaque, src: *const anyopaque, len: usize, _: Allocator) void {
            @memcpy(@as([*]u8, @ptrCast(dest))[0..len], @as([*]const u8, @ptrCast(src))[0..len]);
        }
    };
    pub const default = Hook{
        .dtor = Default.dtor,
        .copy = Default.copy,
    };
};

hash: Id,
layout: Layout,
hook: *const Hook,

pub fn of(comptime T: type, world: ?*const lib.World) Self {
    return Self{
        .hash = lib.hash.hash_type(T),
        .layout = .{ .size = @sizeOf(T), .alignment = Alignment.of(T) },
        .hook = hook_of(T, world),
    };
}

pub inline fn hook_of(comptime T: type, world: ?*const lib.World) *const Hook {
    return (if (world) |w| w.get_hook(T) else null) orelse &lib.TypeInfo.Hook.default;
}
