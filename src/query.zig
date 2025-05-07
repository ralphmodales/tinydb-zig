const std = @import("std");
const Document = @import("document").Document;

pub const Operator = enum {
    eq, // ==
    ne, // !=
    gt, // >
    lt, // <
    ge, // >=
    le, // <=
};

pub const LogicalOperator = enum {
    logical_and,
    logical_or,
    logical_not,
};

pub const Condition = struct {
    field: []const u8,
    operator: Operator,
    value: std.json.Value,

    pub fn evaluate(self: Condition, doc: Document) bool {
        const field_value = doc.get(self.field) orelse return false;
        return switch (self.operator) {
            .eq => compareValues(field_value, self.value, eqlValues),
            .ne => !compareValues(field_value, self.value, eqlValues),
            .gt => compareValues(field_value, self.value, gt),
            .lt => compareValues(field_value, self.value, lt),
            .ge => compareValues(field_value, self.value, ge),
            .le => compareValues(field_value, self.value, le),
        };
    }

    fn eqlValues(a: std.json.Value, b: std.json.Value) bool {
        return switch (a) {
            .integer => |x| switch (b) {
                .integer => |y| x == y,
                .float => |y| @as(f64, @floatFromInt(x)) == y,
                else => false,
            },
            .float => |x| switch (b) {
                .float => |y| x == y,
                .integer => |y| x == @as(f64, @floatFromInt(y)),
                else => false,
            },
            .string => |x| if (b == .string) std.mem.eql(u8, x, b.string) else false,
            .bool => |x| if (b == .bool) x == b.bool else false,
            else => false,
        };
    }

    fn compareValues(a: std.json.Value, b: std.json.Value, comptime cmp: fn (a: std.json.Value, b: std.json.Value) bool) bool {
        return switch (a) {
            .integer => |x| switch (b) {
                .integer => |y| cmp(std.json.Value{ .integer = x }, std.json.Value{ .integer = y }),
                .float => |y| cmp(std.json.Value{ .float = @floatFromInt(x) }, std.json.Value{ .float = y }),
                else => false,
            },
            .float => |x| switch (b) {
                .float => |y| cmp(std.json.Value{ .float = x }, std.json.Value{ .float = y }),
                .integer => |y| cmp(std.json.Value{ .float = x }, std.json.Value{ .float = @floatFromInt(y) }),
                else => false,
            },
            .string => |x| if (b == .string) cmp(std.json.Value{ .string = x }, b) else false,
            .bool => |x| if (b == .bool) cmp(std.json.Value{ .bool = x }, b) else false,
            else => false,
        };
    }

    fn gt(a: std.json.Value, b: std.json.Value) bool {
        return switch (a) {
            .integer => |x| switch (b) {
                .integer => |y| x > y,
                else => false,
            },
            .float => |x| switch (b) {
                .float => |y| x > y,
                else => false,
            },
            else => false,
        };
    }

    fn lt(a: std.json.Value, b: std.json.Value) bool {
        return switch (a) {
            .integer => |x| switch (b) {
                .integer => |y| x < y,
                else => false,
            },
            .float => |x| switch (b) {
                .float => |y| x < y,
                else => false,
            },
            else => false,
        };
    }

    fn ge(a: std.json.Value, b: std.json.Value) bool {
        return switch (a) {
            .integer => |x| switch (b) {
                .integer => |y| x >= y,
                else => false,
            },
            .float => |x| switch (b) {
                .float => |y| x >= y,
                else => false,
            },
            else => false,
        };
    }

    fn le(a: std.json.Value, b: std.json.Value) bool {
        return switch (a) {
            .integer => |x| switch (b) {
                .integer => |y| x <= y,
                else => false,
            },
            .float => |x| switch (b) {
                .float => |y| x <= y,
                else => false,
            },
            else => false,
        };
    }
};

