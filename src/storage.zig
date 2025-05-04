const std = @import("std");
const Document = @import("document").Document;

pub const Storage = struct {
    file_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) Storage {
        const owned_path = allocator.dupe(u8, file_path) catch unreachable;

        return Storage{
            .file_path = owned_path,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Storage) void {
        self.allocator.free(self.file_path);
    }

    pub fn write(self: Storage, documents: []const Document) !void {
        const file = try std.fs.cwd().createFile(self.file_path, .{});
        defer file.close();

        var buffered_writer = std.io.bufferedWriter(file.writer());
        const writer = buffered_writer.writer();

        try writer.writeByte('[');
        for (documents, 0..) |doc, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{{\"_id\":", .{});
            try std.json.stringify(doc.id orelse @as(u64, i + 1), .{}, writer);
            try writer.writeAll(",");

            if (doc.data == .object) {
                var it = doc.data.object.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) try writer.writeByte(',');
                    first = false;

                    try writer.writeByte('"');
                    try writer.writeAll(entry.key_ptr.*);
                    try writer.writeAll("\":");
                    try std.json.stringify(entry.value_ptr.*, .{}, writer);
                }
            }
            try writer.writeByte('}');
        }
        try writer.writeByte(']');
        try buffered_writer.flush();
    }

    pub fn read(self: Storage) ![]Document {
        const file = std.fs.cwd().openFile(self.file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return self.allocator.alloc(Document, 0);
            }
            return err;
        };
        defer file.close();

        const stat = try file.stat();
        if (stat.size == 0) {
            return self.allocator.alloc(Document, 0);
        }

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        if (std.mem.eql(u8, content, "[]")) {
            return self.allocator.alloc(Document, 0);
        }

        const parsed = std.json.parseFromSliceLeaky([]std.json.Value, self.allocator, content, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }) catch |err| {
            std.debug.print("Failed to parse JSON: {s}\nContent: {s}\n", .{ @errorName(err), content });
            return err;
        };

        var docs = try self.allocator.alloc(Document, parsed.len);
        errdefer {
            for (docs) |*doc| {
                doc.deinit();
            }
            self.allocator.free(docs);
        }

        for (parsed, 0..) |val, i| {
            if (val != .object) {
                docs[i] = Document.initEmpty(self.allocator, @as(u64, i + 1));
                continue;
            }

            const id = if (val.object.get("_id")) |id_val| switch (id_val) {
                .integer => @as(u64, @intCast(id_val.integer)),
                .float => @as(u64, @intFromFloat(id_val.float)),
                .string => std.fmt.parseInt(u64, id_val.string, 10) catch i + 1,
                else => i + 1,
            } else i + 1;

            var doc = Document.initEmpty(self.allocator, id);

            var it = val.object.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, "_id")) continue;
                try doc.put(entry.key_ptr.*, entry.value_ptr.*);
            }

            docs[i] = doc;
        }

        return docs;
    }
};
