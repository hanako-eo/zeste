const std = @import("std");
const Allocator = std.mem.Allocator;

const lib = @import("./../root.zig");

/// Represents the storage for a single type of component within a single type of entity.
pub fn ComponentStorageUnmanaged(comptime T: type) type {
    return struct {
        const Self = @This();

        items: [*]T = &.{},
        capacity: usize = 0,

        pub const empty: Self = .{};

        pub fn from_owned(slice: []T) Self {
            return Self{
                .items = slice.ptr,
                .capacity = slice.len,
            };
        }

        pub fn to_erased(self: *Self, world: ?*const lib.World) ErasedComponentStorageUnmanaged {
            const erased = ErasedComponentStorageUnmanaged{
                .ptr = @ptrCast(self.items),
                .capacity = self.capacity,
                .info = lib.TypeInfo.of(T, world),
            };
            self.* = empty;
            return erased;
        }

        /// Release all allocated memory.
        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.allocated_slice());
            self.* = undefined;
        }

        /// Extends the list by 1 element. Allocate more memory as necessary and
        /// place the new item at the end of the list (at the index of len).
        /// To repercute the new size of the list, you need to increment manually
        /// the lenght of the list after the call of apprend.
        pub fn append(self: *Self, allocator: Allocator, item: T, len: usize) Allocator.Error!void {
            const new_item_ptr = try self.add_one(allocator, len);
            new_item_ptr.* = item;
        }

        /// Increase length by 1, returning pointer to the new item.
        /// The returned pointer becomes invalid when the list resized.
        /// To repercute the new size of the list, you need to increment manually
        /// the lenght of the list after the call of apprend.
        pub fn add_one(self: *Self, allocator: Allocator, len: usize) Allocator.Error!*T {
            try self.ensure_total_capacity(allocator, len + 1, len);
            return self.add_one_assume_capacity(len);
        }

        /// Increase length by 1, returning pointer to the new item.
        /// Never invalidates element pointers.
        /// The returned element pointer becomes invalid when the list is resized.
        /// Asserts that the list can hold one additional item.
        /// To repercute the new size of the list, you need to increment manually
        /// the lenght of the list after the call of apprend.
        pub fn add_one_assume_capacity(self: *Self, len: usize) *T {
            std.debug.assert(len < self.capacity);

            return &self.items[len];
        }

        /// Remove and return the last element from the list.
        /// If the list is empty, returns `null`.
        /// Invalidates pointers to last element.
        /// To repercute the new size of the list, you need to decrement manually
        /// the lenght of the list after the call of apprend.
        pub fn pop(self: *Self, len: usize) ?T {
            if (len == 0) return null;
            const val = self.items[len - 1];
            return val;
        }

        /// Removes the element at the specified index and returns it.
        /// The empty slot is filled from the end of the list.
        /// Invalidates pointers to last element.
        /// This operation is O(1).
        /// Asserts that the list is not empty.
        /// Invalidates pointers to last element.
        /// Asserts that the index is in bounds.
        /// To repercute the new size of the list, you need to decrement manually
        /// the lenght of the list after the call of apprend.
        pub fn swap_remove(self: *Self, i: usize, len: usize) T {
            if (len - 1 == i) return self.pop(len).?;

            const old_item = self.items[i];
            self.items[i] = self.pop(len).?;
            return old_item;
        }

        /// If the current capacity is less than `new_capacity`, this function will
        /// modify the list so that it can hold at least `new_capacity` items.
        /// Invalidates element pointers if additional memory is needed.
        pub fn ensure_total_capacity(self: *Self, allocator: Allocator, new_capacity: usize, len: usize) Allocator.Error!void {
            if (@sizeOf(T) == 0) {
                self.capacity = std.math.maxInt(usize);
                return;
            }

            if (self.capacity >= new_capacity) return;

            const better_capacity = grow_capacity(@sizeOf(T), self.capacity, new_capacity);
            return self.ensure_total_capacity_precise(allocator, better_capacity, len);
        }

        /// If the current capacity is less than `new_capacity`, this function will
        /// modify the list so that it can hold exactly `new_capacity` items.
        /// Invalidates element pointers if additional memory is needed.
        fn ensure_total_capacity_precise(self: *Self, allocator: Allocator, new_capacity: usize, len: usize) Allocator.Error!void {
            // Here we avoid copying allocated but unused bytes by
            // attempting a resize in place, and falling back to allocating
            // a new buffer and doing our own copy. With a realloc() call,
            // the allocator implementation would pointlessly copy our
            // extra capacity.
            const old_memory = self.allocated_slice();
            if (allocator.remap(old_memory, new_capacity)) |new_memory| {
                self.items = new_memory.ptr;
                self.capacity = new_memory.len;
            } else {
                const new_memory = try allocator.alignedAlloc(T, null, new_capacity);
                @memcpy(new_memory[0..len], self.items);
                allocator.free(old_memory);
                self.items = new_memory.ptr;
                self.capacity = new_memory.len;
            }
        }

        /// Returns a slice of all the items plus the extra capacity, whose memory
        /// contents are `undefined`.
        pub fn allocated_slice(self: Self) []T {
            return self.items[0..self.capacity];
        }
    };
}

