const std = @import("std");
const Document = @import("document").Document;
const Storage = @import("storage").Storage;
const MemoryStorage = @import("memory_storage").MemoryStorage;
const QueryNode = @import("query").QueryNode;
const Condition = @import("query").Condition;

pub const StorageType = enum {
    file,
    memory,
};

pub const Table = struct {
    name: []const u8,
    storage_type: StorageType,
    storage: union {
        file: Storage,
        memory: MemoryStorage,
    },
    documents: std.ArrayList(Document),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, storage_type: StorageType, file_path: ?[]const u8) !Table {
        var doc_list = std.ArrayList(Document).init(allocator);
        const owned_name = try allocator.dupe(u8, name);

        var table = Table{
            .name = owned_name,
            .storage_type = storage_type,
            .storage = undefined,
            .documents = doc_list,
            .allocator = allocator,
        };

        switch (storage_type) {
            .file => {
                if (file_path == null) return error.FilePathRequired;
                table.storage = .{ .file = Storage.init(allocator, file_path.?) };
                const documents = try table.storage.file.read();
                defer allocator.free(documents);
                try doc_list.appendSlice(documents);
            },
            .memory => {
                table.storage = .{ .memory = MemoryStorage.init(allocator) };
            },
        }

        return table;
    }

    pub fn deinit(self: *Table) void {
        for (self.documents.items) |*doc| {
            doc.deinit();
        }
        self.documents.deinit();
        self.allocator.free(self.name);

        switch (self.storage_type) {
            .file => self.storage.file.deinit(),
            .memory => self.storage.memory.deinit(),
        }
    }

    pub fn insert(self: *Table, json_str: []const u8) !u64 {
        const id = @as(u64, self.documents.items.len + 1);
        const doc = try Document.initFromJson(self.allocator, json_str, id);
        try self.documents.append(doc);
        try self.saveToStorage();
        return id;
    }

    pub fn insertMultiple(self: *Table, json_strings: []const []const u8) ![]u64 {
        var ids = std.ArrayList(u64).init(self.allocator);
        defer ids.deinit();

        const start_id = self.documents.items.len + 1;

        for (json_strings, 0..) |json_str, i| {
            const id = @as(u64, start_id + i);
            const doc = try Document.initFromJson(self.allocator, json_str, id);
            try self.documents.append(doc);
            try ids.append(id);
        }

        try self.saveToStorage();
        return try self.allocator.dupe(u64, ids.items);
    }

    fn saveToStorage(self: *Table) !void {
        switch (self.storage_type) {
            .file => try self.storage.file.write(self.documents.items),
            .memory => try self.storage.memory.write(self.documents.items),
        }
    }

    pub fn search(self: Table, query_node: ?QueryNode) ![]Document {
        if (query_node == null) return self.documents.items;

        var matches = std.ArrayList(Document).init(self.allocator);
        defer matches.deinit();

        for (self.documents.items) |doc| {
            if (query_node.?.evaluate(doc)) {
                try matches.append(doc);
            }
        }

        const result = try self.allocator.dupe(Document, matches.items);
        return result;
    }

    pub fn searchByCondition(self: Table, condition: ?Condition) ![]Document {
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

    pub fn updateById(self: *Table, id: u64, json_str: []const u8) !void {
        for (self.documents.items) |*doc| {
            if (doc.id == id) {
                doc.deinit();
                doc.* = try Document.initFromJson(self.allocator, json_str, id);
                try self.saveToStorage();
                return;
            }
        }
        return error.DocumentNotFound;
    }

    pub fn update(self: *Table, query_node: ?QueryNode, json_str: []const u8) !usize {
        var updated_count: usize = 0;

        const matches = try self.search(query_node);
        defer self.allocator.free(matches);

        if (matches.len == 0) {
            return error.NoDocumentsMatch;
        }

        for (matches) |match| {
            for (self.documents.items) |*doc| {
                if (doc.id == match.id) {
                    const id = doc.id;
                    doc.deinit();
                    doc.* = try Document.initFromJson(self.allocator, json_str, id);
                    updated_count += 1;
                    break;
                }
            }
        }

        if (updated_count > 0) {
            try self.saveToStorage();
        }

        return updated_count;
    }

    pub fn removeById(self: *Table, id: u64) !void {
        for (self.documents.items, 0..) |doc, i| {
            if (doc.id == id) {
                var removed = self.documents.orderedRemove(i);
                removed.deinit();
                try self.saveToStorage();
                return;
            }
        }
        return error.DocumentNotFound;
    }

    pub fn remove(self: *Table, query_node: ?QueryNode) !usize {
        if (query_node == null) {
            return error.QueryRequired;
        }

        const matches = try self.search(query_node);
        defer self.allocator.free(matches);

        if (matches.len == 0) {
            return error.NoDocumentsMatch;
        }

        var ids_to_remove = std.ArrayList(u64).init(self.allocator);
        defer ids_to_remove.deinit();

        for (matches) |match| {
            if (match.id) |id| {
                try ids_to_remove.append(id);
            }
        }

        var removed_count: usize = 0;

        var i: usize = self.documents.items.len;
        while (i > 0) {
            i -= 1;
            const doc = self.documents.items[i];

            for (ids_to_remove.items) |id| {
                if (doc.id == id) {
                    var removed = self.documents.orderedRemove(i);
                    removed.deinit();
                    removed_count += 1;
                    break;
                }
            }
        }

        if (removed_count > 0) {
            try self.saveToStorage();
        }

        return removed_count;
    }

    pub const UpsertOperation = enum {
        insert,
        update,
    };

    pub const UpsertResult = struct {
        operation: UpsertOperation,
        count: usize,
        id: ?u64 = null,
    };

    pub fn upsert(self: *Table, query_node: ?QueryNode, json_str: []const u8) !UpsertResult {
        const matches = try self.search(query_node);
        defer self.allocator.free(matches);

        if (matches.len > 0) {
            var updated_count: usize = 0;
            for (matches) |match| {
                for (self.documents.items) |*doc| {
                    if (doc.id == match.id) {
                        const id = doc.id;
                        doc.deinit();
                        doc.* = try Document.initFromJson(self.allocator, json_str, id);
                        updated_count += 1;
                        break;
                    }
                }
            }

            if (updated_count > 0) {
                try self.saveToStorage();
            }

            return UpsertResult{ .operation = .update, .count = updated_count };
        } else {
            const id = try self.insert(json_str);
            return UpsertResult{ .operation = .insert, .count = 1, .id = id };
        }
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

        return try self.createTable(name, .file);
    }

    pub fn createTable(self: *Database, name: []const u8, storage_type: StorageType) !*Table {
        if (self.tables.getPtr(name)) |table_ptr| {
            return table_ptr;
        }

        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        var file_path: ?[]const u8 = null;
        if (storage_type == .file) {
            file_path = try std.fmt.allocPrint(self.allocator, "{s}.json", .{name});
            errdefer self.allocator.free(file_path.?);
        }

        const new_table = try Table.init(self.allocator, name, storage_type, file_path);
        if (file_path != null) {
            self.allocator.free(file_path.?);
        }

        try self.tables.put(name_copy, new_table);
        return self.tables.getPtr(name_copy).?;
    }
};
