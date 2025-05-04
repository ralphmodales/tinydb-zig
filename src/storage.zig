const std = @import("std");
const Document = @import("document").Document;

pub const Storage = struct {
    file_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) Storage {
        return Storage{
            .file_path = file_path,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Storage) void {
        _ = self;
    }

    pub fn write(self: Storage, documents: []const Document) !void {
        const file = try std.fs.cwd().createFile(self.file_path, .{});
        defer file.close();

        var buffered_writer = std.io.bufferedWriter(file.writer());
        const writer = buffered_writer.writer();

        try writer.writeByte('[');
        for (documents, 0..) |doc, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{{\"_id\": {},", .{doc.id orelse 0});
            try doc.toJson(writer);
            try writer.writeByte('}');
        }
        try writer.writeByte(']');
        try buffered_writer.flush();
    }

    pub fn read(self: Storage) ![]Document {
        const file = std.fs.cwd().openFile(self.file_path, .{}) catch |err| {
            if (err == error.FileNotFound) return &[_]Document{};
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice([]std.json.Value, self.allocator, content, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        var docs = try self.allocator.alloc(Document, parsed.value.len);
        for (parsed.value, 0..) |val, i| {
            if (val != .object) continue;
            const id = if (val.object.get("_id")) |id_val| switch (id_val) {
                .integer => @as(u64, @intCast(id_val.integer)),
                else => i + 1,
            } else i + 1;

            var buffer: [1024]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buffer);
            var writer = fbs.writer();

            try writer.writeByte('{');
            var first = true;
            var it = val.object.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, "_id")) continue;

                if (!first) try writer.writeByte(',');
                first = false;

                try writer.writeByte('"');
                try writer.writeAll(entry.key_ptr.*);
                try writer.writeAll("\":");
                try std.json.stringify(entry.value_ptr.*, .{}, writer);
            }
            try writer.writeByte('}');

            docs[i] = try Document.initFromJson(self.allocator, fbs.getWritten(), id);
        }
        return docs;
    }
};
