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

/// Parse a semicolon-separated list.
/// Per the spec, list values end with a trailing semicolon; empty items
/// (produced by consecutive semicolons or a leading semicolon) are ignored.
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

// ── Unit tests ────────────────────────────────────────────────────────────────

test "parseBoolean: true and false" {
    try std.testing.expect(try parseBoolean("true") == true);
    try std.testing.expect(try parseBoolean("false") == false);
}

test "parseBoolean: invalid values return error" {
    try std.testing.expectError(error.InvalidBoolean, parseBoolean("1"));
    try std.testing.expectError(error.InvalidBoolean, parseBoolean("yes"));
    try std.testing.expectError(error.InvalidBoolean, parseBoolean("True"));
    try std.testing.expectError(error.InvalidBoolean, parseBoolean(""));
}

test "parseNumeric: valid floats" {
    try std.testing.expectApproxEqAbs(1.0, try parseNumeric("1.0"), 1e-9);
    try std.testing.expectApproxEqAbs(3.14, try parseNumeric("3.14"), 1e-9);
    try std.testing.expectApproxEqAbs(0.0, try parseNumeric("0"), 1e-9);
    try std.testing.expectApproxEqAbs(-2.5, try parseNumeric("-2.5"), 1e-9);
}

test "parseNumeric: invalid values return error" {
    try std.testing.expectError(error.InvalidNumeric, parseNumeric("abc"));
    try std.testing.expectError(error.InvalidNumeric, parseNumeric(""));
}

test "parseList: semicolon-separated values" {
    const allocator = std.testing.allocator;
    const list = try parseList(allocator, "Application;Utility;System;");
    defer freeList(allocator, list);
    try std.testing.expectEqual(@as(usize, 3), list.len);
    try std.testing.expectEqualStrings("Application", list[0]);
    try std.testing.expectEqualStrings("Utility", list[1]);
    try std.testing.expectEqualStrings("System", list[2]);
}

test "parseList: trailing semicolon does not create empty entry" {
    const allocator = std.testing.allocator;
    const list = try parseList(allocator, "image/x-foo;");
    defer freeList(allocator, list);
    try std.testing.expectEqual(@as(usize, 1), list.len);
    try std.testing.expectEqualStrings("image/x-foo", list[0]);
}

test "parseList: single item without trailing semicolon" {
    const allocator = std.testing.allocator;
    const list = try parseList(allocator, "OnlyOne");
    defer freeList(allocator, list);
    try std.testing.expectEqual(@as(usize, 1), list.len);
    try std.testing.expectEqualStrings("OnlyOne", list[0]);
}

test "parseList: empty string returns empty list" {
    const allocator = std.testing.allocator;
    const list = try parseList(allocator, "");
    defer freeList(allocator, list);
    try std.testing.expectEqual(@as(usize, 0), list.len);
}
