const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("TinyDB in Zig - Work in Progress!\n", .{});
}
