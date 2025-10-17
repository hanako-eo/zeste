pub const hash = @import("./hash.zig");
pub const storages = @import("./storages.zig");

pub const Entity = @import("./entity.zig");
pub const TypeInfo = @import("./type_info.zig");
pub const World = @import("./world.zig");

test {
    _ = hash;
    _ = storages;

    _ = Entity;
    _ = TypeInfo;
    _ = World;
}
