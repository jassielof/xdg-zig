//! XDG Base Directory Specification implementation.
//!
//! Implements version 0.8 of the spec: https://specifications.freedesktop.org/basedir-spec/latest/
//!
//! Most public functions accept an optional `?*const std.process.Environ.Map`. When non-null the map is used instead of the real process environment, which allows deterministic unit testing without mutating global state. `xdgRuntimeDir` uses the real environment via its public API.
//!
//! Functions returning a single path return a `[]u8` owned by the caller. Directory list functions return a `[][]u8`; use `freeDirs` to release them.
//!
//! Spec rule: paths in env vars MUST be absolute; relative paths are silently ignored when building directory lists.

const std = @import("std");
const Allocator = std.mem.Allocator;
const EnvironMap = std.process.Environ.Map;
const fsp = std.fs.path;
const Io = std.Io;
const builtin = @import("builtin");

/// Look up a key in an environment map (which must be provided by the caller).
///
/// Returns an allocated copy owned by the caller, or null if absent/empty.
fn envGet(
    allocator: Allocator,
    env_map: ?*const EnvironMap,
    key: []const u8,
) !?[]u8 {
    const val = if (env_map) |map|
        map.get(key) orelse return null
    else
        return std.process.Environ.getAlloc(processEnviron(), allocator, key) catch |err| switch (err) {
            error.EnvironmentVariableMissing => return null,
            else => return err,
        };
    return try allocator.dupe(u8, val);
}

/// Read an env var and return it only when non-empty and absolute.
///
/// Returns null when absent, empty, or relative. Caller owns the result.
fn getAbsEnvVar(
    allocator: Allocator,
    env_map: ?*const EnvironMap,
    key: []const u8,
) !?[]u8 {
    const val = try envGet(allocator, env_map, key) orelse return null;
    errdefer allocator.free(val);

    if (val.len == 0 or !fsp.isAbsolute(val)) {
        allocator.free(val);
        return null;
    }

    return val;
}

/// Return the user home directory. Checks HOME then USERPROFILE. Caller owns.
fn getHomeDir(allocator: Allocator, env: ?*const EnvironMap) ![]u8 {
    if (try envGet(allocator, env, "HOME")) |h| return h;
    if (try envGet(allocator, env, "USERPROFILE")) |h| return h;
    return error.EnvironmentVariableMissing;
}

/// Split a platform-path-separated list and append only absolute entries.
///
/// Uses the unmanaged ArrayList API: pass allocator to `append`.
fn collectAbsolutePaths(
    allocator: Allocator,
    list_str: []const u8,
    out: *std.ArrayList([]u8),
) !void {
    var iter = std.mem.splitScalar(u8, list_str, fsp.delimiter);
    while (iter.next()) |entry| {
        const trimmed = std.mem.trim(u8, entry, " \t");
        if (trimmed.len == 0 or !fsp.isAbsolute(trimmed)) continue;
        try out.append(allocator, try allocator.dupe(u8, trimmed));
    }
}

/// Free all items in the list then the list storage itself (errdefer helper).
fn freeDirsList(allocator: Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

/// `$XDG_DATA_HOME` or `$HOME/.local/share`. Caller must free.
pub fn xdgDataHome(allocator: Allocator, env: ?*const EnvironMap) ![]u8 {
    if (try getAbsEnvVar(allocator, env, "XDG_DATA_HOME")) |v| return v;
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".local", "share" });
}

/// `$XDG_CONFIG_HOME` or `$HOME/.config`. Caller must free.
pub fn xdgConfigHome(allocator: Allocator, env: ?*const EnvironMap) ![]u8 {
    if (try getAbsEnvVar(allocator, env, "XDG_CONFIG_HOME")) |v| return v;
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".config" });
}

/// `$XDG_STATE_HOME` or `$HOME/.local/state`. Caller must free.
pub fn xdgStateHome(allocator: Allocator, env: ?*const EnvironMap) ![]u8 {
    if (try getAbsEnvVar(allocator, env, "XDG_STATE_HOME")) |v| return v;
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".local", "state" });
}

