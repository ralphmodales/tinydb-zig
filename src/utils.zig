const std = @import("std");
const Operator = @import("query").Operator;

pub fn stringToOperator(op_str: []const u8) !Operator {
    if (std.mem.eql(u8, op_str, "eq")) {
        return Operator.eq;
    } else if (std.mem.eql(u8, op_str, "ne")) {
        return Operator.ne;
    } else if (std.mem.eql(u8, op_str, "gt")) {
        return Operator.gt;
    } else if (std.mem.eql(u8, op_str, "lt")) {
        return Operator.lt;
    } else if (std.mem.eql(u8, op_str, "ge")) {
        return Operator.ge;
    } else if (std.mem.eql(u8, op_str, "le")) {
        return Operator.le;
    } else {
        return error.InvalidOperator;
    }
}

pub fn prettyPrintJson(allocator: std.mem.Allocator, json_str: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    try std.json.stringify(parsed.value, .{ .whitespace = .indent_2 }, buffer.writer());
    return buffer.toOwnedSlice();
}

pub fn validateJson(allocator: std.mem.Allocator, json_str: []const u8) !bool {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return true;
}

pub fn getTimestamp() ![]u8 {
    var buffer: [64]u8 = undefined;
    const timestamp = std.time.timestamp();
    const len = try std.fmt.bufPrint(&buffer, "{d}", .{timestamp});
    return buffer[0..len];
}

pub fn hashString(string: []const u8) ![64]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(string, &hash, .{});

    var hash_hex: [64]u8 = undefined;
    _ = try std.fmt.bufPrint(&hash_hex, "{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    return hash_hex;
}

pub fn generateId(allocator: std.mem.Allocator) ![]u8 {
    var random = std.crypto.random;
    var bytes: [16]u8 = undefined;
    random.bytes(&bytes);

    var buffer: [32]u8 = undefined;
    const len = try std.fmt.bufPrint(&buffer, "{s}", .{std.fmt.fmtSliceHexLower(&bytes)});
    return allocator.dupe(u8, buffer[0..len]);
}
