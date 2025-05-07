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

test "Query with pattern matching" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = Database.init(allocator);
    defer db.deinit();
    var products = try db.table("products_test_match");

    _ = try products.insert("{\"name\": \"iPhone 15\", \"category\": \"smartphone\", \"tags\": \"apple,mobile,premium\"}");
    _ = try products.insert("{\"name\": \"MacBook Air\", \"category\": \"laptop\", \"tags\": \"apple,computer,premium\"}");
    _ = try products.insert("{\"name\": \"Samsung Galaxy S24\", \"category\": \"smartphone\", \"tags\": \"samsung,mobile,premium\"}");
    _ = try products.insert("{\"name\": \"Pixel 8\", \"category\": \"smartphone\", \"tags\": \"google,mobile,premium\"}");
    _ = try products.insert("{\"name\": \"ThinkPad X1\", \"category\": \"laptop\", \"tags\": \"lenovo,computer,business\"}");

    {
        var query = Query.init(allocator);
        const prefix_match = query.field("name").matches("iPhone*");

        const results = try products.search(prefix_match);
        defer allocator.free(results);

        try std.testing.expectEqual(@as(usize, 1), results.len);
        try std.testing.expectEqualStrings("iPhone 15", results[0].get("name").?.string);
    }

    {
        var query = Query.init(allocator);
        const suffix_match = query.field("name").matches("*Book*");

        const results = try products.search(suffix_match);
        defer allocator.free(results);

        try std.testing.expectEqual(@as(usize, 2), results.len);

        var found_macbook = false;
        var found_thinkpad = false;

        for (results) |doc| {
            const name = doc.get("name").?.string;
            if (std.mem.eql(u8, name, "MacBook Air")) found_macbook = true;
            if (std.mem.eql(u8, name, "ThinkPad X1")) found_thinkpad = true;
        }

        try std.testing.expect(found_macbook);
        try std.testing.expect(found_thinkpad);
    }

    {
        var query = Query.init(allocator);
        const contains_match = query.field("name").matches("*pad*");

        const results = try products.search(contains_match);
        defer allocator.free(results);

        try std.testing.expectEqual(@as(usize, 1), results.len);
        try std.testing.expectEqualStrings("ThinkPad X1", results[0].get("name").?.string);
    }

    {
        var query = Query.init(allocator);
        const single_char_match = query.field("name").matches("iPhone 1?");

        const results = try products.search(single_char_match);
        defer allocator.free(results);

        try std.testing.expectEqual(@as(usize, 1), results.len);
        try std.testing.expectEqualStrings("iPhone 15", results[0].get("name").?.string);
    }

    {
        var query = Query.init(allocator);
        const complex_pattern = query.field("name").matches("*a*n*");

        const results = try products.search(complex_pattern);
        defer allocator.free(results);

        try std.testing.expectEqual(@as(usize, 2), results.len);

        var found_samsung = false;
        var found_thinkpad = false;

        for (results) |doc| {
            const name = doc.get("name").?.string;
            if (std.mem.eql(u8, name, "Samsung Galaxy S24")) found_samsung = true;
            if (std.mem.eql(u8, name, "ThinkPad X1")) found_thinkpad = true;
        }

        try std.testing.expect(found_samsung);
        try std.testing.expect(found_thinkpad);
    }

    {
        var query = Query.init(allocator);
        const tag_pattern = query.field("tags").matches("*mobile*");

        const results = try products.search(tag_pattern);
        defer allocator.free(results);

        try std.testing.expectEqual(@as(usize, 3), results.len);

        var found_iphone = false;
        var found_samsung = false;
        var found_pixel = false;

        for (results) |doc| {
            const name = doc.get("name").?.string;
            if (std.mem.eql(u8, name, "iPhone 15")) found_iphone = true;
            if (std.mem.eql(u8, name, "Samsung Galaxy S24")) found_samsung = true;
            if (std.mem.eql(u8, name, "Pixel 8")) found_pixel = true;
        }

        try std.testing.expect(found_iphone);
        try std.testing.expect(found_samsung);
        try std.testing.expect(found_pixel);
    }
}
