const std = @import("std");
const Database = @import("database").Database;
const Query = @import("query").Query;
const QueryNode = @import("query").QueryNode;
const Condition = @import("query").Condition;
const Operator = @import("query").Operator;
const LogicalOperator = @import("query").LogicalOperator;
const utils = @import("utils");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.print("TinyDB in Zig\n", .{});
    try stdout.print("Enter 'help' for commands\n", .{});

    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.print("tinydb> ", .{});
        const input = (try stdin.readUntilDelimiterOrEof(&buffer, '\n')) orelse break;

        if (input.len == 0) continue;

        var cmd_iter = std.mem.splitSequence(u8, input, " ");
        const cmd = cmd_iter.first();

        if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "quit")) {
            break;
        } else if (std.mem.eql(u8, cmd, "help")) {
            try printHelp(stdout);
        } else if (std.mem.eql(u8, cmd, "create")) {
            const table_name = cmd_iter.next() orelse {
                try stdout.print("Error: Missing table name\n", .{});
                continue;
            };

            const storage_type_str = cmd_iter.next();
            var storage_type: @import("database").StorageType = .file;
            if (storage_type_str) |str| {
                if (std.mem.eql(u8, str, "memory")) {
                    storage_type = .memory;
                } else if (std.mem.eql(u8, str, "file")) {
                    storage_type = .file;
                } else {
                    try stdout.print("Error: Invalid storage type '{s}', using default (file)\n", .{str});
                }
            }

            _ = try db.createTable(table_name, storage_type);
            try stdout.print("Table '{s}' created with {s} storage\n", .{ table_name, if (storage_type == .memory) "memory" else "file" });
        } else if (std.mem.eql(u8, cmd, "insert")) {
            try handleInsert(stdout, &db, &cmd_iter, allocator);
        } else if (std.mem.eql(u8, cmd, "insert_multiple")) {
            try handleInsertMultiple(stdout, &db, &cmd_iter, allocator);
        } else if (std.mem.eql(u8, cmd, "find")) {
            try handleFind(stdout, &db, &cmd_iter, allocator);
        } else if (std.mem.eql(u8, cmd, "update")) {
            try handleUpdate(stdout, &db, &cmd_iter, allocator);
        } else if (std.mem.eql(u8, cmd, "upsert")) {
            try handleUpsert(stdout, &db, &cmd_iter, allocator);
        } else if (std.mem.eql(u8, cmd, "delete")) {
            try handleDelete(stdout, &db, &cmd_iter, allocator);
        } else if (std.mem.eql(u8, cmd, "list")) {
            const next_cmd = cmd_iter.next() orelse {
                try stdout.print("Error: Missing 'tables' or table name after 'list'\n", .{});
                continue;
            };

            if (std.mem.eql(u8, next_cmd, "tables")) {
                try listTables(stdout, &db);
            } else {
                const table_ptr = db.table(next_cmd) catch {
                    try stdout.print("Error: Table '{s}' not found\n", .{next_cmd});
                    continue;
                };

                const docs = try table_ptr.search(null);
                try stdout.print("Documents in table '{s}':\n", .{next_cmd});
                for (docs) |doc| {
                    try stdout.print("ID: {?d} - ", .{doc.id});
                    try doc.toJson(stdout);
                    try stdout.print("\n", .{});
                }
            }
        } else {
            try stdout.print("Unknown command: {s}\n", .{cmd});
            try stdout.print("Enter 'help' for commands\n", .{});
        }
    }
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Commands:
        \\  help                                 - Show this help message
        \\  create <table> [storage_type]        - Create a new table (storage_type: file or memory, default: file)
        \\  insert <table> <json>                - Insert a new document into table
        \\  insert_multiple <table> <json_array> - Insert multiple documents into table
        \\  find <table> [query]                 - Find documents in table with optional query
        \\  update <table> <id> <json>           - Update document by ID
        \\  update <table> <query> with <json>   - Update documents matching query
        \\  upsert <table> <query> with <json>   - Update if documents match query, otherwise insert
        \\  delete <table> <id>                  - Delete document by ID
        \\  delete <table> <query>               - Delete documents matching query
        \\  list tables                          - List all tables
        \\  list <table>                         - List all documents in table
        \\  exit, quit                           - Exit the program
        \\
        \\Query Syntax:
        \\  Simple: field op value
        \\  Complex: (field1 op1 value1) AND|OR (field2 op2 value2)
        \\  Negation: NOT (field op value)
        \\
        \\Operators:
        \\  eq, ne, gt, lt, ge, le       - Equal, Not Equal, Greater Than, Less Than, Greater/Equal, Less/Equal
        \\  matches                      - Pattern matching with wildcards (* and ?)
        \\  AND, OR, NOT                 - Logical operators (case insensitive)
        \\
        \\Examples:
        \\  create users memory
        \\  insert users {{"name":"John","age":30}}
        \\  insert_multiple users [{{"name":"John","age":30}},{{"name":"Jane","age":25}}]
        \\  upsert users name eq "John" with {{"name":"John","age":31}}
        \\  find users age gt 25
        \\  find users name matches "Jo*"
        \\  find users (age gt 25) AND (name eq "John")
        \\  find users (age gt 20) OR (name eq "Jane")
        \\  find users NOT (age lt 30)
        \\  update users 1 {{"name":"John","age":31}}
        \\  update users age gt 25 with {{"status":"senior"}}
        \\  delete users 1
        \\  delete users age lt 18
        \\  list tables
        \\  list users
        \\
    , .{});
}

