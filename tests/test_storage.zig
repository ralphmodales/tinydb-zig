const std = @import("std");
const Storage = @import("storage").Storage;
const Document = @import("document").Document;

test "Storage read and write" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var storage = Storage.init(allocator, "test_db.json");
    defer storage.deinit();

    var doc1 = try Document.initFromJson(allocator, "{\"name\": \"Alice\", \"age\": 25}", 1);
    defer doc1.deinit();
    var doc2 = try Document.initFromJson(allocator, "{\"name\": \"Bob\", \"age\": 30}", 2);
    defer doc2.deinit();

    const docs = &[_]Document{ doc1, doc2 };
    try storage.write(docs);

    const read_docs = try storage.read();
    defer allocator.free(read_docs);

    try std.testing.expectEqual(@as(usize, 2), read_docs.len);
    try std.testing.expectEqual(@as(?u64, 1), read_docs[0].id);
    try std.testing.expectEqualStrings("Alice", read_docs[0].get("name").?.string);
    try std.testing.expectEqual(@as(i64, 25), read_docs[0].get("age").?.integer);
    try std.testing.expectEqual(@as(?u64, 2), read_docs[1].id);
    try std.testing.expectEqualStrings("Bob", read_docs[1].get("name").?.string);
    try std.testing.expectEqual(@as(i64, 30), read_docs[1].get("age").?.integer);
}

test "Storage read empty file" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var storage = Storage.init(allocator, "nonexistent_db.json");
    defer storage.deinit();

    const docs = try storage.read();
    defer allocator.free(docs);
    try std.testing.expectEqual(@as(usize, 0), docs.len);
}
