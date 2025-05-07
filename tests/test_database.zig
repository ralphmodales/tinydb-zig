const std = @import("std");
const Database = @import("database").Database;
const Document = @import("document").Document;
const Query = @import("query").Query;

test "Database and Table CRUD operations" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var users = try db.table("users");

    const id1 = try users.insert("{\"name\": \"Alice\", \"age\": 25}");
    try std.testing.expectEqual(@as(u64, 1), id1);
    const id2 = try users.insert("{\"name\": \"Bob\", \"age\": 30}");
    try std.testing.expectEqual(@as(u64, 2), id2);

    const docs = try users.search(null);
    try std.testing.expectEqual(@as(usize, 2), docs.len);
    try std.testing.expectEqualStrings("Alice", docs[0].get("name").?.string);
    try std.testing.expectEqualStrings("Bob", docs[1].get("name").?.string);

    try users.updateById(id1, "{\"name\": \"Alice Updated\", \"age\": 26}");
    const updated_docs = try users.search(null);
    try std.testing.expectEqualStrings("Alice Updated", updated_docs[0].get("name").?.string);
    try std.testing.expectEqual(@as(i64, 26), updated_docs[0].get("age").?.integer);

    try users.removeById(id2);
    const final_docs = try users.search(null);
    try std.testing.expectEqual(@as(usize, 1), final_docs.len);
    try std.testing.expectEqualStrings("Alice Updated", final_docs[0].get("name").?.string);

    var products = try db.table("products");
    const prod_id = try products.insert("{\"item\": \"Laptop\", \"price\": 999}");
    try std.testing.expectEqual(@as(u64, 1), prod_id);
    try std.testing.expectEqual(@as(usize, 1), (try products.search(null)).len);
    try std.testing.expectEqual(@as(usize, 1), (try users.search(null)).len);
}

test "Query-based Update and Delete operations" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var users = try db.table("users_query_ops");

    _ = try users.insert("{\"name\": \"John\", \"age\": 30}");
    _ = try users.insert("{\"name\": \"Jane\", \"age\": 20}");

    {
        const initial_docs = try users.search(null);
        try std.testing.expectEqual(@as(usize, 2), initial_docs.len);

        var found_john = false;
        var found_jane = false;

        for (initial_docs) |doc| {
            const name = doc.get("name").?.string;
            if (std.mem.eql(u8, name, "John")) found_john = true;
            if (std.mem.eql(u8, name, "Jane")) found_jane = true;
        }

        try std.testing.expect(found_john);
        try std.testing.expect(found_jane);
    }

    var query = Query.init(allocator);
    const age_gt_25 = query.field("age").gt(25);

    const updated_count = try users.update(age_gt_25, "{\"name\": \"John\", \"age\": 30, \"status\": \"senior\"}");
    try std.testing.expectEqual(@as(usize, 1), updated_count);

    {
        const updated_docs = try users.search(null);
        try std.testing.expectEqual(@as(usize, 2), updated_docs.len);

        var found_john_with_status = false;
        var found_jane_without_status = false;

        for (updated_docs) |doc| {
            const name = doc.get("name").?.string;
            if (std.mem.eql(u8, name, "John")) {
                try std.testing.expectEqualStrings("senior", doc.get("status").?.string);
                found_john_with_status = true;
            }
            if (std.mem.eql(u8, name, "Jane")) {
                try std.testing.expect(doc.get("status") == null);
                found_jane_without_status = true;
            }
        }

        try std.testing.expect(found_john_with_status);
        try std.testing.expect(found_jane_without_status);
    }

    const age_lt_25 = query.field("age").lt(25);

    const deleted_count = try users.remove(age_lt_25);
    try std.testing.expectEqual(@as(usize, 1), deleted_count);

    {
        const final_docs = try users.search(null);
        try std.testing.expectEqual(@as(usize, 1), final_docs.len);
        try std.testing.expectEqualStrings("John", final_docs[0].get("name").?.string);
        try std.testing.expectEqual(@as(i64, 30), final_docs[0].get("age").?.integer);
        try std.testing.expectEqualStrings("senior", final_docs[0].get("status").?.string);
    }
}

test "Upsert operations" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var users = try db.table("users_upsert");

    _ = try users.insert("{\"name\": \"John\", \"age\": 30}");

    var query_builder = Query.init(allocator);
    const initial_john_filter = query_builder.field("name").eq("John");
    var docs = try users.search(initial_john_filter);
    try std.testing.expectEqual(@as(usize, 1), docs.len);
    try std.testing.expectEqual(@as(i64, 30), docs[0].get("age").?.integer);

    const john_upsert_filter = query_builder.field("name").eq("John");
    const john_update_data = "{\"name\": \"John\", \"age\": 31}";

    docs = try users.search(john_upsert_filter);
    if (docs.len > 0) {
        const updated_count = try users.update(john_upsert_filter, john_update_data);
        try std.testing.expectEqual(@as(usize, 1), updated_count);
    } else {
        _ = try users.insert(john_update_data);
        try std.testing.expect(false);
    }

    docs = try users.search(john_upsert_filter);
    try std.testing.expectEqual(@as(usize, 1), docs.len);
    try std.testing.expectEqualStrings("John", docs[0].get("name").?.string);
    try std.testing.expectEqual(@as(i64, 31), docs[0].get("age").?.integer);

    var all_docs = try users.search(null);
    try std.testing.expectEqual(@as(usize, 1), all_docs.len);

    const jane_upsert_filter = query_builder.field("name").eq("Jane");
    const jane_data = "{\"name\": \"Jane\", \"age\": 20}";

    docs = try users.search(jane_upsert_filter);
    if (docs.len > 0) {
        _ = try users.update(jane_upsert_filter, jane_data);
        try std.testing.expect(false);
    } else {
        _ = try users.insert(jane_data);
    }

    docs = try users.search(jane_upsert_filter);
    try std.testing.expectEqual(@as(usize, 1), docs.len);
    try std.testing.expectEqualStrings("Jane", docs[0].get("name").?.string);
    try std.testing.expectEqual(@as(i64, 20), docs[0].get("age").?.integer);

    all_docs = try users.search(null);
    try std.testing.expectEqual(@as(usize, 2), all_docs.len);

    docs = try users.search(john_upsert_filter);
    try std.testing.expectEqual(@as(usize, 1), docs.len);
    try std.testing.expectEqual(@as(i64, 31), docs[0].get("age").?.integer);
}
