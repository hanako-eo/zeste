const std = @import("std");

const utils = @import("./utils.zig");

/// Compute an hash for a given type `T`
pub fn hash_type(comptime T: type) u64 {
    const type_name = @typeName(T);

    return std.hash.Wyhash.hash(0, type_name);
}

/// Compute an hash for a compount type, that is, a struct, an array or a slice of types
///
/// # Example
///
/// ```zig
/// const hash = hash_compound(.{ usize, []const u8 });
/// // or
/// const hash = hash_compound(struct { id: usize, name: []const u8 });
/// // or
/// const hash = hash_compound([_]type{ usize, name });
/// ```
pub fn hash_compound(comptime Ts: anytype) u64 {
    // hash all type and apply a mix on its
    comptime var hash: u64 = 0;
    inline for (utils.types(Ts)) |T| {
        hash = comptime mix2(hash, hash_type(T));
    }

    return hash;
}

inline fn mix2(a: u64, b: u64) u64 {
    const x = @as(u128, a) *% b;
    return @as(u64, @truncate(x)) ^ @as(u64, @truncate(x >> 64));
}

const testing = std.testing;
test hash_type {
    try testing.expectEqual(std.hash_map.hashString("u8"), hash_type(u8));
    try testing.expectEqual(hash_type(u8), hash_type(u8));
    try testing.expect(hash_type(u7) != hash_type(u8));
}

test hash_compound {
    const mix = struct {
        inline fn call(args: anytype) u64 {
            var hash: u64 = 0;
            inline for (std.meta.fields(@TypeOf(args))) |field| {
                hash = mix2(hash, @field(args, field.name));
            }
            return hash;
        }
    }.call;

    try testing.expectEqual(mix(.{ hash_type(u8), hash_type(u7) }), hash_compound(.{ u8, u7 }));
    try testing.expectEqual(mix(.{ hash_type(u8), hash_type(u7) }), hash_compound(struct { a: u8, b: u7 }));
    try testing.expectEqual(mix(.{ hash_type(u8), hash_type(u7) }), hash_compound(struct { u8, u7 }));
    try testing.expectEqual(mix(.{ hash_type(u8), hash_type(u7) }), hash_compound([_]type{ u8, u7 }));
    try testing.expectEqual(mix(.{ hash_type(u8), hash_type(u7) }), hash_compound(@as([]const type, &.{ u8, u7 })));
    try testing.expectEqual(hash_compound(.{ u8, u7 }), hash_compound(.{ u7, u8 }));
}
