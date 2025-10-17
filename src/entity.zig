const lib = @import("./root.zig");

const Self = @This();
pub const Id = u64;

id: Id,
archetype: *lib.storages.ArchetypeStorage,
world: *lib.World,

pub fn init(id: usize, archetype: *lib.storages.ArchetypeStorage, world: *lib.World) Self {
    return Self{
        .id = id,
        .archetype = archetype,
        .world = world,
    };
}
