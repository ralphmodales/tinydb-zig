const std = @import("std");

pub const Document = struct {
    id: ?u64,
    data: std.json.Value,
    allocator: std.mem.Allocator,
    parsed: ?std.json.Parsed(std.json.Value) = null,

    pub fn initFromJson(allocator: std.mem.Allocator, json_str: []const u8, id: ?u64) !Document {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
        return Document{
            .id = id,
            .data = parsed.value,
            .allocator = allocator,
            .parsed = parsed,
        };
    }

    pub fn initEmpty(allocator: std.mem.Allocator, id: ?u64) Document {
        return Document{
            .id = id,
            .data = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
            .allocator = allocator,
            .parsed = null,
        };
    }

    pub fn deinit(self: *Document) void {
        if (self.parsed) |*p| {
            p.deinit();
        } else if (self.data == .object) {
            self.data.object.deinit();
        }
    }

    pub fn toJson(self: Document, writer: anytype) !void {
        try std.json.stringify(self.data, .{}, writer);
    }

    pub fn get(self: Document, key: []const u8) ?std.json.Value {
        var path_iter = std.mem.splitSequence(u8, key, ".");
        const first_key = path_iter.next() orelse return null;

        if (path_iter.next() == null) {
            if (self.data == .object) {
                return self.data.object.get(first_key);
            }
            return null;
        }

        path_iter = std.mem.splitSequence(u8, key, ".");

        var current_value: ?std.json.Value = self.data;

        while (path_iter.next()) |path_part| {
            if (current_value == null or current_value.? != .object) {
                return null;
            }

            current_value = current_value.?.object.get(path_part);

            if (current_value == null) {
                return null;
            }
        }

        return current_value;
    }

    pub fn put(self: *Document, key: []const u8, value: std.json.Value) !void {
        if (self.data == .object) {
            try self.data.object.put(key, value);
        }
    }

    pub fn clone(self: Document) !Document {
        var cloned_data: std.json.Value = undefined;

        if (self.data == .object) {
            var new_obj = std.json.ObjectMap.init(self.allocator);

            var it = self.data.object.iterator();
            while (it.next()) |entry| {
                var buf = std.ArrayList(u8).init(self.allocator);
                defer buf.deinit();

                try std.json.stringify(entry.value_ptr.*, .{}, buf.writer());

                const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, buf.items, .{ .allocate = .alloc_always });

                const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                errdefer self.allocator.free(key_copy);

                try new_obj.put(key_copy, parsed.value);
            }

            cloned_data = .{ .object = new_obj };
        } else {
            var buf = std.ArrayList(u8).init(self.allocator);
            defer buf.deinit();

            try std.json.stringify(self.data, .{}, buf.writer());

            const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, buf.items, .{ .allocate = .alloc_always });

            cloned_data = parsed.value;
        }

        return Document{
            .id = self.id,
            .data = cloned_data,
            .allocator = self.allocator,
            .parsed = null,
        };
    }
};
