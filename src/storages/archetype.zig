const std = @import("std");
const Allocator = std.mem.Allocator;

const lib = @import("./../root.zig");
const utils = @import("./../utils.zig");

hash: u64,
infos: []const lib.TypeInfo,

/// set of all hashes of all types with a size of 0.
tags: std.AutoHashMapUnmanaged(u64, void),
/// combine hashing with indexing in the component list.
component_indexes: std.AutoHashMapUnmanaged(u64, usize),
/// list of all components (the component type is deleted because it is
/// impossible to store a list of different types).
components: [*]lib.storages.ErasedComponentStorageUnmanaged,
/// lenght of all entities store inside the archetype.
len: usize = 0,

const Self = @This();

pub fn init(infos: []const lib.TypeInfo, world: *lib.World) !Self {
    var empty_type_len: u32 = 0;
    for (infos) |info| {
        if (info.layout.size == 0) empty_type_len += 1;
    }

    var tags = std.AutoHashMapUnmanaged(u64, void).empty;
    try tags.ensureTotalCapacity(world.allocator, empty_type_len);

    var component_indexes = std.AutoHashMapUnmanaged(u64, usize).empty;
    try component_indexes.ensureTotalCapacity(world.allocator, @as(u32, @intCast(infos.len)) - empty_type_len);

    var components = try world.allocator.alloc(lib.storages.ErasedComponentStorageUnmanaged, @as(u32, @intCast(infos.len)) - empty_type_len);
    for (infos, 0..) |id, i| {
        if (id.layout.size != 0) {
            component_indexes.putAssumeCapacity(id.hash, i);
            components[i] = .{ .info = id };
        } else {
            tags.putAssumeCapacity(id.hash, void{});
        }
    }

    return Self{
        .hash = lib.hash.hash_compound_info(infos),
        .tags = tags,
        .component_indexes = component_indexes,
        .components = components.ptr,
    };
}
