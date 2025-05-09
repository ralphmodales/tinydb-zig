const std = @import("std");
const Document = @import("document").Document;

pub const MemoryStorage = struct {
    documents: std.ArrayList(Document),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MemoryStorage {
        return MemoryStorage{
            .documents = std.ArrayList(Document).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MemoryStorage) void {
        for (self.documents.items) |*doc| {
            doc.deinit();
        }
        self.documents.deinit();
    }

    pub fn write(self: *MemoryStorage, documents: []const Document) !void {
        for (self.documents.items) |*doc| {
            doc.deinit();
        }
        self.documents.clearRetainingCapacity();

        for (documents) |doc| {
            try self.documents.append(try doc.clone());
        }
    }

    pub fn read(self: MemoryStorage) ![]Document {
        var docs = try self.allocator.alloc(Document, self.documents.items.len);
        errdefer {
            for (docs) |*doc| {
                doc.deinit();
            }
            self.allocator.free(docs);
        }

        for (self.documents.items, 0..) |doc, i| {
            docs[i] = try doc.clone();
        }

        return docs;
    }
};
