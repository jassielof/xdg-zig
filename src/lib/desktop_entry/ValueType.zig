//! Value type utilities for desktop entry values.
//! Desktop entries can have different value types: string, localestring,
//! boolean, numeric, and lists of these types.

const std = @import("std");

/// Parse a boolean value (true/false)
pub fn parseBoolean(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidBoolean;
}

/// Parse a numeric value
pub fn parseNumeric(value: []const u8) !f64 {
    return std.fmt.parseFloat(f64, value) catch error.InvalidNumeric;
}

/// Parse a semicolon-separated list
pub fn parseList(allocator: std.mem.Allocator, value: []const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |item| {
            allocator.free(item);
        }
        list.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, value, ';');
    while (iter.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " \t");
        if (trimmed.len > 0) {
            const item_copy = try allocator.dupe(u8, trimmed);
            try list.append(allocator, item_copy);
        }
    }

    return list.toOwnedSlice(allocator);
}

/// Free a list returned by parseList
pub fn freeList(allocator: std.mem.Allocator, list: [][]const u8) void {
    for (list) |item| {
        allocator.free(item);
    }
    allocator.free(list);
}
