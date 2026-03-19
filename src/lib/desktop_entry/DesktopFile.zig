//! Top-level representation of a parsed XDG desktop entry file.
//! According to the specification, desktop entry files contain groups (sections)
//! with key-value pairs. The most important group is [Desktop Entry].

const std = @import("std");
const DesktopGroup = @import("DesktopGroup.zig");

const DesktopFile = @This();

/// All groups in the file, keyed by group name
groups: std.StringHashMap(DesktopGroup),

/// Allocator used for all memory allocations
allocator: std.mem.Allocator,

/// Initialize an empty desktop file
pub fn init(allocator: std.mem.Allocator) DesktopFile {
    return .{
        .groups = std.StringHashMap(DesktopGroup).init(allocator),
        .allocator = allocator,
    };
}

/// Free all memory associated with this desktop file
pub fn deinit(self: *DesktopFile) void {
    var it = self.groups.iterator();
    while (it.next()) |kv| {
        self.allocator.free(kv.key_ptr.*);
        kv.value_ptr.deinit(self.allocator);
    }
    self.groups.deinit();
}

/// Get the main [Desktop Entry] group if it exists
pub fn getDesktopEntry(self: *const DesktopFile) ?*const DesktopGroup {
    return self.groups.getPtr("Desktop Entry");
}

/// Add a new group to the file.
/// Duplicates the group_name string internally.
pub fn putGroup(self: *DesktopFile, group_name: []const u8, group: DesktopGroup) !void {
    const owned_name = try self.allocator.dupe(u8, group_name);
    errdefer self.allocator.free(owned_name);
    try self.groups.put(owned_name, group);
}

/// Get a group by name
pub fn getGroup(self: *const DesktopFile, name: []const u8) ?*const DesktopGroup {
    return self.groups.getPtr(name);
}

/// Return true if a group with the given name exists
pub fn hasGroup(self: *const DesktopFile, name: []const u8) bool {
    return self.groups.contains(name);
}

// ── Convenience accessors for [Desktop Entry] keys ───────────────────────────

/// Return the raw value of the `Type` key, or null if absent
pub fn getType(self: *const DesktopFile) ?[]const u8 {
    const de = self.getDesktopEntry() orelse return null;
    return de.getValue("Type");
}

/// Return the raw value of the `Name` key, or null if absent
pub fn getName(self: *const DesktopFile) ?[]const u8 {
    const de = self.getDesktopEntry() orelse return null;
    return de.getValue("Name");
}

/// Return the raw value of the `Exec` key, or null if absent
pub fn getExec(self: *const DesktopFile) ?[]const u8 {
    const de = self.getDesktopEntry() orelse return null;
    return de.getValue("Exec");
}

/// Return the raw value of the `URL` key, or null if absent
pub fn getURL(self: *const DesktopFile) ?[]const u8 {
    const de = self.getDesktopEntry() orelse return null;
    return de.getValue("URL");
}
