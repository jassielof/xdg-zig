//! Integration tests for the XDG Base Directory module.
//! These tests use synthetic environment maps for deterministic CI behavior.

const std = @import("std");
const builtin = @import("builtin");

const xdg = @import("xdg");
const bd = xdg.base_directory;

test "env map: xdgDataHome is absolute" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    const h = try bd.xdgDataHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
}

test "env map: xdgConfigHome is absolute" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    const h = try bd.xdgConfigHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
}

test "env map: xdgStateHome is absolute" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    const h = try bd.xdgStateHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
}

test "env map: xdgCacheHome is absolute" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    const h = try bd.xdgCacheHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
}

test "env map: xdgExecutableHome is absolute and ends with .local/bin" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    const h = try bd.xdgExecutableHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
    try std.testing.expect(
        std.mem.endsWith(u8, h, ".local/bin") or
            std.mem.endsWith(u8, h, ".local\\bin"),
    );
}

test "process env: xdgRuntimeDir is null or absolute" {
    const allocator = std.testing.allocator;
    const rt = try bd.xdgRuntimeDir(allocator);
    if (rt) |val| {
        defer allocator.free(val);
        try std.testing.expect(std.fs.path.isAbsolute(val));
    }
    // null is perfectly valid — no assertion needed
}

test "env map: xdgDataDirs first element equals xdgDataHome" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    const home = try bd.xdgDataHome(allocator, &env);
    defer allocator.free(home);
    const dirs = try bd.xdgDataDirs(allocator, &env);
    defer bd.freeDirs(allocator, dirs);
    try std.testing.expect(dirs.len >= 1);
    try std.testing.expectEqualStrings(home, dirs[0]);
}

test "env map: all xdgDataDirs entries are absolute" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    const dirs = try bd.xdgDataDirs(allocator, &env);
    defer bd.freeDirs(allocator, dirs);
    for (dirs) |d| {
        try std.testing.expect(std.fs.path.isAbsolute(d));
    }
}

test "env map: xdgConfigDirs first element equals xdgConfigHome" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    const home = try bd.xdgConfigHome(allocator, &env);
    defer allocator.free(home);
    const dirs = try bd.xdgConfigDirs(allocator, &env);
    defer bd.freeDirs(allocator, dirs);
    try std.testing.expect(dirs.len >= 1);
    try std.testing.expectEqualStrings(home, dirs[0]);
}

test "env map: all xdgConfigDirs entries are absolute" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    const dirs = try bd.xdgConfigDirs(allocator, &env);
    defer bd.freeDirs(allocator, dirs);
    for (dirs) |d| {
        try std.testing.expect(std.fs.path.isAbsolute(d));
    }
}

// Synthetic-env override tests
// Use Environ.Map to inject a controlled environment without touching real env vars.

fn makeTestEnv(allocator: std.mem.Allocator) !std.process.Environ.Map {
    var env = std.process.Environ.Map.init(allocator);
    try env.put("HOME", "/home/xdgtest");
    return env;
}

test "override: XDG_DATA_HOME is honoured" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    try env.put("XDG_DATA_HOME", "/custom/data");
    const h = try bd.xdgDataHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/custom/data", h);
}

test "override: relative XDG_DATA_HOME is ignored, fallback used" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    try env.put("XDG_DATA_HOME", "relative/path");
    const h = try bd.xdgDataHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/home/xdgtest/.local/share", h);
}

test "override: XDG_CONFIG_HOME is honoured" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();
    try env.put("XDG_CONFIG_HOME", "/custom/config");
    const h = try bd.xdgConfigHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/custom/config", h);
}

test "override: XDG_DATA_DIRS relative entries are filtered" {
    const allocator = std.testing.allocator;
    var env = try makeTestEnv(allocator);
    defer env.deinit();

    const path1 = if (builtin.os.tag == .windows) "C:\\abs1" else "/abs1";
    const path2 = if (builtin.os.tag == .windows) "D:\\abs2" else "/abs2";
    const dirs_var = try std.fmt.allocPrint(
        allocator,
        "{s}{c}not_absolute{c}{s}",
        .{ path1, std.fs.path.delimiter, std.fs.path.delimiter, path2 },
    );
    defer allocator.free(dirs_var);

    try env.put("XDG_DATA_DIRS", dirs_var);
    const dirs = try bd.xdgDataDirs(allocator, &env);
    defer bd.freeDirs(allocator, dirs);
    // home + /abs1 + /abs2 (not_absolute filtered)
    try std.testing.expectEqual(@as(usize, 3), dirs.len);
    try std.testing.expectEqualStrings(path1, dirs[1]);
    try std.testing.expectEqualStrings(path2, dirs[2]);
}

test "override: xdgRuntimeDir remains safe under synthetic-env tests" {
    // xdgRuntimeDir intentionally reads process env; assert API is stable.
    const allocator = std.testing.allocator;
    const rt = try bd.xdgRuntimeDir(allocator);
    if (rt) |val| {
        defer allocator.free(val);
        try std.testing.expect(std.fs.path.isAbsolute(val));
    }
}
