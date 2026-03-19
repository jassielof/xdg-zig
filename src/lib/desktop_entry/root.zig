//! XDG Desktop Entry Parser Library
//!
//! A compliant parser for XDG Desktop Entry files according to the specification: https://specifications.freedesktop.org/desktop-entry/latest/

const std = @import("std");

// Core types
pub const Parser = @import("Parser.zig");
pub const DesktopFile = @import("DesktopFile.zig");
pub const DesktopGroup = @import("DesktopGroup.zig");
pub const DesktopEntry = @import("DesktopEntry.zig");
pub const DesktopComment = @import("DesktopComment.zig");
pub const ValueType = @import("ValueType.zig");
pub const errors = @import("errors.zig");

// Re-export common error types
pub const ParseError = errors.ParseError;

/// Parse a desktop entry file from a file path
/// Convenience function that creates a parser and parses the file
pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !DesktopFile {
    var parser = Parser.init(allocator);
    return try parser.parseFile(path);
}

/// Parse a desktop entry file from a string
/// Convenience function that creates a parser and parses the content
pub fn parseString(allocator: std.mem.Allocator, content: []const u8) !DesktopFile {
    var parser = Parser.init(allocator);
    return try parser.parse(content);
}

test parseString {
    const allocator = std.testing.allocator;

    const content =
        \\# Sample desktop entry
        \\[Desktop Entry]
        \\Name=Sample App
        \\Exec=sample-app
        \\Type=Application
        \\
    ;

    var desktop_file = try parseString(allocator, content);
    defer desktop_file.deinit();

    try std.testing.expect(desktop_file.groups.len == 1);
    const group = desktop_file.groups[0];
    try std.testing.expect(std.mem.eql(u8, group.name, "Desktop Entry"));
    try std.testing.expect(group.entries.len == 3);
    try std.testing.expect(std.mem.eql(u8, group.entries[0].name, "Name"));
    try std.testing.expect(std.mem.eql(u8, group.entries[0].value, "Sample App"));
    try std.testing.expect(std.mem.eql(u8, group.entries[1].name, "Exec"));
    try std.testing.expect(std.mem.eql(u8, group.entries[1].value, "sample-app"));
}
