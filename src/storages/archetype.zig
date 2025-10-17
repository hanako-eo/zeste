const std = @import("std");
const Allocator = std.mem.Allocator;

const lib = @import("./../root.zig");
const utils = @import("./../utils.zig");

infos: []const lib.TypeInfo,

/// set of all hashes of all types with a size of 0.
tags: std.AutoHashMapUnmanaged(u64, void),
/// combine hashing with indexing in the component list.
component_indexes: std.AutoHashMapUnmanaged(u64, usize),
/// list of all components (the component type is deleted because it is
/// impossible to store a list of different types).
components: [*]lib.storages.ErasedComponentStorageUnmanaged,
/// list of all entities store inside the archetype.
entities: std.ArrayList(lib.Entity.Id),

const Self = @This();

pub fn init(infos: []const lib.TypeInfo, allocator: Allocator) !Self {
    var empty_type_len: u32 = 0;
    for (infos) |info| {
        if (info.layout.size == 0) empty_type_len += 1;
    }

    var tags = std.AutoHashMapUnmanaged(u64, void).empty;
    try tags.ensureTotalCapacity(allocator, empty_type_len);

    var component_indexes = std.AutoHashMapUnmanaged(u64, usize).empty;
    try component_indexes.ensureTotalCapacity(allocator, @as(u32, @intCast(infos.len)) - empty_type_len);

    var components = try allocator.alloc(lib.storages.ErasedComponentStorageUnmanaged, @as(u32, @intCast(infos.len)) - empty_type_len);
    for (infos, 0..) |id, i| {
        if (id.layout.size != 0) {
            component_indexes.putAssumeCapacity(id.hash, i);
            components[i] = .{ .info = id };
        } else {
            tags.putAssumeCapacity(id.hash, void{});
        }
    }

    return Self{
        .tags = tags,
        .component_indexes = component_indexes,
        .components = components.ptr,
        .entities = std.ArrayList(lib.Entity.Id).empty,
        .infos = infos,
    };
}

pub fn deinit(self: *Self, allocator: Allocator) void {
    for (0..self.component_indexes.size) |i| {
        self.components[i].deinit(allocator, self.entities.items.len);
    }
    self.component_indexes.deinit(allocator);
    self.entities.deinit(allocator);
    self.tags.deinit(allocator);
    self.* = undefined;
}

pub fn append_entity(self: *Self, allocator: Allocator, entity: lib.Entity) void {
    self.entities.append(allocator, entity);
    for (0..self.component_indexes.size) |i| {
        self.components[i].ensure_total_capacity(allocator, self.entities.items.len, self.entities.items.len - 1);
    }
}
