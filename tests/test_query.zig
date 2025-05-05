const std = @import("std");
const Database = @import("database").Database;
const Document = @import("document").Document;
const Query = @import("query").Query;

test "Query and search" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();
    var users = try db.table("users");

    _ = try users.insert("{\"name\": \"Alice\", \"age\": 25}");
    _ = try users.insert("{\"name\": \"Bob\", \"age\": 30}");
    _ = try users.insert("{\"name\": \"Charlie\", \"age\": 20}");

    var query = Query.init(allocator);

    const eq_condition = query.field("age").eq(25);
    const eq_results = try users.search(eq_condition);
    defer allocator.free(eq_results);
    try std.testing.expectEqual(@as(usize, 1), eq_results.len);
    try std.testing.expectEqualStrings("Alice", eq_results[0].get("name").?.string);

    const gt_condition = query.field("age").gt(25);
    const gt_results = try users.search(gt_condition);
    defer allocator.free(gt_results);
    try std.testing.expectEqual(@as(usize, 1), gt_results.len);
    try std.testing.expectEqualStrings("Bob", gt_results[0].get("name").?.string);

    const le_condition = query.field("age").le(25);
    const le_results = try users.search(le_condition);
    defer allocator.free(le_results);
    try std.testing.expectEqual(@as(usize, 2), le_results.len);
    try std.testing.expectEqualStrings("Alice", le_results[0].get("name").?.string);
    try std.testing.expectEqualStrings("Charlie", le_results[1].get("name").?.string);

    const str_condition = query.field("name").eq("Bob");
    const str_results = try users.search(str_condition);
    defer allocator.free(str_results);
    try std.testing.expectEqual(@as(usize, 1), str_results.len);
    try std.testing.expectEqual(@as(i64, 30), str_results[0].get("age").?.integer);

    const all_results = try users.search(null);
    try std.testing.expectEqual(@as(usize, 3), all_results.len);
}