fn handleInsert(
    writer: anytype,
    db: *Database,
    cmd_iter: *std.mem.SplitIterator(u8, .sequence),
    allocator: std.mem.Allocator,
) !void {
    const table_name = cmd_iter.next() orelse {
        try writer.print("Error: Missing table name\n", .{});
        return;
    };

    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    var first_part = true;
    while (cmd_iter.next()) |part| {
        if (!first_part) {
            try json_string.append(' ');
        } else {
            first_part = false;
        }
        try json_string.appendSlice(part);
    }

    if (json_string.items.len == 0) {
        try writer.print("Error: Missing JSON data\n", .{});
        return;
    }

    const table_ptr = db.table(table_name) catch {
        try writer.print("Error: Table '{s}' not found\n", .{table_name});
        return;
    };

    const doc_id = table_ptr.insert(json_string.items) catch |err| {
        try writer.print("Error inserting document: {s}\n", .{@errorName(err)});
        if (err == error.JsonParseFailed) {
            try writer.print("  -> Check JSON syntax: {s}\n", .{json_string.items});
        }
        return;
    };

    try writer.print("Document inserted with ID: {d}\n", .{doc_id});
}

fn handleInsertMultiple(
    writer: anytype,
    db: *Database,
    cmd_iter: *std.mem.SplitIterator(u8, .sequence),
    allocator: std.mem.Allocator,
) !void {
    const table_name = cmd_iter.next() orelse {
        try writer.print("Error: Missing table name\n", .{});
        return;
    };

    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    var first_part = true;
    while (cmd_iter.next()) |part| {
        if (!first_part) {
            try json_string.append(' ');
        } else {
            first_part = false;
        }
        try json_string.appendSlice(part);
    }

    if (json_string.items.len == 0) {
        try writer.print("Error: Missing JSON array data\n", .{});
        return;
    }

    const trimmed = std.mem.trim(u8, json_string.items, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') {
        try writer.print("Error: JSON array must be enclosed in square brackets []\n", .{});
        return;
    }

    const table_ptr = db.table(table_name) catch {
        try writer.print("Error: Table '{s}' not found\n", .{table_name});
        return;
    };

    var json_docs = std.ArrayList([]const u8).init(allocator);
    defer {
        for (json_docs.items) |item| {
            allocator.free(item);
        }
        json_docs.deinit();
    }

    var depth: u32 = 0;
    var in_quotes = false;
    var escaped = false;
    var start: usize = 0;
    var i: usize = 0;

    i = 1;
    while (i < trimmed.len - 1) {
        if (depth == 0 and std.ascii.isWhitespace(trimmed[i])) {
            i += 1;
            continue;
        }

        if (depth == 0 and trimmed[i] == '{') {
            start = i;
            depth += 1;
        } else if (in_quotes) {
            if (escaped) {
                escaped = false;
            } else if (trimmed[i] == '\\') {
                escaped = true;
            } else if (trimmed[i] == '"') {
                in_quotes = false;
            }
        } else if (trimmed[i] == '"') {
            in_quotes = true;
        } else if (trimmed[i] == '{') {
            depth += 1;
        } else if (trimmed[i] == '}') {
            depth -= 1;
            if (depth == 0) {
                const doc_str = try allocator.dupe(u8, trimmed[start .. i + 1]);
                try json_docs.append(doc_str);
            }
        }

        i += 1;
    }

    if (json_docs.items.len == 0) {
        try writer.print("Error: No valid JSON objects found in array\n", .{});
        return;
    }

    const ids = table_ptr.insertMultiple(json_docs.items) catch |err| {
        try writer.print("Error inserting documents: {s}\n", .{@errorName(err)});
        if (err == error.JsonParseFailed) {
            try writer.print("  -> Check JSON syntax\n", .{});
        }
        return;
    };
    defer allocator.free(ids);

    try writer.print("Inserted {d} documents with IDs: ", .{ids.len});
    for (ids, 0..) |id, idx| {
        try writer.print("{d}", .{id});
        if (idx < ids.len - 1) {
            try writer.print(", ", .{});
        }
    }
    try writer.print("\n", .{});
}

