//! Represents a comment line in a desktop entry file.
//! According to the spec, comments begin with '#' and should be preserved
//! across reads and writes of the file.

const std = @import("std");

const DesktopComment = @This();

/// The line number where this comment appears
line_number: usize,

/// The comment text (without the leading '#')
text: []const u8,

/// Initialize a comment
pub fn init(line_number: usize, text: []const u8) DesktopComment {
    return .{
        .line_number = line_number,
        .text = text,
    };
}

/// Free memory associated with this comment
pub fn deinit(self: *DesktopComment, allocator: std.mem.Allocator) void {
    allocator.free(self.text);
}
