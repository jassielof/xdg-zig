//! Represents a group (section) in a desktop entry file.
//! Groups are denoted by [GroupName] headers and contain key-value entries.
//! According to the spec, group names may contain all ASCII characters
//! except '[', ']', and control characters.

const std = @import("std");
const Entry = @import("DesktopEntry.zig");
const Comment = @import("DesktopComment.zig");

const Group = @This();

/// All entries in this group, preserving insertion order
entries: std.ArrayList(Entry),

/// Index mapping keys to their position in the entries list for O(1) lookup
entry_index: std.StringHashMap(usize),

/// Comments that appear in this group (preserved for spec compliance)
comments: std.ArrayList(Comment),

/// Initialize an empty group
pub fn init(allocator: std.mem.Allocator) Group {
    return .{
        .entries = .empty,
        .entry_index = std.StringHashMap(usize).init(allocator),
        .comments = .empty,
    };
}

/// Free all memory associated with this group
pub fn deinit(self: *Group, allocator: std.mem.Allocator) void {
    for (self.entries.items) |*entry| {
        entry.deinit(allocator);
    }
    self.entries.deinit(allocator);

    var it = self.entry_index.iterator();
    while (it.next()) |kv| {
        allocator.free(kv.key_ptr.*);
    }
    self.entry_index.deinit();

    for (self.comments.items) |*comment| {
        comment.deinit(allocator);
    }
    self.comments.deinit(allocator);
}

/// Add an entry to this group
/// Takes ownership of the entry
pub fn putEntry(self: *Group, allocator: std.mem.Allocator, entry: Entry) !void {
    if (self.entry_index.get(entry.key)) |existing_index| {
        self.entries.items[existing_index].deinit(allocator);
        self.entries.items[existing_index] = entry;
    } else {
        const key_copy = try allocator.dupe(u8, entry.key);
        errdefer allocator.free(key_copy);
        const index = self.entries.items.len;
        try self.entries.append(allocator, entry);
        try self.entry_index.put(key_copy, index);
    }
}

/// Get an entry by key name
pub fn getEntry(self: *const Group, key: []const u8) ?*const Entry {
    const index = self.entry_index.get(key) orelse return null;
    return &self.entries.items[index];
}

/// Get the raw value of a key
pub fn getValue(self: *const Group, key: []const u8) ?[]const u8 {
    const entry = self.getEntry(key) orelse return null;
    return entry.value;
}

/// Add a comment to this group
pub fn addComment(self: *Group, allocator: std.mem.Allocator, comment: Comment) !void {
    try self.comments.append(allocator, comment);
}