fn handleFind(
    writer: anytype,
    db: *Database,
    cmd_iter: *std.mem.SplitIterator(u8, .sequence),
    allocator: std.mem.Allocator,
) !void {
    const table_name = cmd_iter.next() orelse {
        try writer.print("Error: Missing table name\n", .{});
        return;
    };

    const table_ptr = db.table(table_name) catch {
        try writer.print("Error: Table '{s}' not found\n", .{table_name});
        return;
    };

    var query_string = std.ArrayList(u8).init(allocator);
    defer query_string.deinit();

    while (cmd_iter.next()) |part| {
        if (query_string.items.len > 0) {
            try query_string.append(' ');
        }
        try query_string.appendSlice(part);
    }

    if (query_string.items.len == 0) {
        const docs = try table_ptr.search(null);
        try writer.print("Found {d} documents in table '{s}':\n", .{ docs.len, table_name });
        for (docs) |doc| {
            try writer.print("ID: {?d} - ", .{doc.id});
            try doc.toJson(writer);
            try writer.print("\n", .{});
        }
        return;
    }

    var query_node = parseQuery(allocator, query_string.items) catch |err| {
        try writer.print("Error parsing query: {s}\n", .{@errorName(err)});
        return;
    };
    defer query_node.deinit();

    const docs = try table_ptr.search(query_node);
    try writer.print("Found {d} documents in table '{s}' matching query:\n", .{ docs.len, table_name });
    for (docs) |doc| {
        try writer.print("ID: {?d} - ", .{doc.id});
        try doc.toJson(writer);
        try writer.print("\n", .{});
    }
}

const TokenType = enum {
    field,
    operator,
    value,
    leftParen,
    rightParen,
    logicalOperator,
    updateKeyword,
};

const Token = struct {
    type: TokenType,
    value: []const u8,
};

fn parseQuery(allocator: std.mem.Allocator, query_str: []const u8) !QueryNode {
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    try tokenizeQuery(allocator, query_str, &tokens);

    if (tokens.items.len == 0) {
        return error.EmptyQuery;
    }

    if (tokens.items.len == 3 and
        tokens.items[0].type == .field and
        tokens.items[1].type == .operator and
        tokens.items[2].type == .value)
    {
        return try parseSimpleCondition(allocator, tokens.items[0].value, tokens.items[1].value, tokens.items[2].value);
    }

    var pos: usize = 0;
    return try parseExpression(allocator, tokens.items, &pos);
}

