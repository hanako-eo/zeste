const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const lib = @import("./root.zig");

const Self = @This();

pub const Hook = struct {
    dtor: *const fn (context: *anyopaque, allocator: Allocator) void,
    copy: *const fn (dest: *anyopaque, src: *const anyopaque, len: usize, allocator: Allocator) void,

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

hash: u64,
layout: struct {
    size: usize,
    alignment: Alignment,
},
hook: *const Hook,

pub fn of(comptime T: type, world: *const lib.World) Self {
    return Self{
        .hash = lib.hash.hash_type(T),
        .layout = .{ .size = @sizeOf(T), .alignment = Alignment.of(T) },
        .hook = world.get_hook(T),
    };
}
