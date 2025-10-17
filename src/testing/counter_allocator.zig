const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

base_allocator: Allocator,
counters: struct {
    alloc: u32 = 0,
    resize: u32 = 0,
    remap: u32 = 0,
    free: u32 = 0,
},

pub fn init(base_allocator: Allocator) Self {
    return Self{
        .base_allocator = base_allocator,
        .counters = .{},
    };
}

fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const self: *Self = @ptrCast(@alignCast(context));
    self.counters.alloc += 1;
    return self.base_allocator.rawAlloc(len, alignment, ret_addr);
}

fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const self: *Self = @ptrCast(@alignCast(context));
    self.counters.resize += 1;
    return self.base_allocator.rawResize(memory, alignment, new_len, ret_addr);
}

fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const self: *Self = @ptrCast(@alignCast(context));
    self.counters.remap += 1;
    return self.base_allocator.rawRemap(memory, alignment, new_len, ret_addr);
}

fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    const self: *Self = @ptrCast(@alignCast(context));
    self.counters.free += 1;
    return self.base_allocator.rawFree(memory, alignment, ret_addr);
}

pub fn allocator(self: *Self) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}