fn tokenizeQuery(allocator: std.mem.Allocator, query_str: []const u8, tokens: *std.ArrayList(Token)) !void {
    var i: usize = 0;
    var in_quotes = false;
    var token_start: usize = 0;
    var current_token = std.ArrayList(u8).init(allocator);
    defer current_token.deinit();

    while (i < query_str.len) {
        const c = query_str[i];

        if (c == '"') {
            if (!in_quotes) {
                if (current_token.items.len > 0) {
                    try tokens.append(decideTokenType(try allocator.dupe(u8, current_token.items)));
                    current_token.clearRetainingCapacity();
                }
                in_quotes = true;
                token_start = i;
            } else {
                try current_token.appendSlice(query_str[token_start .. i + 1]);
                try tokens.append(Token{ .type = .value, .value = try allocator.dupe(u8, current_token.items) });
                current_token.clearRetainingCapacity();
                in_quotes = false;
            }
            i += 1;
            continue;
        }

        if (in_quotes) {
            i += 1;
            continue;
        }

        if (c == '(') {
            if (current_token.items.len > 0) {
                try tokens.append(decideTokenType(try allocator.dupe(u8, current_token.items)));
                current_token.clearRetainingCapacity();
            }
            try tokens.append(Token{ .type = .leftParen, .value = "(" });
            i += 1;
            continue;
        } else if (c == ')') {
            if (current_token.items.len > 0) {
                try tokens.append(decideTokenType(try allocator.dupe(u8, current_token.items)));
                current_token.clearRetainingCapacity();
            }
            try tokens.append(Token{ .type = .rightParen, .value = ")" });
            i += 1;
            continue;
        }

        if (std.ascii.isWhitespace(c)) {
            if (current_token.items.len > 0) {
                try tokens.append(decideTokenType(try allocator.dupe(u8, current_token.items)));
                current_token.clearRetainingCapacity();
            }
            i += 1;
            continue;
        }

        try current_token.append(c);
        i += 1;
    }

    if (current_token.items.len > 0) {
        try tokens.append(decideTokenType(try allocator.dupe(u8, current_token.items)));
    }
}

fn decideTokenType(value: []const u8) Token {
    if (std.ascii.eqlIgnoreCase(value, "AND") or
        std.ascii.eqlIgnoreCase(value, "OR") or
        std.ascii.eqlIgnoreCase(value, "NOT"))
    {
        return Token{ .type = .logicalOperator, .value = value };
    }

    if (std.mem.eql(u8, value, "eq") or
        std.mem.eql(u8, value, "ne") or
        std.mem.eql(u8, value, "gt") or
        std.mem.eql(u8, value, "lt") or
        std.mem.eql(u8, value, "ge") or
        std.mem.eql(u8, value, "le") or
        std.mem.eql(u8, value, "matches"))
    {
        return Token{ .type = .operator, .value = value };
    }

    if (std.mem.eql(u8, value, "with")) {
        return Token{ .type = .updateKeyword, .value = value };
    }

    return Token{ .type = .field, .value = value };
}

