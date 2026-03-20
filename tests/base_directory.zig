//! Integration tests for the XDG Base Directory module.
//! These tests exercise the real process environment (env = null).

const std = @import("std");
const xdg = @import("xdg");
const bd = xdg.base_directory;

// ── Real-environment tests ────────────────────────────────────────────────────
// These test the actual running environment. We can't assume specific paths,
// but we can assert structural properties (absolute, correct suffix, etc.).

test "real env: xdgDataHome is absolute" {
    const allocator = std.testing.allocator;
    const h = try bd.xdgDataHome(allocator, null);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
}

test "real env: xdgConfigHome is absolute" {
    const allocator = std.testing.allocator;
    const h = try bd.xdgConfigHome(allocator, null);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
}

test "real env: xdgStateHome is absolute" {
    const allocator = std.testing.allocator;
    const h = try bd.xdgStateHome(allocator, null);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
}

test "real env: xdgCacheHome is absolute" {
    const allocator = std.testing.allocator;
    const h = try bd.xdgCacheHome(allocator, null);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
}

test "real env: xdgExecutableHome is absolute and ends with .local/bin" {
    const allocator = std.testing.allocator;
    const h = try bd.xdgExecutableHome(allocator, null);
    defer allocator.free(h);
    try std.testing.expect(std.fs.path.isAbsolute(h));
    try std.testing.expect(
        std.mem.endsWith(u8, h, ".local/bin") or
            std.mem.endsWith(u8, h, ".local\\bin"),
    );
}

test "real env: xdgRuntimeDir is null or non-empty string" {
    const allocator = std.testing.allocator;
    const rt = try bd.xdgRuntimeDir(allocator);
    if (rt) |val| {
        defer allocator.free(val);
        try std.testing.expect(val.len > 0);
    }
    // null is perfectly valid — no assertion needed
}

test "real env: xdgDataDirs first element equals xdgDataHome" {
    const allocator = std.testing.allocator;
    const home = try bd.xdgDataHome(allocator, null);
    defer allocator.free(home);
    const dirs = try bd.xdgDataDirs(allocator, null);
    defer bd.freeDirs(allocator, dirs);
    try std.testing.expect(dirs.len >= 1);
    try std.testing.expectEqualStrings(home, dirs[0]);
}

test "real env: all xdgDataDirs entries are absolute" {
    const allocator = std.testing.allocator;
    const dirs = try bd.xdgDataDirs(allocator, null);
    defer bd.freeDirs(allocator, dirs);
    for (dirs) |d| {
        try std.testing.expect(std.fs.path.isAbsolute(d));
    }
}

test "real env: xdgConfigDirs first element equals xdgConfigHome" {
    const allocator = std.testing.allocator;
    const home = try bd.xdgConfigHome(allocator, null);
    defer allocator.free(home);
    const dirs = try bd.xdgConfigDirs(allocator, null);
    defer bd.freeDirs(allocator, dirs);
    try std.testing.expect(dirs.len >= 1);
    try std.testing.expectEqualStrings(home, dirs[0]);
}

test "real env: all xdgConfigDirs entries are absolute" {
    const allocator = std.testing.allocator;
    const dirs = try bd.xdgConfigDirs(allocator, null);
    defer bd.freeDirs(allocator, dirs);
    for (dirs) |d| {
        try std.testing.expect(std.fs.path.isAbsolute(d));
    }
}

// ── Synthetic-env override tests ──────────────────────────────────────────────
// Use EnvMap to inject a controlled environment without touching real env vars.

fn makeTestEnv(allocator: std.mem.Allocator) !std.process.EnvMap {
    var env = std.process.EnvMap.init(allocator);
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
    try env.put("XDG_DATA_DIRS", "/abs1:not_absolute:/abs2");
    const dirs = try bd.xdgDataDirs(allocator, &env);
    defer bd.freeDirs(allocator, dirs);
    // home + /abs1 + /abs2 (not_absolute filtered)
    try std.testing.expectEqual(@as(usize, 3), dirs.len);
    try std.testing.expectEqualStrings("/abs1", dirs[1]);
    try std.testing.expectEqualStrings("/abs2", dirs[2]);
}

test "override: xdgRuntimeDir reads real env only" {
    // xdgRuntimeDir has no env injection; just assert it doesn't panic.
    const allocator = std.testing.allocator;
    const rt = try bd.xdgRuntimeDir(allocator);
    if (rt) |val| allocator.free(val);
}
