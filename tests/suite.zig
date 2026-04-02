const std = @import("std");
const testing = std.testing;

comptime {
    _ = @import("desktop_entry.zig");
    _ = @import("base_directory.zig");
}
