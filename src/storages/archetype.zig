const std = @import("std");
const Allocator = std.mem.Allocator;

const lib = @import("./../root.zig");
const utils = @import("./../utils.zig");

hash: u64,

// hash -> erased_component
component_indexes: std.AutoHashMapUnmanaged(u64, usize),
components: [*]lib.storages.ErasedComponentStorageUnmanaged,

const Self = @This();

pub fn init(comptime Bundle: anytype, allocator: Allocator) !Self {
    // TODO: track all type with a size of 0 in the bundle to avoid array of empty type
    // FIXME: track all bundle with the same type several times like `.{ u8, u8 }`
    const Ts = utils.types(Bundle);
    var component_indexes = std.AutoHashMapUnmanaged(u64, usize).empty;
    component_indexes.ensureTotalCapacity(allocator, Ts.len);

    var components = try allocator.alloc(lib.storages.ErasedComponentStorageUnmanaged, Ts.len);
    inline for (Ts, 0..) |T, i| {
        component_indexes.putAssumeCapacity(lib.hash.hash_type(T), i);

        const component = lib.storages.ComponentStorageUnmanaged(T).empty;
        components[i] = component.to_erased();
    }

    return Self{
        .hash = lib.hash.hash_compound(Ts),
        .component_indexes = component_indexes,
        .components = components,
    };
}
