const std = @import("std");
const Allocator = std.mem.Allocator;

const lib = @import("./root.zig");

const Self = @This();

allocator: Allocator,
hooks: std.AutoHashMapUnmanaged(u64, lib.TypeInfo.Hook),

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,
        .hooks = std.AutoHashMapUnmanaged(u64, lib.TypeInfo.Hook).empty,
    };
}

pub fn get_hook(self: Self, comptime T: type) *const lib.TypeInfo.Hook {
    return self.hooks.getPtr(lib.hash.hash_type(T)) orelse &lib.TypeInfo.Hook.default;
}

pub fn set_hook(self: *Self, comptime T: type, hook: lib.TypeInfo.Hook) void {
    self.hooks.put(self.allocator, lib.hash.hash_type(T), hook);
}
