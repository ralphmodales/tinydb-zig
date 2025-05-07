const std = @import("std");
const Database = @import("database").Database;
const Document = @import("document").Document;
const Query = @import("query").Query;
const QueryNode = @import("query").QueryNode;

test "Complex Query with logical AND" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();
    var users = try db.table("users_test_and");

    _ = try users.insert("{\"name\": \"Alice\", \"age\": 25, \"active\": true}");
    _ = try users.insert("{\"name\": \"Bob\", \"age\": 30, \"active\": true}");
    _ = try users.insert("{\"name\": \"Charlie\", \"age\": 25, \"active\": false}");
    _ = try users.insert("{\"name\": \"Dave\", \"age\": 40, \"active\": true}");

    var query = Query.init(allocator);
    const age_condition = query.field("age").eq(25);
    const active_condition = query.field("active").eq(true);

    var and_query = try QueryNode.andOp(allocator, age_condition, active_condition);
    defer and_query.deinit();

    const results = try users.search(and_query);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Alice", results[0].get("name").?.string);
}

test "Complex Query with logical OR" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();
    var users = try db.table("users_test_or");

    _ = try users.insert("{\"name\": \"Alice\", \"age\": 25, \"role\": \"admin\"}");
    _ = try users.insert("{\"name\": \"Bob\", \"age\": 30, \"role\": \"user\"}");
    _ = try users.insert("{\"name\": \"Charlie\", \"age\": 35, \"role\": \"admin\"}");
    _ = try users.insert("{\"name\": \"Dave\", \"age\": 40, \"role\": \"guest\"}");

    var query = Query.init(allocator);
    const role_admin = query.field("role").eq("admin");
    const age_over_35 = query.field("age").ge(35);

    var or_query = try QueryNode.orOp(allocator, role_admin, age_over_35);
    defer or_query.deinit();

    const results = try users.search(or_query);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 3), results.len);
}

test "Complex Query with logical NOT" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();
    var users = try db.table("users_test_not");

    _ = try users.insert("{\"name\": \"Alice\", \"age\": 25, \"premium\": true}");
    _ = try users.insert("{\"name\": \"Bob\", \"age\": 30, \"premium\": false}");
    _ = try users.insert("{\"name\": \"Charlie\", \"age\": 35, \"premium\": true}");

    var query = Query.init(allocator);
    const premium_condition = query.field("premium").eq(true);

    var not_query = try QueryNode.notOp(allocator, premium_condition);
    defer not_query.deinit();

    const results = try users.search(not_query);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Bob", results[0].get("name").?.string);
}

test "Nested Complex Query (AND + OR)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();
    var products = try db.table("products_test_compound");

    _ = try products.insert("{\"name\": \"Laptop\", \"price\": 1200, \"inStock\": true, \"category\": \"electronics\"}");
    _ = try products.insert("{\"name\": \"Phone\", \"price\": 800, \"inStock\": true, \"category\": \"electronics\"}");
    _ = try products.insert("{\"name\": \"Desk\", \"price\": 300, \"inStock\": false, \"category\": \"furniture\"}");
    _ = try products.insert("{\"name\": \"Chair\", \"price\": 100, \"inStock\": true, \"category\": \"furniture\"}");
    _ = try products.insert("{\"name\": \"Monitor\", \"price\": 400, \"inStock\": true, \"category\": \"electronics\"}");

    var query = Query.init(allocator);

    const electronics = query.field("category").eq("electronics");
    const furniture = query.field("category").eq("furniture");
    var category_query = try QueryNode.orOp(allocator, electronics, furniture);

    const in_stock = query.field("inStock").eq(true);
    var combined_query = try QueryNode.andOp(allocator, category_query, in_stock);

    const cheap_price = query.field("price").lt(500);
    var final_query = try QueryNode.andOp(allocator, combined_query, cheap_price);
    defer final_query.deinit();

    defer combined_query.deinit();
    defer category_query.deinit();

    const results = try products.search(final_query);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);

    var found_chair = false;
    var found_monitor = false;

    for (results) |doc| {
        const name = doc.get("name").?.string;
        if (std.mem.eql(u8, name, "Chair")) found_chair = true;
        if (std.mem.eql(u8, name, "Monitor")) found_monitor = true;
    }

    try std.testing.expect(found_chair);
    try std.testing.expect(found_monitor);
}

test "Query with nested field paths" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();
    var orders = try db.table("orders_nested");

    _ = try orders.insert("{\"id\": \"1001\", \"customer\": {\"name\": \"Alice\", \"status\": \"vip\"}}");
    _ = try orders.insert("{\"id\": \"1002\", \"customer\": {\"name\": \"Bob\", \"status\": \"regular\"}}");
    _ = try orders.insert("{\"id\": \"1003\", \"customer\": {\"name\": \"Charlie\", \"status\": \"vip\"}}");

    var query = Query.init(allocator);
    const vip_condition = query.field("customer.status").eq("vip");

    const results = try orders.search(vip_condition);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);

    var found_alice = false;
    var found_charlie = false;

    for (results) |doc| {
        const id = doc.get("id").?.string;
        if (std.mem.eql(u8, id, "1001")) found_alice = true;
        if (std.mem.eql(u8, id, "1003")) found_charlie = true;
    }

    try std.testing.expect(found_alice);
    try std.testing.expect(found_charlie);
}
