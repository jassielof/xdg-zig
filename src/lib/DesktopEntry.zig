//! Represents a single key-value entry in a desktop entry file.
//! Keys can only contain A-Za-z0-9- characters and are case-sensitive.
//! Keys can have locale suffixes like Key[locale]=value.

const std = @import("std");

const DesktopEntry = @This();

/// The key name (without locale suffix)
key: []const u8,

/// The raw value string
value: []const u8,

/// Optional locale suffix (e.g., "es" for Key[es])
locale: ?[]const u8,

/// Initialize an entry with required fields
pub fn init(key: []const u8, value: []const u8, locale: ?[]const u8) DesktopEntry {
    return .{
        .key = key,
        .value = value,
        .locale = locale,
    };
}

/// Free memory associated with this entry
pub fn deinit(self: *DesktopEntry, allocator: std.mem.Allocator) void {
    allocator.free(self.key);
    allocator.free(self.value);
    if (self.locale) |loc| {
        allocator.free(loc);
    }
}

/// Parse a key that may contain a locale suffix
/// Returns the base key and optional locale
pub fn parseKeyWithLocale(allocator: std.mem.Allocator, full_key: []const u8) !struct { key: []const u8, locale: ?[]const u8 } {
    if (std.mem.indexOfScalar(u8, full_key, '[')) |start| {
        if (std.mem.indexOfScalar(u8, full_key, ']')) |end| {
            if (end > start + 1 and end == full_key.len - 1) {
                const key = try allocator.dupe(u8, full_key[0..start]);
                const locale = try allocator.dupe(u8, full_key[start + 1 .. end]);
                return .{ .key = key, .locale = locale };
            }
        }
    }

    const key = try allocator.dupe(u8, full_key);
    return .{ .key = key, .locale = null };
}

/// Validate that a key name only contains allowed characters
pub fn isValidKeyName(key: []const u8) bool {
    if (key.len == 0) return false;

    for (key) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-';
        if (!valid) return false;
    }

    return true;
}

/// Unescape a value string according to the desktop entry specification
/// Handles: \s (space), \n (newline), \t (tab), \r (carriage return), \\ (backslash)
pub fn unescapeValue(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < value.len) {
        if (value[i] == '\\' and i + 1 < value.len) {
            const next = value[i + 1];
            const unescaped: u8 = switch (next) {
                's' => ' ',
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                else => {
                    try result.append(allocator, '\\');
                    try result.append(allocator, next);
                    i += 2;
                    continue;
                },
            };
            try result.append(allocator, unescaped);
            i += 2;
        } else {
            try result.append(allocator, value[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}
