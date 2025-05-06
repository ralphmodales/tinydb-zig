const std = @import("std");
const Database = @import("database").Database;
const Query = @import("query").Query;
const Condition = @import("query").Condition;
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
            _ = try db.table(table_name);
            try stdout.print("Table '{s}' created\n", .{table_name});
        } else if (std.mem.eql(u8, cmd, "insert")) {
            try handleInsert(stdout, &db, &cmd_iter, allocator);
        } else if (std.mem.eql(u8, cmd, "find")) {
            try handleFind(stdout, &db, &cmd_iter, allocator);
        } else if (std.mem.eql(u8, cmd, "update")) {
            try handleUpdate(stdout, &db, &cmd_iter, allocator);
        } else if (std.mem.eql(u8, cmd, "delete")) {
            try handleDelete(stdout, &db, &cmd_iter);
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
        \\  help                         - Show this help message
        \\  create <table>               - Create a new table
        \\  insert <table> <json>        - Insert a new document into table
        \\  find <table> [field op value] - Find documents in table with optional condition
        \\  update <table> <id> <json>   - Update document by ID
        \\  delete <table> <id>          - Delete document by ID
        \\  list tables                  - List all tables
        \\  list <table>                 - List all documents in table
        \\  exit, quit                   - Exit the program
        \\
        \\Operators (for find):
        \\  eq, gt, lt, ge, le           - Equal, Greater Than, Less Than, Greater/Equal, Less/Equal
        \\
        \\Examples:
        \\  create users
        \\  insert users {{"name":"John","age":30}}
        \\  find users age gt 25
        \\  find users name eq "John"
        \\  update users 1 {{"name":"John","age":31}}
        \\  delete users 1
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

    const field_maybe = cmd_iter.next();

    if (field_maybe == null) {
        const docs = try table_ptr.search(null);
        try writer.print("Found {d} documents in table '{s}':\n", .{ docs.len, table_name });
        for (docs) |doc| {
            try writer.print("ID: {?d} - ", .{doc.id});
            try doc.toJson(writer);
            try writer.print("\n", .{});
        }
        return;
    }

    const field: []const u8 = field_maybe.?;

    const op_str = cmd_iter.next() orelse {
        try writer.print("Error: Missing operator after field '{s}'\n", .{field});
        return;
    };

    const value_str = cmd_iter.next() orelse {
        try writer.print("Error: Missing value after operator '{s}'\n", .{op_str});
        return;
    };

    var remaining_value_parts = std.ArrayList(u8).init(allocator);
    defer remaining_value_parts.deinit();
    while (cmd_iter.next()) |part| {
        try remaining_value_parts.appendSlice(" ");
        try remaining_value_parts.appendSlice(part);
    }

    var full_value_str_list = std.ArrayList(u8).init(allocator);
    defer full_value_str_list.deinit();
    try full_value_str_list.appendSlice(value_str);
    try full_value_str_list.appendSlice(remaining_value_parts.items);
    const final_value_str = full_value_str_list.items;

    const op = utils.stringToOperator(op_str) catch {
        try writer.print("Error: Invalid operator '{s}'\n", .{op_str});
        try writer.print("Valid operators: eq, gt, lt, ge, le\n", .{});
        return;
    };

    var query = Query.init(allocator);
    var field_query = query.field(field);

    var condition: Condition = undefined;

    if (std.fmt.parseInt(i64, final_value_str, 10)) |int_val| {
        condition = switch (op) {
            .eq => field_query.eq(int_val),
            .gt => field_query.gt(int_val),
            .lt => field_query.lt(int_val),
            .ge => field_query.ge(int_val),
            .le => field_query.le(int_val),
        };
    } else |_| {
        if (std.fmt.parseFloat(f64, final_value_str)) |float_val| {
            condition = switch (op) {
                .eq => field_query.eq(float_val),
                .gt => field_query.gt(float_val),
                .lt => field_query.lt(float_val),
                .ge => field_query.ge(float_val),
                .le => field_query.le(float_val),
            };
        } else |_| {
            var final_str_val = final_value_str;
            if (final_str_val.len >= 2 and final_str_val[0] == '"' and final_str_val[final_str_val.len - 1] == '"') {
                final_str_val = final_str_val[1 .. final_str_val.len - 1];
            }
            condition = switch (op) {
                .eq => field_query.eq(final_str_val),
                else => {
                    try writer.print("Error: Operator '{s}' not supported for string comparison (only 'eq')\n", .{op_str});
                    return;
                },
            };
        }
    }

    const docs = try table_ptr.search(condition);
    try writer.print("Found {d} documents in table '{s}' matching condition:\n", .{ docs.len, table_name });
    for (docs) |doc| {
        try writer.print("ID: {?d} - ", .{doc.id});
        try doc.toJson(writer);
        try writer.print("\n", .{});
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

    const id_str = cmd_iter.next() orelse {
        try writer.print("Error: Missing ID\n", .{});
        return;
    };

    const id = std.fmt.parseInt(u64, id_str, 10) catch {
        try writer.print("Error: Invalid ID '{s}'\n", .{id_str});
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
        try writer.print("Error: Missing JSON update data\n", .{});
        return;
    }

    const table_ptr = db.table(table_name) catch {
        try writer.print("Error: Table '{s}' not found\n", .{table_name});
        return;
    };

    table_ptr.update(id, json_string.items) catch |err| {
        switch (err) {
            error.DocumentNotFound => try writer.print("Error: Document with ID {d} not found in table '{s}'\n", .{ id, table_name }),
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

    try writer.print("Document with ID {d} updated\n", .{id});
}

fn handleDelete(
    writer: anytype,
    db: *Database,
    cmd_iter: *std.mem.SplitIterator(u8, .sequence),
) !void {
    const table_name = cmd_iter.next() orelse {
        try writer.print("Error: Missing table name\n", .{});
        return;
    };

    const id_str = cmd_iter.next() orelse {
        try writer.print("Error: Missing ID\n", .{});
        return;
    };

    const id = std.fmt.parseInt(u64, id_str, 10) catch {
        try writer.print("Error: Invalid ID '{s}'\n", .{id_str});
        return;
    };

    const table_ptr = db.table(table_name) catch {
        try writer.print("Error: Table '{s}' not found\n", .{table_name});
        return;
    };

    table_ptr.remove(id) catch |err| {
        switch (err) {
            error.DocumentNotFound => try writer.print("Error: Document with ID {d} not found in table '{s}'\n", .{ id, table_name }),
            else => try writer.print("Error during delete: {s}\n", .{@errorName(err)}),
        }
        return;
    };

    try writer.print("Document with ID {d} deleted\n", .{id});
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
