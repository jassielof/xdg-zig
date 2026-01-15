const std = @import("std");
const xdg = @import("xdg_desktop_entry");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <desktop-file.desktop>\n", .{args[0]});
        std.debug.print("\nExample:\n", .{});
        std.debug.print("  {s} /usr/share/applications/firefox.desktop\n", .{args[0]});
        return;
    }

    const file_path = args[1];

    // Parse the desktop file
    var desktop_file = xdg.parseFile(allocator, file_path) catch |err| {
        std.debug.print("Error parsing file: {}\n", .{err});
        return err;
    };
    defer desktop_file.deinit();

    std.debug.print("Successfully parsed: {s}\n\n", .{file_path});

    // Get the main [Desktop Entry] group
    if (desktop_file.getDesktopEntry()) |entry| {
        std.debug.print("=== Desktop Entry ===\n", .{});

        // Print common fields
        const fields = [_][]const u8{
            "Type",
            "Name",
            "Comment",
            "Exec",
            "Icon",
            "Terminal",
            "Categories",
        };

        for (fields) |field| {
            if (entry.getValue(field)) |value| {
                std.debug.print("{s}: {s}\n", .{ field, value });
            }
        }

        // Print all other entries
        std.debug.print("\n=== All Entries ({d} total) ===\n", .{entry.entries.items.len});
        for (entry.entries.items) |item| {
            if (item.locale) |locale| {
                std.debug.print("{s}[{s}] = {s}\n", .{ item.key, locale, item.value });
            } else {
                std.debug.print("{s} = {s}\n", .{ item.key, item.value });
            }
        }
    } else {
        std.debug.print("Warning: No [Desktop Entry] group found\n", .{});
    }

    // Print all groups
    std.debug.print("\n=== All Groups ===\n", .{});
    var group_iter = desktop_file.groups.iterator();
    while (group_iter.next()) |kv| {
        std.debug.print("[{s}] ({d} entries)\n", .{ kv.key_ptr.*, kv.value_ptr.entries.items.len });
    }
}

test "simple parsing test" {
    const allocator = std.testing.allocator;

    const content =
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Example
        \\Name[es]=Ejemplo
        \\Exec=/usr/bin/example
        \\Icon=example-icon
        \\Terminal=false
        \\Categories=Utility;Development;
        \\
    ;

    var desktop_file = try xdg.parseString(allocator, content);
    defer desktop_file.deinit();

    const entry = desktop_file.getDesktopEntry().?;

    // Test basic values
    try std.testing.expectEqualStrings("Application", entry.getValue("Type").?);
    try std.testing.expectEqualStrings("Example", entry.getValue("Name").?);
    try std.testing.expectEqualStrings("/usr/bin/example", entry.getValue("Exec").?);

    // Test boolean parsing
    const terminal_value = entry.getValue("Terminal").?;
    const is_terminal = try xdg.ValueType.parseBoolean(terminal_value);
    try std.testing.expect(is_terminal == false);

    // Test list parsing
    const categories = entry.getValue("Categories").?;
    const category_list = try xdg.ValueType.parseList(allocator, categories);
    defer xdg.ValueType.freeList(allocator, category_list);

    try std.testing.expectEqual(@as(usize, 2), category_list.len);
    try std.testing.expectEqualStrings("Utility", category_list[0]);
    try std.testing.expectEqualStrings("Development", category_list[1]);
}

test "error handling" {
    const allocator = std.testing.allocator;

    // Missing [Desktop Entry] group
    const invalid_content =
        \\[Some Other Group]
        \\Key=Value
        \\
    ;

    const result = xdg.parseString(allocator, invalid_content);
    try std.testing.expectError(xdg.ParseError.MissingDesktopEntryGroup, result);
}

test "locale handling" {
    const allocator = std.testing.allocator;

    const content =
        \\[Desktop Entry]
        \\Name=English Name
        \\Name[es]=Nombre Español
        \\Name[fr]=Nom Français
        \\
    ;

    var desktop_file = try xdg.parseString(allocator, content);
    defer desktop_file.deinit();

    const entry = desktop_file.getDesktopEntry().?;

    // Find localized entries
    var found_es = false;
    var found_fr = false;

    for (entry.entries.items) |item| {
        if (std.mem.eql(u8, item.key, "Name")) {
            if (item.locale) |locale| {
                if (std.mem.eql(u8, locale, "es")) {
                    try std.testing.expectEqualStrings("Nombre Español", item.value);
                    found_es = true;
                }
                if (std.mem.eql(u8, locale, "fr")) {
                    try std.testing.expectEqualStrings("Nom Français", item.value);
                    found_fr = true;
                }
            }
        }
    }

    try std.testing.expect(found_es);
    try std.testing.expect(found_fr);
}
