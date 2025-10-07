fn type_compound_len(comptime Ts: anytype) comptime_int {
    const type_info = if (@TypeOf(Ts) == type) @typeInfo(Ts) else @typeInfo(@TypeOf(Ts));
    return switch (type_info) {
        .@"struct" => |info| info.fields.len,
        .array, .pointer => Ts.len,
        .type => 1,
        else => @compileError("Expected struct, array or slice, found '" ++ @typeName(Ts) ++ "'"),
    };
}

pub fn types(comptime Ts: anytype) [type_compound_len(Ts)]type {
    const type_info = if (@TypeOf(Ts) == type) @typeInfo(Ts) else @typeInfo(@TypeOf(Ts));
    switch (type_info) {
        .@"struct" => |info| {
            comptime var struct_types: [info.fields.len]type = undefined;
            inline for (info.fields, 0..) |field, i| {
                struct_types[i] = if (info.is_tuple)
                    field.defaultValue() orelse field.type
                else
                    field.type;
            }
            return struct_types;
        },
        .array => return Ts,
        .pointer => {
            return Ts[0..Ts.len].*;
        },
        .type => return .{Ts},
        else => @compileError("Expected struct, array or slice, found '" ++ @typeName(Ts) ++ "'"),
    }
}