fn parseExpression(allocator: std.mem.Allocator, tokens: []Token, pos: *usize) !QueryNode {
    if (pos.* >= tokens.len) {
        return error.UnexpectedEndOfQuery;
    }

    if (pos.* + 1 < tokens.len and
        tokens[pos.*].type == .logicalOperator and
        std.ascii.eqlIgnoreCase(tokens[pos.*].value, "NOT"))
    {
        pos.* += 1;

        if (pos.* < tokens.len and tokens[pos.*].type == .leftParen) {
            pos.* += 1;
            const inner_expr = try parseExpression(allocator, tokens, pos);

            if (pos.* < tokens.len and tokens[pos.*].type == .rightParen) {
                pos.* += 1;
                return try QueryNode.notOp(allocator, inner_expr);
            } else {
                return error.MissingRightParenthesis;
            }
        } else {
            const inner_expr = try parseExpression(allocator, tokens, pos);
            return try QueryNode.notOp(allocator, inner_expr);
        }
    }

    var left_node: QueryNode = undefined;

    if (pos.* < tokens.len and tokens[pos.*].type == .leftParen) {
        pos.* += 1;
        left_node = try parseExpression(allocator, tokens, pos);

        if (pos.* < tokens.len and tokens[pos.*].type == .rightParen) {
            pos.* += 1;
        } else {
            return error.MissingRightParenthesis;
        }
    } else if (pos.* + 2 < tokens.len and
        tokens[pos.*].type == .field and
        tokens[pos.* + 1].type == .operator and
        (tokens[pos.* + 2].type == .value or tokens[pos.* + 2].type == .field))
    {
        left_node = try parseSimpleCondition(allocator, tokens[pos.*].value, tokens[pos.* + 1].value, tokens[pos.* + 2].value);
        pos.* += 3;
    } else {
        return error.InvalidQueryExpression;
    }

    if (pos.* < tokens.len and tokens[pos.*].type == .logicalOperator) {
        const op_token = tokens[pos.*];
        pos.* += 1;

        const right_node = try parseExpression(allocator, tokens, pos);

        if (std.ascii.eqlIgnoreCase(op_token.value, "AND")) {
            return try QueryNode.andOp(allocator, left_node, right_node);
        } else if (std.ascii.eqlIgnoreCase(op_token.value, "OR")) {
            return try QueryNode.orOp(allocator, left_node, right_node);
        } else {
            return error.UnsupportedLogicalOperator;
        }
    }

    return left_node;
}

fn parseSimpleCondition(allocator: std.mem.Allocator, field: []const u8, op_str: []const u8, value_str: []const u8) !QueryNode {
    const op = utils.stringToOperator(op_str) catch {
        return error.InvalidOperator;
    };

    var query = Query.init(allocator);
    var field_query = query.field(field);

    var final_value_str = value_str;
    if (final_value_str.len >= 2 and final_value_str[0] == '"' and final_value_str[final_value_str.len - 1] == '"') {
        final_value_str = final_value_str[1 .. final_value_str.len - 1];
    }

    if (op == .matches) {
        return field_query.matches(final_value_str);
    }

    if (std.fmt.parseInt(i64, final_value_str, 10)) |int_val| {
        return switch (op) {
            .eq => field_query.eq(int_val),
            .ne => field_query.ne(int_val),
            .gt => field_query.gt(int_val),
            .lt => field_query.lt(int_val),
            .ge => field_query.ge(int_val),
            .le => field_query.le(int_val),
            .matches => unreachable,
        };
    } else |_| {
        if (std.fmt.parseFloat(f64, final_value_str)) |float_val| {
            return switch (op) {
                .eq => field_query.eq(float_val),
                .ne => field_query.ne(float_val),
                .gt => field_query.gt(float_val),
                .lt => field_query.lt(float_val),
                .ge => field_query.ge(float_val),
                .le => field_query.le(float_val),
                .matches => unreachable,
            };
        } else |_| {
            return switch (op) {
                .eq => field_query.eq(final_value_str),
                .ne => field_query.ne(final_value_str),
                .matches => field_query.matches(final_value_str),
                .gt, .lt, .ge, .le => error.StringComparisonNotSupported,
            };
        }
    }
}

