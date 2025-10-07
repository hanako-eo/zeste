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
            return Self{ .items = slice.ptr, .capacity = slice.len };
        }

        pub fn to_erased(self: *Self) ErasedComponentStorageUnmanaged {
            const erased = ErasedComponentStorageUnmanaged{
                .ptr = self.items[0..self.capacity],
            };
            self.* = empty;
            return erased;
        }

        /// Release all allocated memory.
        pub fn deinit(self: Self, allocator: Allocator) void {
            if (self.capacity > 0 and @sizeOf(T) > 0) {
                allocator.free(self.allocated_slice());
            }
        }

        /// Extends the list by 1 element. Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn append(self: *Self, allocator: Allocator, item: T, len: *usize) Allocator.Error!void {
            const new_item_ptr = try self.add_one(allocator, len);
            new_item_ptr.* = item;
        }

        /// Increase length by 1, returning pointer to the new item.
        /// The returned pointer becomes invalid when the list resized.
        pub fn add_one(self: *Self, allocator: Allocator, len: *usize) Allocator.Error!*T {
            const newlen = len.* + 1;
            try self.ensure_total_capacity(allocator, newlen, len.*);
            return self.add_one_assume_capacity(len);
        }

        /// Increase length by 1, returning pointer to the new item.
        /// Never invalidates element pointers.
        /// The returned element pointer becomes invalid when the list is resized.
        /// Asserts that the list can hold one additional item.
        pub fn add_one_assume_capacity(self: *Self, len: *usize) *T {
            std.debug.assert(len.* < self.capacity);

            len.* += 1;
            return &self.items[len.* - 1];
        }

        /// Remove and return the last element from the list.
        /// If the list is empty, returns `null`.
        /// Invalidates pointers to last element.
        pub fn pop(self: *Self, len: *usize) ?T {
            if (len.* == 0) return null;
            const val = self.items[len.* - 1];
            len.* -= 1;
            return val;
        }

        /// Removes the element at the specified index and returns it.
        /// The empty slot is filled from the end of the list.
        /// Invalidates pointers to last element.
        /// This operation is O(1).
        /// Asserts that the list is not empty.
        /// Asserts that the index is in bounds.
        pub fn swap_remove(self: *Self, i: usize, len: *usize) T {
            if (len.* - 1 == i) return self.pop(len).?;

            const old_item = self.items[i];
            self.items[i] = self.pop(len).?;
            return old_item;
        }

        /// If the current capacity is less than `new_capacity`, this function will
        /// modify the array so that it can hold at least `new_capacity` items.
        /// Invalidates element pointers if additional memory is needed.
        pub fn ensure_total_capacity(self: *Self, allocator: Allocator, new_capacity: usize, len: usize) Allocator.Error!void {
            if (@sizeOf(T) == 0) {
                self.capacity = std.math.maxInt(usize);
                return;
            }

            if (self.capacity >= new_capacity) return;

            const better_capacity = grow_capacity(self.capacity, new_capacity);
            return self.ensure_total_capacity_precise(allocator, better_capacity, len);
        }

        /// If the current capacity is less than `new_capacity`, this function will
        /// modify the array so that it can hold exactly `new_capacity` items.
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

        const init_capacity: comptime_int = @max(1, std.atomic.cache_line / @sizeOf(T));

        /// Called when memory growth is necessary. Returns a capacity larger than
        /// minimum that grows super-linearly.
        fn grow_capacity(current: usize, minimum: usize) usize {
            var new = current;
            while (true) {
                new +|= new / 2 + init_capacity;
                if (new >= minimum)
                    return new;
            }
        }
    };
}

pub const ErasedComponentStorageUnmanaged = struct {
    const Self = @This();

    ptr: []anyopaque = &.{},

    pub fn cast(self: Self, comptime Component: type) ComponentStorageUnmanaged(Component) {
        return ComponentStorageUnmanaged(Component).from_owned(@ptrCast(self.ptr));
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.slice);
    }
};

const CounterAllocator = @import("../testing/counter_allocator.zig");
const testing = std.testing;
test "allocation" {
    var component = ComponentStorageUnmanaged(u32).empty;
    defer component.deinit(testing.allocator);
    const len = 0;

    try component.ensure_total_capacity(testing.allocator, 1, len);

    try testing.expectEqual(ComponentStorageUnmanaged(u32).grow_capacity(0, 1), component.capacity);
}

test "appends" {
    var gpa = CounterAllocator.init(testing.allocator);
    const allocator = gpa.allocator();

    var len: usize = 0;
    var component = ComponentStorageUnmanaged(u32).empty;
    defer component.deinit(allocator);

    try component.append(allocator, 0, &len);
    try component.append(allocator, 1, &len);

    try std.testing.expectEqual(1, gpa.counters.alloc);

    try std.testing.expectEqual(2, len);
    try std.testing.expectEqual(0, component.items[0]);
    try std.testing.expectEqual(1, component.items[1]);
}

test "pop" {
    var gpa = CounterAllocator.init(testing.allocator);
    const allocator = gpa.allocator();

    var len: usize = 0;
    var component = ComponentStorageUnmanaged(u32).empty;
    defer component.deinit(allocator);

    try component.append(allocator, 0, &len);
    try component.append(allocator, 1, &len);

    const popped_item = component.pop(&len);

    try std.testing.expectEqual(1, gpa.counters.alloc);

    try std.testing.expectEqual(1, len);
    try std.testing.expectEqual(0, component.items[0]);
    try std.testing.expectEqual(1, popped_item);
}

test "swap_remove" {
    var gpa = CounterAllocator.init(testing.allocator);
    const allocator = gpa.allocator();

    var len: usize = 0;
    var component = ComponentStorageUnmanaged(u32).empty;
    defer component.deinit(allocator);

    try component.append(allocator, 0, &len);
    try component.append(allocator, 1, &len);
    try component.append(allocator, 2, &len);

    const popped_item = component.swap_remove(0, &len);

    try std.testing.expectEqual(1, gpa.counters.alloc);

    try std.testing.expectEqual(2, len);
    try std.testing.expectEqual(2, component.items[0]);
    try std.testing.expectEqual(0, popped_item);
}
