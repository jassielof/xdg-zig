const std = @import("std");
const testing = std.testing;

test {
    _ = @import("desktop_entry.zig");
    _ = @import("base_directory.zig");
    testing.refAllDecls(@This());
}
