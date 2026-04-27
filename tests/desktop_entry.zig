//! Integration tests for the XDG Desktop Entry parser.
//! Exercises all fixture files under tests/fixtures/desktop-entry/.

const std = @import("std");

const xdg = @import("xdg");
const de = xdg.desktop_entry;

fn resolveFixturePath(allocator: std.mem.Allocator, io: std.Io, rel_path: []const u8) ![]u8 {
    const cwd_realpath = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator);
    defer allocator.free(cwd_realpath);

    var current_dir = try allocator.dupe(u8, cwd_realpath);
    defer allocator.free(current_dir);

    while (true) {
        const candidate = try std.fs.path.join(allocator, &.{ current_dir, rel_path });
        if (std.Io.Dir.accessAbsolute(io, candidate, .{})) {
            return candidate;
        } else |err| switch (err) {
            error.FileNotFound => allocator.free(candidate),
            else => {
                allocator.free(candidate);
                return err;
            },
        }

        const parent = std.fs.path.dirname(current_dir) orelse break;
        if (parent.len == current_dir.len) break;

        const next_dir = try allocator.dupe(u8, parent);
        allocator.free(current_dir);
        current_dir = next_dir;
    }

    return error.FileNotFound;
}

// Helper: parse a fixture file relative to project root, independent of cwd.
fn parseFixture(allocator: std.mem.Allocator, rel_path: []const u8) !de.DesktopFile {
    const io = std.testing.io;
    const path = try resolveFixturePath(allocator, io, rel_path);
    defer allocator.free(path);
    return de.parseFile(allocator, io, path);
}

// ── Valid fixtures ─────────────────────────────────────────────────────────────

test "valid: minimal application" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/minimal.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Application", f.getType().?);
    try std.testing.expectEqualStrings("Minimal App", f.getName().?);
    try std.testing.expectEqualStrings("minimal-app", f.getExec().?);
    try std.testing.expect(f.hasGroup("Desktop Entry"));
}

test "valid: spec example (from the XDG spec)" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/spec_example.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Application", f.getType().?);
    try std.testing.expectEqualStrings("Foo Viewer", f.getName().?);
    try std.testing.expect(f.hasGroup("Desktop Action Gallery"));
    try std.testing.expect(f.hasGroup("Desktop Action Create"));

    // MimeType and Actions keys
    const de_group = f.getDesktopEntry().?;
    try std.testing.expect(de_group.getValue("MimeType") != null);
    try std.testing.expect(de_group.getValue("Actions") != null);
}

test "valid: full entry with localized keys and actions" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/full_entry.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Application", f.getType().?);
    try std.testing.expectEqualStrings("Full Featured Application", f.getName().?);

    const de_group = f.getDesktopEntry().?;
    // Localized Name key must be stored under the locale-suffixed key name
    try std.testing.expect(de_group.getValue("Name") != null);
    // Categories and MimeType
    try std.testing.expect(de_group.getValue("Categories") != null);
    try std.testing.expect(de_group.getValue("MimeType") != null);

    // Action groups
    try std.testing.expect(f.hasGroup("Desktop Action new-window"));
    try std.testing.expect(f.hasGroup("Desktop Action preferences"));
}

test "valid: feature rich entry with locales and OnlyShowIn" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/feature_rich.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Application", f.getType().?);
    const de_group = f.getDesktopEntry().?;
    try std.testing.expect(de_group.getValue("OnlyShowIn") != null);
    try std.testing.expect(de_group.getValue("Keywords") != null);
    try std.testing.expect(f.hasGroup("Desktop Action edit"));
    try std.testing.expect(f.hasGroup("Desktop Action view"));
}

test "valid: link entry" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/link_entry.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Link", f.getType().?);
    try std.testing.expectEqualStrings("Example Website Link", f.getName().?);
    try std.testing.expectEqualStrings("https://www.example.com", f.getURL().?);
}

test "valid: directory entry" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/directory_entry.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Directory", f.getType().?);
    try std.testing.expectEqualStrings("Custom Directory", f.getName().?);
    // Directory type does not require Exec or URL
    try std.testing.expect(f.getExec() == null);
    try std.testing.expect(f.getURL() == null);
}

test "valid: hidden application" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/hidden_app.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Application", f.getType().?);
    const de_group = f.getDesktopEntry().?;
    try std.testing.expectEqualStrings("true", de_group.getValue("Hidden").?);
    try std.testing.expectEqualStrings("true", de_group.getValue("NoDisplay").?);
}

test "valid: terminal application" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/terminal_app.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Application", f.getType().?);
    const de_group = f.getDesktopEntry().?;
    try std.testing.expectEqualStrings("true", de_group.getValue("Terminal").?);
    try std.testing.expect(de_group.getValue("Categories") != null);
}

test "valid: dbus-activatable application (no Exec needed)" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/dbus_app.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Application", f.getType().?);
    try std.testing.expectEqualStrings("DBus Activatable App", f.getName().?);
    const de_group = f.getDesktopEntry().?;
    try std.testing.expectEqualStrings("true", de_group.getValue("DBusActivatable").?);
    // DBusActivatable is an alternative to Exec — no Exec key present
    try std.testing.expect(f.getExec() == null);
}

test "valid: file with inline comments" {
    const allocator = std.testing.allocator;
    var f = try parseFixture(allocator, "tests/fixtures/desktop-entry/valid/with_comments.desktop");
    defer f.deinit();

    try std.testing.expectEqualStrings("Application", f.getType().?);
    try std.testing.expectEqualStrings("App with Comments", f.getName().?);
    // The X-Custom Extension group must be parsed correctly
    try std.testing.expect(f.hasGroup("X-Custom Extension"));
    // Comments must NOT appear as entries
    const de_group = f.getDesktopEntry().?;
    try std.testing.expect(de_group.getValue("# This comment is inside the Desktop Entry group") == null);
}

// ── Invalid fixtures ──────────────────────────────────────────────────────────

test "invalid: missing [Desktop Entry] group" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/missing_desktop_entry.desktop");
    try std.testing.expectError(de.ParseError.MissingDesktopEntryGroup, result);
}

test "invalid: missing Name key" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/missing_name.desktop");
    try std.testing.expectError(de.ParseError.MissingRequiredKey, result);
}

test "invalid: missing Type key" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/missing_type.desktop");
    try std.testing.expectError(de.ParseError.MissingRequiredKey, result);
}

test "invalid: unrecognised Type value" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/invalid_type.desktop");
    try std.testing.expectError(de.ParseError.InvalidTypeValue, result);
}

test "invalid: Application without Exec (and no DBusActivatable)" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/app_without_exec.desktop");
    try std.testing.expectError(de.ParseError.MissingExecForApplication, result);
}

test "invalid: Link without URL" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/link_without_url.desktop");
    try std.testing.expectError(de.ParseError.MissingUrlForLink, result);
}

test "invalid: duplicate group headers" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/duplicate_groups.desktop");
    try std.testing.expectError(de.ParseError.DuplicateGroup, result);
}

test "invalid: malformed group header (no closing bracket)" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/invalid_group_header.desktop");
    try std.testing.expectError(de.ParseError.InvalidGroupHeader, result);
}

test "invalid: key names with illegal characters" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/invalid_key_name.desktop");
    try std.testing.expectError(de.ParseError.InvalidKeyName, result);
}

test "invalid: line with no equals sign" {
    const allocator = std.testing.allocator;
    const result = parseFixture(allocator, "tests/fixtures/desktop-entry/invalid/invalid_line_format.desktop");
    try std.testing.expectError(de.ParseError.InvalidLine, result);
}
