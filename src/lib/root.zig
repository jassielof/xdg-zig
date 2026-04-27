//! XDG library for working with XDG standards.

const std = @import("std");
const refAllDecls = std.testing.refAllDecls;

pub const base_directory = @import("base_directory/root.zig");
pub const desktop_entry = @import("desktop_entry/root.zig");

comptime {
    refAllDecls(@This());
}