pub const QueryNode = union(enum) {
    condition: Condition,
    logical: LogicalExpression,

    pub fn evaluate(self: QueryNode, doc: Document) bool {
        return switch (self) {
            .condition => |cond| cond.evaluate(doc),
            .logical => |expr| expr.evaluate(doc),
        };
    }

    pub fn andOp(allocator: std.mem.Allocator, left: QueryNode, right: QueryNode) !QueryNode {
        var children = std.ArrayList(QueryNode).init(allocator);
        try children.append(left);
        try children.append(right);

        return QueryNode{
            .logical = LogicalExpression{
                .operator = .logical_and,
                .children = children,
                .allocator = allocator,
            },
        };
    }

    pub fn orOp(allocator: std.mem.Allocator, left: QueryNode, right: QueryNode) !QueryNode {
        var children = std.ArrayList(QueryNode).init(allocator);
        try children.append(left);
        try children.append(right);

        return QueryNode{
            .logical = LogicalExpression{
                .operator = .logical_or,
                .children = children,
                .allocator = allocator,
            },
        };
    }

    pub fn notOp(allocator: std.mem.Allocator, child: QueryNode) !QueryNode {
        var children = std.ArrayList(QueryNode).init(allocator);
        try children.append(child);

        return QueryNode{
            .logical = LogicalExpression{
                .operator = .logical_not,
                .children = children,
                .allocator = allocator,
            },
        };
    }

    pub fn deinit(self: *QueryNode) void {
        switch (self.*) {
            .logical => |*expr| expr.deinit(),
            else => {},
        }
    }
};

pub const LogicalExpression = struct {
    operator: LogicalOperator,
    children: std.ArrayList(QueryNode),
    allocator: std.mem.Allocator,

    pub fn evaluate(self: LogicalExpression, doc: Document) bool {
        switch (self.operator) {
            .logical_and => {
                for (self.children.items) |child| {
                    if (!child.evaluate(doc)) return false;
                }
                return true;
            },
            .logical_or => {
                for (self.children.items) |child| {
                    if (child.evaluate(doc)) return true;
                }
                return false;
            },
            .logical_not => {
                if (self.children.items.len == 0) return true;
                return !self.children.items[0].evaluate(doc);
            },
        }
    }

    pub fn deinit(self: *LogicalExpression) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit();
    }
};

pub const Query = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Query {
        return Query{ .allocator = allocator };
    }

    pub fn field(self: Query, name: []const u8) FieldQuery {
        return FieldQuery{ .query = self, .field = name };
    }
};

pub const FieldQuery = struct {
    query: Query,
    field: []const u8,

    pub fn eq(self: FieldQuery, value: anytype) QueryNode {
        return QueryNode{ .condition = Condition{
            .field = self.field,
            .operator = .eq,
            .value = jsonValue(value),
        } };
    }

    pub fn ne(self: FieldQuery, value: anytype) QueryNode {
        return QueryNode{ .condition = Condition{
            .field = self.field,
            .operator = .ne,
            .value = jsonValue(value),
        } };
    }

    pub fn gt(self: FieldQuery, value: anytype) QueryNode {
        return QueryNode{ .condition = Condition{
            .field = self.field,
            .operator = .gt,
            .value = jsonValue(value),
        } };
    }

    pub fn lt(self: FieldQuery, value: anytype) QueryNode {
        return QueryNode{ .condition = Condition{
            .field = self.field,
            .operator = .lt,
            .value = jsonValue(value),
        } };
    }

    pub fn ge(self: FieldQuery, value: anytype) QueryNode {
        return QueryNode{ .condition = Condition{
            .field = self.field,
            .operator = .ge,
            .value = jsonValue(value),
        } };
    }

    pub fn le(self: FieldQuery, value: anytype) QueryNode {
        return QueryNode{ .condition = Condition{
            .field = self.field,
            .operator = .le,
            .value = jsonValue(value),
        } };
    }
};

fn jsonValue(value: anytype) std.json.Value {
    return switch (@TypeOf(value)) {
        i64, u64, i32, u32, i16, u16, i8, u8 => std.json.Value{ .integer = @intCast(value) },
        f64, f32 => std.json.Value{ .float = @floatCast(value) },
        bool => std.json.Value{ .bool = value },
        []const u8 => std.json.Value{ .string = value },
        else => std.json.Value{ .null = {} },
    };
}
