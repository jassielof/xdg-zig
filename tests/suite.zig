const std = @import("std");
const refAllDecls = std.testing.refAllDecls;

comptime {
    refAllDecls(@This());
    refAllDecls(@import("desktop_entry.zig"));
    refAllDecls(@import("base_directory.zig"));
}
