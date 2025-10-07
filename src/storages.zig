pub const ArchetypeStorage = @import("./storages/archetype.zig");
pub const ComponentStorageUnmanaged = @import("./storages/component.zig").ComponentStorageUnmanaged;
pub const ErasedComponentStorageUnmanaged = @import("./storages/component.zig").ErasedComponentStorageUnmanaged;

test {
    _ = ArchetypeStorage;
    _ = ComponentStorageUnmanaged;
    _ = ErasedComponentStorageUnmanaged;
}
