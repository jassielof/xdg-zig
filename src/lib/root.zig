//! XDG Desktop Entry Parser Library
//!
//! A compliant parser for XDG Desktop Entry files according to the specification:
//! https://specifications.freedesktop.org/desktop-entry/latest/
//!
//! Example usage:
//! ```zig
//! const std = @import("std");
//! const xdg = @import("xdg_desktop_entry");
//!
//! var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//! defer _ = gpa.deinit();
//! const allocator = gpa.allocator();
//!
//! var parser = xdg.Parser.init(allocator);
//! var desktop_file = try parser.parseFile("app.desktop");
//! defer desktop_file.deinit();
//!
//! if (desktop_file.getDesktopEntry()) |entry| {
//!     if (entry.getValue("Name")) |name| {
//!         std.debug.print("App name: {s}\n", .{name});
//!     }
//! }
//! ```

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

test "library imports" {
    // const testing = std.testing;
    _ = Parser;
    _ = DesktopFile;
    _ = DesktopGroup;
    _ = DesktopEntry;
    _ = DesktopComment;
    _ = ValueType;
    _ = errors;
}

test "basic parsing" {
    const allocator = std.testing.allocator;

    const content =
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Test App
        \\Exec=test-app
        \\
    ;

    var desktop_file = try parseString(allocator, content);
    defer desktop_file.deinit();

    const entry = desktop_file.getDesktopEntry().?;
    try std.testing.expectEqualStrings("Application", entry.getValue("Type").?);
    try std.testing.expectEqualStrings("Test App", entry.getValue("Name").?);
    try std.testing.expectEqualStrings("test-app", entry.getValue("Exec").?);
}
