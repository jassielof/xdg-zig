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

/// Parse a key that may contain a locale suffix.
/// Returns the base key and optional locale.
/// Examples:
///   "Name"       → { key: "Name", locale: null }
///   "Name[es]"   → { key: "Name", locale: "es" }
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

/// Validate that a key name only contains allowed characters: A-Za-z0-9-
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

/// Unescape a value string according to the desktop entry specification.
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

// ── Unit tests ────────────────────────────────────────────────────────────────

test "isValidKeyName: valid keys" {
    try std.testing.expect(isValidKeyName("Name"));
    try std.testing.expect(isValidKeyName("GenericName"));
    try std.testing.expect(isValidKeyName("X-My-Extension"));
    try std.testing.expect(isValidKeyName("DBusActivatable"));
    try std.testing.expect(isValidKeyName("Key123"));
}

test "isValidKeyName: invalid keys" {
    try std.testing.expect(!isValidKeyName(""));
    try std.testing.expect(!isValidKeyName("Key Name"));  // space
    try std.testing.expect(!isValidKeyName("Key.Dot"));   // dot
    try std.testing.expect(!isValidKeyName("Key@"));      // symbol
    try std.testing.expect(!isValidKeyName("Ключ"));      // non-ASCII
}

test "parseKeyWithLocale: plain key" {
    const allocator = std.testing.allocator;
    const result = try parseKeyWithLocale(allocator, "Name");
    defer allocator.free(result.key);
    try std.testing.expectEqualStrings("Name", result.key);
    try std.testing.expect(result.locale == null);
}

test "parseKeyWithLocale: key with locale" {
    const allocator = std.testing.allocator;
    const result = try parseKeyWithLocale(allocator, "Name[es]");
    defer allocator.free(result.key);
    defer allocator.free(result.locale.?);
    try std.testing.expectEqualStrings("Name", result.key);
    try std.testing.expectEqualStrings("es", result.locale.?);
}

test "parseKeyWithLocale: key with long locale tag" {
    const allocator = std.testing.allocator;
    const result = try parseKeyWithLocale(allocator, "Name[zh_CN]");
    defer allocator.free(result.key);
    defer allocator.free(result.locale.?);
    try std.testing.expectEqualStrings("Name", result.key);
    try std.testing.expectEqualStrings("zh_CN", result.locale.?);
}

test "unescapeValue: no escapes" {
    const allocator = std.testing.allocator;
    const result = try unescapeValue(allocator, "Hello World");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

test "unescapeValue: standard escape sequences" {
    const allocator = std.testing.allocator;
    const result = try unescapeValue(allocator, "a\\nb\\tc\\sd\\\\e");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a\nb\tc d\\e", result);
}

test "unescapeValue: backslash at end (unknown escape passthrough)" {
    const allocator = std.testing.allocator;
    const result = try unescapeValue(allocator, "foo\\x");
    defer allocator.free(result);
    // Unknown escape sequences are passed through unchanged
    try std.testing.expectEqualStrings("foo\\x", result);
}
