const std = @import("std");
const testing = std.testing;

comptime {
    _ = @import("basic.zig");
    _ = @import("fixtures.zig");
}

test {
    testing.refAllDecls(@This());
}
