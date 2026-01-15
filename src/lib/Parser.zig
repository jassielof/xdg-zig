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
    var current_group_name: ?[]const u8 = null;
    var line_number: usize = 0;

    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        line_number += 1;

        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines
        if (trimmed.len == 0) continue;

        // Handle comments
        if (trimmed[0] == '#') {
            const comment_text = try self.allocator.dupe(u8, trimmed[1..]);
            const comment = DesktopComment.init(line_number, comment_text);

            if (current_group) |group| {
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
            current_group_name = group_name;
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

            // Validate key name
            if (!DesktopEntry.isValidKeyName(parsed.key)) {
                self.allocator.free(parsed.key);
                if (parsed.locale) |loc| self.allocator.free(loc);
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

    return file;
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

/// Validate a group name according to the specification
fn isValidGroupName(name: []const u8) bool {
    if (name.len == 0) return false;

    for (name) |c| {
        // Must not contain '[', ']', or control characters
        if (c == '[' or c == ']' or c < 0x20 or c == 0x7F) {
            return false;
        }
    }

    return true;
}
