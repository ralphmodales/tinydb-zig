const std = @import("std");
const Document = @import("document").Document;

test "Document creation and serialization" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_str = "{\"name\": \"Alice\", \"age\": 25}";
    var doc = try Document.initFromJson(allocator, json_str, 1);
    defer doc.deinit();

    try std.testing.expectEqual(@as(?u64, 1), doc.id);

    const name = doc.get("name");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("Alice", name.?.string);

    const age = doc.get("age");
    try std.testing.expect(age != null);
    try std.testing.expectEqual(@as(i64, 25), age.?.integer);

    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try doc.toJson(fbs.writer());
    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"name\":\"Alice\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"age\":25") != null);
}

test "Document empty and put" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var doc = Document.initEmpty(allocator, null);
    defer doc.deinit();

    try doc.put("name", .{ .string = "Bob" });
    const name = doc.get("name");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("Bob", name.?.string);
}
