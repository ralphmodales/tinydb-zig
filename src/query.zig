const std = @import("std");
const Document = @import("document").Document;

pub const Operator = enum {
    eq, // ==
    gt, // >
    lt, // <
    ge, // >=
    le, // <=
};

pub const Condition = struct {
    field: []const u8,
    operator: Operator,
    value: std.json.Value,

    pub fn evaluate(self: Condition, doc: Document) bool {
        const field_value = doc.get(self.field) orelse return false;
        return switch (self.operator) {
            .eq => compareValues(field_value, self.value, eqlValues),
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

    pub fn eq(self: FieldQuery, value: anytype) Condition {
        return Condition{
            .field = self.field,
            .operator = .eq,
            .value = jsonValue(value),
        };
    }

    pub fn gt(self: FieldQuery, value: anytype) Condition {
        return Condition{
            .field = self.field,
            .operator = .gt,
            .value = jsonValue(value),
        };
    }

    pub fn lt(self: FieldQuery, value: anytype) Condition {
        return Condition{
            .field = self.field,
            .operator = .lt,
            .value = jsonValue(value),
        };
    }

    pub fn ge(self: FieldQuery, value: anytype) Condition {
        return Condition{
            .field = self.field,
            .operator = .ge,
            .value = jsonValue(value),
        };
    }

    pub fn le(self: FieldQuery, value: anytype) Condition {
        return Condition{
            .field = self.field,
            .operator = .le,
            .value = jsonValue(value),
        };
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