/// `$XDG_CACHE_HOME` or `$HOME/.cache`. Caller must free.
pub fn xdgCacheHome(allocator: Allocator, env: ?*const EnvironMap) ![]u8 {
    if (try getAbsEnvVar(allocator, env, "XDG_CACHE_HOME")) |v| return v;
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".cache" });
}

/// `$HOME/.local/bin` (no env var override per spec). Caller must free.
pub fn xdgExecutableHome(allocator: Allocator, env: ?*const EnvironMap) ![]u8 {
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".local", "bin" });
}

/// Internal helper to support deterministic tests with synthetic env maps.
fn xdgRuntimeDirWithEnv(allocator: Allocator, env: ?*const EnvironMap) !?[]u8 {
    if (try getAbsEnvVar(allocator, env, "XDG_RUNTIME_DIR")) |v| return v;

    if (builtin.os.tag == .linux) {
        std.log.warn(
            "XDG_RUNTIME_DIR is unset or invalid; using Linux fallback /run/user/$UID",
            .{},
        );
        const fallback = try std.fmt.allocPrint(allocator, "/run/user/{d}", .{std.os.linux.getuid()});
        return fallback;
    }

    return null;
}

/// `$XDG_RUNTIME_DIR` when set to an absolute path; otherwise null on non-Linux, or `/run/user/$UID` on Linux as a replacement directory.
///
/// Caller must free the returned slice when non-null.
pub fn xdgRuntimeDir(allocator: Allocator) !?[]u8 {
    return xdgRuntimeDirWithEnv(allocator, null);
}

/// `[xdgDataHome] ++ $XDG_DATA_DIRS` (default: /usr/local/share, /usr/share).
///
/// Relative paths in the env var are silently skipped. Caller must `freeDirs`.
pub fn xdgDataDirs(allocator: Allocator, env: ?*const EnvironMap) ![][]u8 {
    var list: std.ArrayList([]u8) = .empty;
    errdefer freeDirsList(allocator, &list);

    try list.append(allocator, try xdgDataHome(allocator, env));

    const dirs_val = try envGet(allocator, env, "XDG_DATA_DIRS");
    if (dirs_val) |dv| {
        defer allocator.free(dv);
        const trimmed = std.mem.trim(u8, dv, " \t");
        if (trimmed.len > 0) {
            try collectAbsolutePaths(allocator, trimmed, &list);
        } else {
            try list.append(allocator, try allocator.dupe(u8, "/usr/local/share"));
            try list.append(allocator, try allocator.dupe(u8, "/usr/share"));
        }
    } else {
        try list.append(allocator, try allocator.dupe(u8, "/usr/local/share"));
        try list.append(allocator, try allocator.dupe(u8, "/usr/share"));
    }

    return list.toOwnedSlice(allocator);
}

/// `[xdgConfigHome] ++ $XDG_CONFIG_DIRS` (default: /etc/xdg).
///
/// Relative paths in the env var are silently skipped. Caller must `freeDirs`.
pub fn xdgConfigDirs(allocator: Allocator, env: ?*const EnvironMap) ![][]u8 {
    var list: std.ArrayList([]u8) = .empty;
    errdefer freeDirsList(allocator, &list);

    try list.append(allocator, try xdgConfigHome(allocator, env));

    const dirs_val = try envGet(allocator, env, "XDG_CONFIG_DIRS");
    if (dirs_val) |dv| {
        defer allocator.free(dv);
        const trimmed = std.mem.trim(u8, dv, " \t");
        if (trimmed.len > 0) {
            try collectAbsolutePaths(allocator, trimmed, &list);
        } else {
            try list.append(allocator, try allocator.dupe(u8, "/etc/xdg"));
        }
    } else {
        try list.append(allocator, try allocator.dupe(u8, "/etc/xdg"));
    }

    return list.toOwnedSlice(allocator);
}

/// Search data dirs for a relative `resource` path; return first existing match.
///
/// Caller must free the returned path (when non-null).
pub fn findDataFile(allocator: Allocator, io: Io, env: ?*const EnvironMap, resource: []const u8) !?[]u8 {
    const dirs = try xdgDataDirs(allocator, env);
    defer freeDirs(allocator, dirs);
    for (dirs) |dir| {
        const candidate = try std.mem.join(allocator, "/", &.{ dir, resource });
        if (Io.Dir.accessAbsolute(io, candidate, .{})) |_| {
            return candidate;
        } else |_| {
            allocator.free(candidate);
        }
    }
    return null;
}

