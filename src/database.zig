const std = @import("std");
const Document = @import("document").Document;
const Storage = @import("storage").Storage;
const Condition = @import("query").Condition;

pub const Table = struct {
    name: []const u8,
    storage: Storage,
    documents: std.ArrayList(Document),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, file_path: []const u8) !Table {
        var storage = Storage.init(allocator, file_path);
        const documents = try storage.read();
        defer allocator.free(documents);

        var doc_list = std.ArrayList(Document).init(allocator);
        try doc_list.appendSlice(documents);

        const owned_name = try allocator.dupe(u8, name);

        return Table{
            .name = owned_name,
            .storage = storage,
            .documents = doc_list,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Table) void {
        for (self.documents.items) |*doc| {
            doc.deinit();
        }
        self.documents.deinit();
        self.allocator.free(self.name);
        self.storage.deinit();
    }

    pub fn insert(self: *Table, json_str: []const u8) !u64 {
        const id = @as(u64, self.documents.items.len + 1);
        const doc = try Document.initFromJson(self.allocator, json_str, id);
        try self.documents.append(doc);
        try self.storage.write(self.documents.items);
        return id;
    }

    pub fn search(self: Table, condition: ?Condition) ![]Document {
        if (condition == null) return self.documents.items;

        var matches = std.ArrayList(Document).init(self.allocator);
        defer matches.deinit();

        for (self.documents.items) |doc| {
            if (condition.?.evaluate(doc)) {
                try matches.append(doc);
            }
        }

        const result = try self.allocator.dupe(Document, matches.items);
        return result;
    }

    pub fn update(self: *Table, id: u64, json_str: []const u8) !void {
        for (self.documents.items) |*doc| {
            if (doc.id == id) {
                doc.deinit();
                doc.* = try Document.initFromJson(self.allocator, json_str, id);
                try self.storage.write(self.documents.items);
                return;
            }
        }
        return error.DocumentNotFound;
    }

    pub fn remove(self: *Table, id: u64) !void {
        for (self.documents.items, 0..) |doc, i| {
            if (doc.id == id) {
                var removed = self.documents.orderedRemove(i);
                removed.deinit();
                try self.storage.write(self.documents.items);
                return;
            }
        }
        return error.DocumentNotFound;
    }
};

pub const Database = struct {
    tables: std.StringHashMap(Table),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Database {
        return Database{
            .tables = std.StringHashMap(Table).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Database) void {
        var iter = self.tables.iterator();
        while (iter.next()) |entry| {
            var new_table = entry.value_ptr.*;
            new_table.deinit();
        }
        self.tables.deinit();
    }

    pub fn table(self: *Database, name: []const u8) !*Table {
        if (self.tables.getPtr(name)) |table_ptr| {
            return table_ptr;
        }

        const file_path = try std.fmt.allocPrint(self.allocator, "{s}.json", .{name});
        errdefer self.allocator.free(file_path);

        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        const new_table = try Table.init(self.allocator, name, file_path);
        self.allocator.free(file_path);

        try self.tables.put(name_copy, new_table);
        return self.tables.getPtr(name_copy).?;
    }
};
