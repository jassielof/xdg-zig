//! Parser for XDG desktop entry files.
//! Implements the specification at:
//! https://specifications.freedesktop.org/desktop-entry/latest/

const std = @import("std");
const DesktopFile = @import("DesktopFile.zig");
const DesktopGroup = @import("DesktopGroup.zig");
const DesktopEntry = @import("DesktopEntry.zig");
const DesktopComment = @import("DesktopComment.zig");
const errors = @import("errors.zig");

const Parser = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Parser {
    return .{ .allocator = allocator };
}

/// Parse a desktop entry file from a string
pub fn parse(self: *Parser, content: []const u8) !DesktopFile {
    var file = DesktopFile.init(self.allocator);
    errdefer file.deinit();

    var current_group: ?*DesktopGroup = null;
    var line_number: usize = 0;

    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        line_number += 1;

        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines
        if (trimmed.len == 0) continue;

        // Handle comments — only store them if we're inside a group;
        // pre-file-header comments are spec-legal but we don't track them.
        if (trimmed[0] == '#') {
            if (current_group) |group| {
                const comment_text = try self.allocator.dupe(u8, trimmed[1..]);
                const comment = DesktopComment.init(line_number, comment_text);
                try group.addComment(self.allocator, comment);
            }
            continue;
        }

        // Handle group headers [GroupName]
        if (trimmed[0] == '[') {
            if (trimmed.len < 3 or trimmed[trimmed.len - 1] != ']') {
                return errors.ParseError.InvalidGroupHeader;
            }

            const group_name = trimmed[1 .. trimmed.len - 1];

            // Validate group name
            if (!isValidGroupName(group_name)) {
                return errors.ParseError.InvalidGroupName;
            }

            // Check for duplicate groups
            if (file.getGroup(group_name)) |_| {
                return errors.ParseError.DuplicateGroup;
            }

            const new_group = DesktopGroup.init(self.allocator);
            try file.putGroup(group_name, new_group);
            current_group = file.groups.getPtr(group_name);

            continue;
        }

        // Handle key-value pairs
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |equals_pos| {
            if (current_group == null) {
                return errors.ParseError.EntryBeforeGroup;
            }

            const key_part = std.mem.trim(u8, trimmed[0..equals_pos], " \t");
            const value_part = std.mem.trim(u8, trimmed[equals_pos + 1 ..], " \t");

            if (key_part.len == 0) {
                return errors.ParseError.EmptyKey;
            }

            // Parse key with possible locale
            const parsed = try DesktopEntry.parseKeyWithLocale(self.allocator, key_part);
            errdefer {
                self.allocator.free(parsed.key);
                if (parsed.locale) |loc| self.allocator.free(loc);
            }

            // Validate key name — errdefer already owns parsed.key / locale,
            // so just return the error and let it clean up.
            if (!DesktopEntry.isValidKeyName(parsed.key)) {
                return errors.ParseError.InvalidKeyName;
            }

            const value_copy = try self.allocator.dupe(u8, value_part);

            const entry = DesktopEntry.init(parsed.key, value_copy, parsed.locale);
            try current_group.?.putEntry(self.allocator, entry);

            continue;
        }

        // Invalid line
        return errors.ParseError.InvalidLine;
    }

    // Verify that the required [Desktop Entry] group exists
    if (file.getDesktopEntry() == null) {
        return errors.ParseError.MissingDesktopEntryGroup;
    }

    // Semantic validation against the [Desktop Entry] group
    try validateSemantics(&file);

    return file;
}

/// Semantic validation of the parsed [Desktop Entry] group.
/// Called after successful syntax parsing.
fn validateSemantics(file: *DesktopFile) !void {
    const de = file.getDesktopEntry().?;

    // Name is always required
    if (de.getValue("Name") == null) {
        return errors.ParseError.MissingRequiredKey;
    }

    // Type is always required
    const type_value = de.getValue("Type") orelse {
        return errors.ParseError.MissingRequiredKey;
    };

    // Type must be one of the three spec-defined values
    const valid_types = [_][]const u8{ "Application", "Link", "Directory" };
    const type_is_valid = for (valid_types) |vt| {
        if (std.mem.eql(u8, type_value, vt)) break true;
    } else false;

    if (!type_is_valid) {
        return errors.ParseError.InvalidTypeValue;
    }

    // Application requires Exec OR DBusActivatable=true
    if (std.mem.eql(u8, type_value, "Application")) {
        const has_exec = de.getValue("Exec") != null;
        const dbus_val = de.getValue("DBusActivatable");
        const has_dbus = dbus_val != null and std.mem.eql(u8, dbus_val.?, "true");
        if (!has_exec and !has_dbus) {
            return errors.ParseError.MissingExecForApplication;
        }
    }

    // Link requires URL
    if (std.mem.eql(u8, type_value, "Link")) {
        if (de.getValue("URL") == null) {
            return errors.ParseError.MissingUrlForLink;
        }
    }
}