/// Search config dirs for a relative `resource` path; return first existing match.
///
/// Caller must free the returned path (when non-null).
pub fn findConfigFile(allocator: Allocator, io: Io, env: ?*const EnvironMap, resource: []const u8) !?[]u8 {
    const dirs = try xdgConfigDirs(allocator, env);
    defer freeDirs(allocator, dirs);
    for (dirs) |dir| {
        const candidate = try std.mem.join(allocator, "/", &.{ dir, resource });
        if (Io.Dir.accessAbsolute(io, candidate, .{})) |_| {
            return candidate;
        } else |_| {
            allocator.free(candidate);
        }
    }
    return null;
}

/// Free a slice of owned path strings returned by xdgDataDirs / xdgConfigDirs.
pub fn freeDirs(allocator: Allocator, dirs: [][]u8) void {
    for (dirs) |d| allocator.free(d);
    allocator.free(dirs);
}

fn makeEnv(allocator: Allocator) !EnvironMap {
    var env = EnvironMap.init(allocator);
    try env.put("HOME", "/home/testuser");
    return env;
}

fn processEnviron() std.process.Environ {
    return .{ .block = if (builtin.os.tag == .windows) .global else .empty };
}

test "xdgDataHome: default from HOME" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    const h = try xdgDataHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/home/testuser/.local/share", h);
}

test "xdgDataHome: env var override" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    try env.put("XDG_DATA_HOME", "/custom/data");
    const h = try xdgDataHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/custom/data", h);
}

test "xdgDataHome: relative path in env var is ignored (falls back to default)" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    try env.put("XDG_DATA_HOME", "relative/path");
    const h = try xdgDataHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/home/testuser/.local/share", h);
}

test "xdgConfigHome: default from HOME" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    const h = try xdgConfigHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/home/testuser/.config", h);
}

test "xdgStateHome: default from HOME" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    const h = try xdgStateHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/home/testuser/.local/state", h);
}

test "xdgCacheHome: default from HOME" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    const h = try xdgCacheHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/home/testuser/.cache", h);
}

test "xdgExecutableHome: always HOME/.local/bin" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    const h = try xdgExecutableHome(allocator, &env);
    defer allocator.free(h);
    try std.testing.expectEqualStrings("/home/testuser/.local/bin", h);
}

test "xdgDataDirs: first element is xdgDataHome" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    const dirs = try xdgDataDirs(allocator, &env);
    defer freeDirs(allocator, dirs);
    try std.testing.expect(dirs.len >= 1);
    try std.testing.expectEqualStrings("/home/testuser/.local/share", dirs[0]);
}

test "xdgDataDirs: default extra dirs when XDG_DATA_DIRS unset" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    const dirs = try xdgDataDirs(allocator, &env);
    defer freeDirs(allocator, dirs);
    try std.testing.expectEqual(@as(usize, 3), dirs.len);
    try std.testing.expectEqualStrings("/usr/local/share", dirs[1]);
    try std.testing.expectEqualStrings("/usr/share", dirs[2]);
}

test "xdgDataDirs: custom XDG_DATA_DIRS" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();

    const path1 = if (builtin.os.tag == .windows) "C:\\opt\\data" else "/opt/data";
    const path2 = if (builtin.os.tag == .windows) "D:\\srv\\data" else "/srv/data";
    const dirs_var = try std.fmt.allocPrint(
        allocator,
        "{s}{c}{s}",
        .{ path1, fsp.delimiter, path2 },
    );
    defer allocator.free(dirs_var);

    try env.put("XDG_DATA_DIRS", dirs_var);
    const dirs = try xdgDataDirs(allocator, &env);
    defer freeDirs(allocator, dirs);
    try std.testing.expectEqual(@as(usize, 3), dirs.len);
    try std.testing.expectEqualStrings(path1, dirs[1]);
    try std.testing.expectEqualStrings(path2, dirs[2]);
}