fn handleUpdate(
    writer: anytype,
    db: *Database,
    cmd_iter: *std.mem.SplitIterator(u8, .sequence),
    allocator: std.mem.Allocator,
) !void {
    const table_name = cmd_iter.next() orelse {
        try writer.print("Error: Missing table name\n", .{});
        return;
    };

    const table_ptr = db.table(table_name) catch {
        try writer.print("Error: Table '{s}' not found\n", .{table_name});
        return;
    };

    const id_or_query = cmd_iter.next() orelse {
        try writer.print("Error: Missing ID or query\n", .{});
        return;
    };

    const id = std.fmt.parseInt(u64, id_or_query, 10) catch null;

    if (id != null) {
        var json_string = std.ArrayList(u8).init(allocator);
        defer json_string.deinit();
        var first_part = true;
        while (cmd_iter.next()) |part| {
            if (!first_part) {
                try json_string.append(' ');
            } else {
                first_part = false;
            }
            try json_string.appendSlice(part);
        }

        if (json_string.items.len == 0) {
            try writer.print("Error: Missing JSON update data\n", .{});
            return;
        }

        table_ptr.updateById(id.?, json_string.items) catch |err| {
            switch (err) {
                error.DocumentNotFound => try writer.print("Error: Document with ID {d} not found in table '{s}'\n", .{ id.?, table_name }),
                else => {
                    const err_name = @errorName(err);
                    if (std.mem.eql(u8, err_name, "JsonParseFailed")) {
                        try writer.print("Error: Invalid JSON format for update data\n", .{});
                        try writer.print("  -> Check JSON syntax: {s}\n", .{json_string.items});
                    } else {
                        try writer.print("Error during update: {s}\n", .{err_name});
                    }
                },
            }
            return;
        };

        try writer.print("Document with ID {d} updated\n", .{id.?});
    } else {
        var query_string = std.ArrayList(u8).init(allocator);
        defer query_string.deinit();

        try query_string.appendSlice(id_or_query);

        var found_with = false;
        var current_part: ?[]const u8 = null;

        while (true) {
            current_part = cmd_iter.next();
            if (current_part == null) break;

            if (std.mem.eql(u8, current_part.?, "with")) {
                found_with = true;
                break;
            }

            try query_string.append(' ');
            try query_string.appendSlice(current_part.?);
        }

        if (!found_with) {
            try writer.print("Error: Missing 'with' keyword in query-based update\n", .{});
            try writer.print("Syntax: update <table> <query> with <json>\n", .{});
            return;
        }

        var json_string = std.ArrayList(u8).init(allocator);
        defer json_string.deinit();
        var first_part = true;

        while (cmd_iter.next()) |part| {
            if (!first_part) {
                try json_string.append(' ');
            } else {
                first_part = false;
            }
            try json_string.appendSlice(part);
        }

        if (json_string.items.len == 0) {
            try writer.print("Error: Missing JSON update data after 'with' keyword\n", .{});
            return;
        }

        var query_node = parseQuery(allocator, query_string.items) catch |err| {
            try writer.print("Error parsing query: {s}\n", .{@errorName(err)});
            return;
        };
        defer query_node.deinit();

        const updated_count = table_ptr.update(query_node, json_string.items) catch |err| {
            switch (err) {
                error.NoDocumentsMatch => try writer.print("No documents matched the query\n", .{}),
                else => {
                    const err_name = @errorName(err);
                    if (std.mem.eql(u8, err_name, "JsonParseFailed")) {
                        try writer.print("Error: Invalid JSON format for update data\n", .{});
                        try writer.print("  -> Check JSON syntax: {s}\n", .{json_string.items});
                    } else {
                        try writer.print("Error during update: {s}\n", .{err_name});
                    }
                },
            }
            return;
        };

        try writer.print("Updated {d} document(s) matching query\n", .{updated_count});
    }
}