pub const ErasedComponentStorageUnmanaged = struct {
    const Self = @This();

    ptr: [*]u8 = &.{},
    capacity: usize = 0,
    info: lib.TypeInfo,

    pub fn from_owned(comptime T: type, slice: []T, world: ?*const lib.World) Self {
        return Self{
            .ptr = @ptrCast(slice.ptr),
            .capacity = slice.len,
            .info = lib.TypeInfo.of(T, world),
        };
    }

    pub fn from_erased_slice(slice: []u8, info: lib.TypeInfo) Self {
        const aligned_layout = info.layout.pad_to_align();

        return Self{
            .ptr = slice.ptr,
            .capacity = @divExact(slice.len, aligned_layout.size),
            .info = info,
        };
    }

    pub fn cast(self: Self, comptime Component: type) ComponentStorageUnmanaged(Component) {
        return ComponentStorageUnmanaged(Component){
            .items = @as([*]Component, @ptrCast(self.ptr)),
            .capacity = self.capacity,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator, len: usize) void {
        const aligned_layout = self.info.layout.pad_to_align();

        // destroy all element of the storage
        for (0..len) |i| {
            self.info.hook.dtor(@as(*anyopaque, @ptrCast(&self.ptr[i * aligned_layout.size])), allocator);
        }

        const memory = self.allocated_slice();
        if (memory.len != 0) {
            allocator.rawFree(
                memory,
                aligned_layout.alignment,
                @returnAddress(),
            );
        }
        self.* = undefined;
    }

    /// Remove and copy the last element from the list into the destination.
    /// If the list is empty, returns `null`.
    /// Invalidates pointers to last element.
    /// To repercute the new size of the list, you need to decrement manually
    /// the lenght of the list after the call of apprend.
    pub fn pop(self: *Self, dest: [*]u8, len: usize) bool {
        if (len == 0) return false;

        const aligned_layout = self.info.layout.pad_to_align();

        @memcpy(dest, self.ptr[(len - 1) * aligned_layout.size .. len * aligned_layout.size]);
        return true;
    }

    /// Removes the element at the specified index and pass it to the destination.
    /// The empty slot is filled from the end of the list.
    /// Invalidates pointers to last element.
    /// This operation is O(1).
    /// Asserts that the list is not empty.
    /// Asserts that the index is in bounds.
    /// To repercute the new size of the list, you need to decrement manually
    /// the lenght of the list after the call of apprend.
    pub fn swap_remove(self: *Self, dest: [*]u8, i: usize, len: usize) bool {
        if (len - 1 == i) return self.pop(dest, len);

        const aligned_layout = self.info.layout.pad_to_align();

        for (0..self.info.layout.size) |j| {
            dest[j] = self.ptr[i * aligned_layout.size + j];
            self.ptr[i * aligned_layout.size + j] = self.ptr[(len - 1) * aligned_layout.size + j];
        }
        return true;
    }

    /// If the current capacity is less than `new_capacity`, this function will
    /// modify the list so that it can hold at least `new_capacity` items.
    /// Invalidates element pointers if additional memory is needed.
    pub fn ensure_total_capacity(self: *Self, allocator: Allocator, new_capacity: usize, len: usize) Allocator.Error!void {
        if (self.info.layout.size == 0) {
            self.capacity = std.math.maxInt(usize);
            return;
        }

        if (self.capacity >= new_capacity) return;

        const better_capacity = grow_capacity(self.info.layout.size, self.capacity, new_capacity);
        return self.ensure_total_capacity_precise(allocator, better_capacity, len);
    }

    /// If the current capacity is less than `new_capacity`, this function will
    /// modify the list so that it can hold exactly `new_capacity` items.
    /// Invalidates element pointers if additional memory is needed.
    fn ensure_total_capacity_precise(self: *Self, allocator: Allocator, new_capacity: usize, len: usize) Allocator.Error!void {
        // Here we avoid copying allocated but unused bytes by
        // attempting a resize in place, and falling back to allocating
        // a new buffer and doing our own copy. With a realloc() call,
        // the allocator implementation would pointlessly copy our
        // extra capacity.
        const recalibrated_layout = self.info.layout.repeat(new_capacity);
        const old_memory = self.allocated_slice();

        if (old_memory.len == 0) {
            const new_memory = allocator.rawAlloc(recalibrated_layout.size, recalibrated_layout.alignment, @returnAddress()) orelse return error.OutOfMemory;

            self.ptr = new_memory;
            self.capacity = new_capacity;
            return;
        }

        if (allocator.rawRemap(old_memory, recalibrated_layout.alignment, recalibrated_layout.size, @returnAddress())) |new_memory| {
            self.ptr = new_memory;
            self.capacity = new_capacity;
        } else {
            const new_memory = allocator.rawAlloc(recalibrated_layout.size, recalibrated_layout.alignment, @returnAddress()) orelse return error.OutOfMemory;

            const array_layout = self.info.layout.repeat(len);
            @memcpy(new_memory[0..array_layout.size], self.ptr);
            allocator.rawFree(old_memory, recalibrated_layout.alignment, @returnAddress());

            self.ptr = new_memory;
            self.capacity = new_capacity;
        }
    }

    /// Returns a slice of all the items plus the extra capacity, whose memory
    /// contents are `undefined`.
    pub fn allocated_slice(self: Self) []u8 {
        const aligned_layout = self.info.layout.pad_to_align();
        return self.ptr[0..(self.capacity * aligned_layout.size)];
    }
};

/// Called when memory growth is necessary. Returns a capacity larger than
/// minimum that grows super-linearly.
inline fn grow_capacity(size: usize, current: usize, minimum: usize) usize {
    const init_capacity: usize = @max(1, std.atomic.cache_line / size);

    var new = current;
    while (true) {
        new +|= new / 2 + init_capacity;
        if (new >= minimum)
            return new;
    }
}

const CounterAllocator = @import("../testing/counter_allocator.zig");
const testing = std.testing;
test "ComponentStorageUnmanaged.allocation" {
    var component = ComponentStorageUnmanaged(u32).empty;
    defer component.deinit(testing.allocator);

    try component.ensure_total_capacity(testing.allocator, 1, 0);

    try testing.expectEqual(grow_capacity(@sizeOf(u32), 0, 1), component.capacity);
}

test "ComponentStorageUnmanaged.appends" {
    var gpa = CounterAllocator.init(testing.allocator);
    const allocator = gpa.allocator();

    var len: usize = 0;
    var component = ComponentStorageUnmanaged(u32).empty;
    defer component.deinit(allocator);

    try component.append(allocator, 0, len);
    len += 1;
    try component.append(allocator, 1, len);
    len += 1;

    try std.testing.expectEqual(1, gpa.counters.alloc);

    try std.testing.expectEqual(2, len);
    try std.testing.expectEqual(0, component.items[0]);
    try std.testing.expectEqual(1, component.items[1]);
}

test "ComponentStorageUnmanaged.pop" {
    var gpa = CounterAllocator.init(testing.allocator);
    const allocator = gpa.allocator();

    var len: usize = 0;
    var component = ComponentStorageUnmanaged(u32).empty;
    defer component.deinit(allocator);

    try component.append(allocator, 0, len);
    len += 1;
    try component.append(allocator, 1, len);
    len += 1;

    const popped_item = component.pop(len);
    len -= 1;

    try std.testing.expectEqual(1, gpa.counters.alloc);

    try std.testing.expectEqual(1, len);
    try std.testing.expectEqual(0, component.items[0]);
    try std.testing.expectEqual(1, popped_item);
}

test "ComponentStorageUnmanaged.swap_remove" {
    var gpa = CounterAllocator.init(testing.allocator);
    const allocator = gpa.allocator();

    var len: usize = 0;
    var component = ComponentStorageUnmanaged(u32).empty;
    defer component.deinit(allocator);

    try component.append(allocator, 0, len);
    len += 1;
    try component.append(allocator, 1, len);
    len += 1;
    try component.append(allocator, 2, len);
    len += 1;

    const popped_item = component.swap_remove(0, len);
    len -= 1;

    try std.testing.expectEqual(1, gpa.counters.alloc);

    try std.testing.expectEqual(2, len);
    try std.testing.expectEqual(2, component.items[0]);
    try std.testing.expectEqual(0, popped_item);
}

test "ErasedComponentStorageUnmanaged.deinit from ComponentStorageUnmanaged" {
    var gpa = CounterAllocator.init(testing.allocator);
    const allocator = gpa.allocator();

    var len: usize = 0;
    var component = ComponentStorageUnmanaged(u32).empty;

    try component.append(allocator, 0, len);
    len += 1;

    try std.testing.expectEqual(1, gpa.counters.alloc);

    var erased = component.to_erased(null);
    erased.deinit(allocator, len);

    try std.testing.expectEqual(1, gpa.counters.free);
}

test "ErasedComponentStorageUnmanaged.ensure_total_capacity" {
    var gpa = CounterAllocator.init(testing.allocator);
    const allocator = gpa.allocator();

    var component = ErasedComponentStorageUnmanaged.from_owned(u32, &.{}, null);

    try component.ensure_total_capacity(allocator, 1, 0);

    try testing.expectEqual(grow_capacity(@sizeOf(u32), 0, 1), component.capacity);
    try std.testing.expectEqual(1, gpa.counters.alloc);

    component.deinit(allocator, 0);
    try std.testing.expectEqual(1, gpa.counters.free);
}

test "ErasedComponentStorageUnmanaged.ensure_total_capacity correctly align" {
    var gpa = CounterAllocator.init(testing.allocator);
    const allocator = gpa.allocator();

    // u24 is stored inside a u32 and have the alignment of it
    var component = ErasedComponentStorageUnmanaged.from_owned(u24, &.{}, null);

    try component.ensure_total_capacity(allocator, 1, 0);

    try testing.expectEqual(grow_capacity(@sizeOf(u24), 0, 1), component.capacity);
    try testing.expectEqual(grow_capacity(@sizeOf(u24), 0, 1) * @alignOf(u24), component.allocated_slice().len);

    component.deinit(allocator, 0);
    try std.testing.expectEqual(1, gpa.counters.free);
}

test "ErasedComponentStorageUnmanaged.pop" {
    var len: usize = 0;
    var component = ComponentStorageUnmanaged(u32).empty;

    try component.append(testing.allocator, 42, len);
    len += 1;

    var erased = component.to_erased(null);
    defer erased.deinit(testing.allocator, len);

    var i: u32 = 0;
    try testing.expect(erased.pop(@ptrCast(&i), len));
    len -= 1;

    try testing.expectEqual(42, i);
}

test "ErasedComponentStorageUnmanaged.swap_remove" {
    var len: usize = 0;
    var component = ComponentStorageUnmanaged(u32).empty;

    try component.append(testing.allocator, 0, len);
    len += 1;
    try component.append(testing.allocator, 1, len);
    len += 1;

    var erased = component.to_erased(null);
    defer erased.deinit(testing.allocator, len);

    var i: u32 = 0;
    try testing.expect(erased.swap_remove(@ptrCast(&i), 0, len));
    len -= 1;

    try testing.expectEqual(0, i);
}

test "ComponentStorageUnmanaged.deinit and call destructor" {
    const T = struct {
        var counter: usize = 0;
        fn dtor(_: *anyopaque, _: Allocator) void {
            counter += 1;
        }
    };

    var world = try lib.World.init(testing.allocator);
    defer world.deinit();
    try world.set_hook(T, .{ .dtor = T.dtor });

    var len: usize = 0;
    var component = ComponentStorageUnmanaged(T).empty;
    defer component.deinit(testing.allocator);

    try component.append(testing.allocator, T{}, len);
    len += 1;
    try component.append(testing.allocator, T{}, len);
    len += 1;

    var erased = component.to_erased(&world);
    erased.deinit(testing.allocator, len);

    try std.testing.expectEqual(2, T.counter);
}
