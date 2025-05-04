const std = @import("std");
const Database = @import("database").Database;
const Document = @import("document").Document;

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

    const docs = users.search();
    try std.testing.expectEqual(@as(usize, 2), docs.len);
    try std.testing.expectEqualStrings("Alice", docs[0].get("name").?.string);
    try std.testing.expectEqualStrings("Bob", docs[1].get("name").?.string);

    try users.update(id1, "{\"name\": \"Alice Updated\", \"age\": 26}");
    const updated_docs = users.search();
    try std.testing.expectEqualStrings("Alice Updated", updated_docs[0].get("name").?.string);
    try std.testing.expectEqual(@as(i64, 26), updated_docs[0].get("age").?.integer);

    try users.remove(id2);
    const final_docs = users.search();
    try std.testing.expectEqual(@as(usize, 1), final_docs.len);
    try std.testing.expectEqualStrings("Alice Updated", final_docs[0].get("name").?.string);

    var products = try db.table("products");
    const prod_id = try products.insert("{\"item\": \"Laptop\", \"price\": 999}");
    try std.testing.expectEqual(@as(u64, 1), prod_id);
    try std.testing.expectEqual(@as(usize, 1), products.search().len);
    try std.testing.expectEqual(@as(usize, 1), users.search().len);
}
