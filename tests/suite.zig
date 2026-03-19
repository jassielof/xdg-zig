const std = @import("std");
const testing = std.testing;

test {
    _ = @import("desktop_entry.zig");
    testing.refAllDecls(@This());
}