test "xdgDataDirs: relative paths in XDG_DATA_DIRS are filtered out" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();

    const path1 = if (builtin.os.tag == .windows) "C:\\valid" else "/valid";
    const path2 = if (builtin.os.tag == .windows) "D:\\also_valid" else "/also_valid";
    const dirs_var = try std.fmt.allocPrint(
        allocator,
        "{s}{c}relative_bad{c}{s}",
        .{ path1, fsp.delimiter, fsp.delimiter, path2 },
    );
    defer allocator.free(dirs_var);

    try env.put("XDG_DATA_DIRS", dirs_var);
    const dirs = try xdgDataDirs(allocator, &env);
    defer freeDirs(allocator, dirs);
    // home + /valid + /also_valid (relative_bad filtered)
    try std.testing.expectEqual(@as(usize, 3), dirs.len);
    try std.testing.expectEqualStrings(path1, dirs[1]);
    try std.testing.expectEqualStrings(path2, dirs[2]);
}

test "xdgConfigDirs: default is /etc/xdg when XDG_CONFIG_DIRS unset" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    const dirs = try xdgConfigDirs(allocator, &env);
    defer freeDirs(allocator, dirs);
    try std.testing.expectEqual(@as(usize, 2), dirs.len);
    try std.testing.expectEqualStrings("/home/testuser/.config", dirs[0]);
    try std.testing.expectEqualStrings("/etc/xdg", dirs[1]);
}

test "xdgConfigDirs: custom XDG_CONFIG_DIRS uses platform separator" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();

    const path1 = if (builtin.os.tag == .windows) "C:\\etc\\xdg" else "/etc/xdg";
    const path2 = if (builtin.os.tag == .windows) "D:\\etc\\xdg-extra" else "/etc/xdg-extra";
    const dirs_var = try std.fmt.allocPrint(
        allocator,
        "{s}{c}{s}",
        .{ path1, fsp.delimiter, path2 },
    );
    defer allocator.free(dirs_var);

    try env.put("XDG_CONFIG_DIRS", dirs_var);

    const dirs = try xdgConfigDirs(allocator, &env);
    defer freeDirs(allocator, dirs);
    try std.testing.expectEqual(@as(usize, 3), dirs.len);
    try std.testing.expectEqualStrings("/home/testuser/.config", dirs[0]);
    try std.testing.expectEqualStrings(path1, dirs[1]);
    try std.testing.expectEqualStrings(path2, dirs[2]);
}

test "xdgRuntimeDir: absolute env value is honoured" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();

    const runtime_dir = if (builtin.os.tag == .windows)
        "C:\\runtime\\xdg"
    else
        "/tmp/runtime-xdg";
    try env.put("XDG_RUNTIME_DIR", runtime_dir);

    const got = try xdgRuntimeDirWithEnv(allocator, &env);
    defer if (got) |g| allocator.free(g);
    try std.testing.expect(got != null);
    try std.testing.expectEqualStrings(runtime_dir, got.?);
}

test "xdgRuntimeDir: relative env value is ignored" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    try env.put("XDG_RUNTIME_DIR", "relative/runtime");

    const got = try xdgRuntimeDirWithEnv(allocator, &env);
    defer if (got) |g| allocator.free(g);

    if (builtin.os.tag == .linux) {
        const expected = try std.fmt.allocPrint(allocator, "/run/user/{d}", .{std.os.linux.getuid()});
        defer allocator.free(expected);
        try std.testing.expect(got != null);
        try std.testing.expectEqualStrings(expected, got.?);
    } else {
        try std.testing.expect(got == null);
    }
}

test "xdgRuntimeDir: Linux fallback when unset" {
    if (builtin.os.tag != .linux) return;

    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();

    const got = try xdgRuntimeDirWithEnv(allocator, &env);
    defer if (got) |g| allocator.free(g);
    const expected = try std.fmt.allocPrint(allocator, "/run/user/{d}", .{std.os.linux.getuid()});
    defer allocator.free(expected);

    try std.testing.expect(got != null);
    try std.testing.expectEqualStrings(expected, got.?);
}
