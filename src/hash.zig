const std = @import("std");

/// Compute an hash for a given type `T`
pub fn hash_type(comptime T: type) u64 {
    const type_name = @typeName(T);

    return std.hash_map.hashString(type_name);
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
    const type_info = if (@TypeOf(Ts) == type) @typeInfo(Ts) else @typeInfo(@TypeOf(Ts));
    const types: []const type = switch (type_info) {
        .@"struct" => |info| blk: {
            comptime var types: []const type = &.{};
            inline for (info.fields) |field| {
                types = types ++ if (info.is_tuple)
                    .{field.defaultValue() orelse field.type}
                else
                    .{field.type};
            }
            break :blk @as(?[]const type, types);
        },
        .array => @as(?[]const type, &Ts),
        .pointer => |p| if (p.size == .slice) @as(?[]const type, Ts) else null,
        else => null,
    } orelse @compileError("Expected struct, array or slice, found '" ++ @typeName(Ts) ++ "'");

    // hash all type and apply a XOR on its
    var hash: u64 = 0;
    inline for (types) |T| {
        hash ^= hash_type(T);
    }

    return hash;
}

const testing = std.testing;
test hash_type {
    try testing.expectEqual(std.hash_map.hashString("u8"), hash_type(u8));
    try testing.expectEqual(hash_type(u8), hash_type(u8));
    try testing.expect(hash_type(u7) != hash_type(u8));
}

test hash_compound {
    try testing.expectEqual(hash_type(u8) ^ hash_type(u7), hash_compound(.{ u8, u7 }));
    try testing.expectEqual(hash_type(u8) ^ hash_type(u7), hash_compound(struct { a: u8, b: u7 }));
    try testing.expectEqual(hash_type(u8) ^ hash_type(u7), hash_compound([_]type{ u8, u7 }));
    try testing.expectEqual(hash_type(u8) ^ hash_type(u7), hash_compound(@as([]const type, &.{ u8, u7 })));
}
