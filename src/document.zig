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
        if (self.data == .object) {
            return self.data.object.get(key);
        }
        return null;
    }

    pub fn put(self: *Document, key: []const u8, value: std.json.Value) !void {
        if (self.data == .object) {
            try self.data.object.put(key, value);
        }
    }
};
