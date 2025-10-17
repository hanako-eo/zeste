const std = @import("std");
const Allocator = std.mem.Allocator;

const lib = @import("./root.zig");
const utils = @import("./utils.zig");

const Self = @This();

next_entity_id: u32,

allocator: Allocator,
archetypes: std.AutoHashMapUnmanaged(lib.TypeInfo.Id, lib.storages.ArchetypeStorage),
hooks: std.AutoHashMapUnmanaged(lib.TypeInfo.Id, lib.TypeInfo.Hook),

pub fn init(allocator: Allocator) !Self {
    var archetypes = std.AutoHashMapUnmanaged(lib.TypeInfo.Id, lib.storages.ArchetypeStorage).empty;
    // creation of an archetype with no components
    try archetypes.put(allocator, 0, try lib.storages.ArchetypeStorage.init(&.{}, allocator));

    return Self{
        .next_entity_id = 0,

        .allocator = allocator,
        .archetypes = archetypes,
        .hooks = std.AutoHashMapUnmanaged(u64, lib.TypeInfo.Hook).empty,
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.archetypes.valueIterator();
    while (iter.next()) |archetype| {
        self.allocator.free(archetype.infos);
        archetype.deinit(self.allocator);
    }
    self.archetypes.deinit(self.allocator);
    self.hooks.deinit(self.allocator);

    self.* = undefined;
}

pub fn get_hook(self: Self, comptime T: type) ?*const lib.TypeInfo.Hook {
    return self.hooks.getPtr(lib.hash.hash_type(T));
}

pub fn set_hook(self: *Self, comptime T: type, hook: lib.TypeInfo.Hook) !void {
    return self.hooks.put(self.allocator, lib.hash.hash_type(T), hook);
}

pub fn create_entity(self: *Self, comptime Bundle: anytype) !lib.Entity {
    const archetype = try self.get_or_create_archetype(Bundle);

    const entity = lib.Entity.init(self.next_entity_id, archetype, self);
    archetype.append_entity(self.allocator, entity);
    self.next_entity_id += 1;

    return entity;
}

fn get_or_create_archetype(self: *Self, comptime Bundle: anytype) !*lib.storages.ArchetypeStorage {
    const component_types = utils.types(Bundle);
    const archetype_hash = lib.hash.hash_compound(component_types);

    const archetype = try self.archetypes.getOrPut(self.allocator, archetype_hash);
    if (!archetype.found_existing) {
        const infos = try self.allocator.alloc(lib.TypeInfo, component_types.len);
        inline for (0..component_types.len) |i| {
            infos[i] = lib.TypeInfo.of(component_types[i], self);
        }

        archetype.value_ptr.* = lib.storages.ArchetypeStorage.init(infos, self.allocator);
    }

    return archetype.value_ptr;
}