/// Parse a desktop entry file from a file path
pub fn parseFile(self: *Parser, path: []const u8) !DesktopFile {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
    defer self.allocator.free(content);

    // Validate UTF-8
    if (!std.unicode.utf8ValidateSlice(content)) {
        return errors.ParseError.InvalidUtf8;
    }

    return try self.parse(content);
}

/// Validate a group name according to the specification.
/// Names may contain any characters except '[', ']', and control characters.
fn isValidGroupName(name: []const u8) bool {
    if (name.len == 0) return false;

    for (name) |c| {
        if (c == '[' or c == ']' or c < 0x20 or c == 0x7F) {
            return false;
        }
    }

    return true;
}

// ── Unit tests ────────────────────────────────────────────────────────────────

test "parse: valid minimal application" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    var f = try p.parse("[Desktop Entry]\nType=Application\nName=Test\nExec=test\n");
    defer f.deinit();
    const de = f.getDesktopEntry().?;
    try std.testing.expectEqualStrings("Application", de.getValue("Type").?);
    try std.testing.expectEqualStrings("Test", de.getValue("Name").?);
}

test "parse: Directory type (no Exec required)" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    var f = try p.parse("[Desktop Entry]\nType=Directory\nName=My Dir\n");
    defer f.deinit();
    const de = f.getDesktopEntry().?;
    try std.testing.expectEqualStrings("Directory", de.getValue("Type").?);
}

test "parse: Link type with URL" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    var f = try p.parse("[Desktop Entry]\nType=Link\nName=My Link\nURL=https://example.com\n");
    defer f.deinit();
    const de = f.getDesktopEntry().?;
    try std.testing.expectEqualStrings("Link", de.getValue("Type").?);
    try std.testing.expectEqualStrings("https://example.com", de.getValue("URL").?);
}

test "parse: extra groups are allowed" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    var f = try p.parse("[Desktop Entry]\nType=Application\nName=App\nExec=app\n\n[Desktop Action edit]\nName=Edit\nExec=app --edit\n");
    defer f.deinit();
    try std.testing.expect(f.hasGroup("Desktop Action edit"));
}

test "parse: localized keys are accepted" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    var f = try p.parse("[Desktop Entry]\nType=Application\nName=App\nName[de]=Anwendung\nExec=app\n");
    defer f.deinit();
    const de = f.getDesktopEntry().?;
    try std.testing.expectEqualStrings("App", de.getValue("Name").?);
}

test "parse error: missing [Desktop Entry] group" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[SomeOtherGroup]\nKey=Value\n");
    try std.testing.expectError(errors.ParseError.MissingDesktopEntryGroup, result);
}

test "parse error: missing Name key" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[Desktop Entry]\nType=Application\nExec=app\n");
    try std.testing.expectError(errors.ParseError.MissingRequiredKey, result);
}

test "parse error: missing Type key" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[Desktop Entry]\nName=App\nExec=app\n");
    try std.testing.expectError(errors.ParseError.MissingRequiredKey, result);
}

test "parse error: invalid Type value" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[Desktop Entry]\nName=App\nType=UnknownType\nExec=app\n");
    try std.testing.expectError(errors.ParseError.InvalidTypeValue, result);
}

test "parse error: Application without Exec" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[Desktop Entry]\nName=App\nType=Application\n");
    try std.testing.expectError(errors.ParseError.MissingExecForApplication, result);
}

test "parse error: Link without URL" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[Desktop Entry]\nName=MyLink\nType=Link\n");
    try std.testing.expectError(errors.ParseError.MissingUrlForLink, result);
}

test "parse error: duplicate group" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[Desktop Entry]\nType=Application\nName=App\nExec=app\n\n[Desktop Entry]\nKey=Value\n");
    try std.testing.expectError(errors.ParseError.DuplicateGroup, result);
}

test "parse error: invalid group header (no closing bracket)" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[Desktop Entry]\nType=Application\nName=App\nExec=app\n\n[No Closing Bracket\nKey=Value\n");
    try std.testing.expectError(errors.ParseError.InvalidGroupHeader, result);
}

test "parse error: invalid key name (spaces not allowed)" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[Desktop Entry]\nType=Application\nName=App\nExec=app\nInvalid Key=value\n");
    try std.testing.expectError(errors.ParseError.InvalidKeyName, result);
}

test "parse error: invalid line (no equals sign)" {
    const allocator = std.testing.allocator;
    var p = Parser.init(allocator);
    const result = p.parse("[Desktop Entry]\nType=Application\nName=App\nExec=app\nThis line has no equals sign\n");
    try std.testing.expectError(errors.ParseError.InvalidLine, result);
}