fn handleDelete(
    writer: anytype,
    db: *Database,
    cmd_iter: *std.mem.SplitIterator(u8, .sequence),
    allocator: std.mem.Allocator,
) !void {
    const table_name = cmd_iter.next() orelse {
        try writer.print("Error: Missing table name\n", .{});
        return;
    };

    const table_ptr = db.table(table_name) catch {
        try writer.print("Error: Table '{s}' not found\n", .{table_name});
        return;
    };

    const id_or_query = cmd_iter.next() orelse {
        try writer.print("Error: Missing ID or query\n", .{});
        return;
    };

    const id = std.fmt.parseInt(u64, id_or_query, 10) catch null;

    if (id != null) {
        table_ptr.removeById(id.?) catch |err| {
            switch (err) {
                error.DocumentNotFound => try writer.print("Error: Document with ID {d} not found in table '{s}'\n", .{ id.?, table_name }),
                else => try writer.print("Error during delete: {s}\n", .{@errorName(err)}),
            }
            return;
        };

        try writer.print("Document with ID {d} deleted\n", .{id.?});
    } else {
        var query_string = std.ArrayList(u8).init(allocator);
        defer query_string.deinit();

        try query_string.appendSlice(id_or_query);

        while (cmd_iter.next()) |part| {
            try query_string.append(' ');
            try query_string.appendSlice(part);
        }

        var query_node = parseQuery(allocator, query_string.items) catch |err| {
            try writer.print("Error parsing query: {s}\n", .{@errorName(err)});
            return;
        };
        defer query_node.deinit();

        const deleted_count = table_ptr.remove(query_node) catch |err| {
            switch (err) {
                error.NoDocumentsMatch => try writer.print("No documents matched the query\n", .{}),
                error.QueryRequired => try writer.print("Error: Query is required for delete operation\n", .{}),
                else => try writer.print("Error during delete: {s}\n", .{@errorName(err)}),
            }
            return;
        };

        try writer.print("Deleted {d} document(s) matching query\n", .{deleted_count});
    }
}

fn handleUpsert(
    writer: anytype,
    db: *Database,
    cmd_iter: *std.mem.SplitIterator(u8, .sequence),
    allocator: std.mem.Allocator,
) !void {
    const table_name = cmd_iter.next() orelse {
        try writer.print("Error: Missing table name\n", .{});
        return;
    };

    const table_ptr = db.table(table_name) catch {
        try writer.print("Error: Table '{s}' not found\n", .{table_name});
        return;
    };

    var query_string = std.ArrayList(u8).init(allocator);
    defer query_string.deinit();

    var found_with = false;
    var current_part: ?[]const u8 = null;

    while (true) {
        current_part = cmd_iter.next();
        if (current_part == null) break;

        if (std.mem.eql(u8, current_part.?, "with")) {
            found_with = true;
            break;
        }

        if (query_string.items.len > 0) {
            try query_string.append(' ');
        }
        try query_string.appendSlice(current_part.?);
    }

    if (!found_with) {
        try writer.print("Error: Missing 'with' keyword in upsert command\n", .{});
        try writer.print("Syntax: upsert <table> <query> with <json>\n", .{});
        return;
    }

    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();
    var first_part = true;

    while (cmd_iter.next()) |part| {
        if (!first_part) {
            try json_string.append(' ');
        } else {
            first_part = false;
        }
        try json_string.appendSlice(part);
    }

    if (json_string.items.len == 0) {
        try writer.print("Error: Missing JSON data after 'with' keyword\n", .{});
        return;
    }

    var query_node = parseQuery(allocator, query_string.items) catch |err| {
        try writer.print("Error parsing query: {s}\n", .{@errorName(err)});
        return;
    };
    defer query_node.deinit();

    const result = table_ptr.upsert(query_node, json_string.items) catch |err| {
        const err_name = @errorName(err);
        if (std.mem.eql(u8, err_name, "JsonParseFailed")) {
            try writer.print("Error: Invalid JSON format\n", .{});
            try writer.print("  -> Check JSON syntax: {s}\n", .{json_string.items});
        } else {
            try writer.print("Error during upsert: {s}\n", .{err_name});
        }
        return;
    };

    switch (result.operation) {
        .update => try writer.print("Updated {d} document(s) matching query\n", .{result.count}),
        .insert => try writer.print("No documents matched query, inserted new document with ID: {d}\n", .{result.id.?}),
    }
}

fn listTables(writer: anytype, db: *Database) !void {
    var tables = std.ArrayList([]const u8).init(db.allocator);
    defer tables.deinit();

    var iter = db.tables.keyIterator();
    while (iter.next()) |key| {
        try tables.append(key.*);
    }

    try writer.print("Tables ({d}):\n", .{tables.items.len});
    if (tables.items.len == 0) {
        try writer.print("(No tables created yet)\n", .{});
    } else {
        for (tables.items) |table_name| {
            try writer.print("- {s}\n", .{table_name});
        }
    }
}
