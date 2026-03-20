//! XDG Base Directory Specification implementation.
//!
//! Implements version 0.8 of the spec:
//! https://specifications.freedesktop.org/basedir-spec/latest/
//!
//! All public functions accept an optional `?*const std.process.EnvMap`.
//! When non-null the map is used instead of the real process environment,
//! which allows deterministic unit testing without mutating global state.
//! Pass `null` in production code to use the real environment.
//!
//! Functions returning a single path return a `[]u8` owned by the caller.
//! Directory list functions return a `[][]u8`; use `freeDirs` to release them.
//!
//! Spec rule: paths in env vars MUST be absolute; relative paths are silently
//! ignored when building directory lists.

const std = @import("std");
const Allocator = std.mem.Allocator;
const EnvMap = std.process.EnvMap;
const fsp = std.fs.path;

// ── Internal helpers ──────────────────────────────────────────────────────────

/// Look up `key` in `env` (when provided) or the real process environment.
/// Returns an allocated copy owned by the caller, or null if absent/empty.
fn envGet(allocator: Allocator, env: ?*const EnvMap, key: []const u8) !?[]u8 {
    if (env) |map| {
        const val = map.get(key) orelse return null;
        return @as(?[]u8, try allocator.dupe(u8, val));
    }
    return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
}

/// Read an env var and return it only when non-empty and absolute.
/// Returns null when absent, empty, or relative. Caller owns the result.
fn getAbsEnvVar(allocator: Allocator, env: ?*const EnvMap, key: []const u8) !?[]u8 {
    const val = try envGet(allocator, env, key) orelse return null;
    errdefer allocator.free(val);
    if (val.len == 0 or !fsp.isAbsolute(val)) {
        allocator.free(val);
        return null;
    }
    return val;
}

/// Return the user home directory. Checks HOME then USERPROFILE. Caller owns.
fn getHomeDir(allocator: Allocator, env: ?*const EnvMap) ![]u8 {
    if (try envGet(allocator, env, "HOME")) |h| return h;
    if (try envGet(allocator, env, "USERPROFILE")) |h| return h;
    return error.EnvironmentVariableNotFound;
}

/// Split a colon-separated list and append only absolute entries to `out`.
/// Uses the unmanaged ArrayList API (Zig 0.15): pass allocator to `append`.
fn collectAbsolutePaths(
    allocator: Allocator,
    list_str: []const u8,
    out: *std.ArrayList([]u8),
) !void {
    var iter = std.mem.splitScalar(u8, list_str, ':');
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

// ── Single-directory accessors ────────────────────────────────────────────────

/// `$XDG_DATA_HOME` or `$HOME/.local/share`. Caller must free.
pub fn xdgDataHome(allocator: Allocator, env: ?*const EnvMap) ![]u8 {
    if (try getAbsEnvVar(allocator, env, "XDG_DATA_HOME")) |v| return v;
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".local", "share" });
}

/// `$XDG_CONFIG_HOME` or `$HOME/.config`. Caller must free.
pub fn xdgConfigHome(allocator: Allocator, env: ?*const EnvMap) ![]u8 {
    if (try getAbsEnvVar(allocator, env, "XDG_CONFIG_HOME")) |v| return v;
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".config" });
}

/// `$XDG_STATE_HOME` or `$HOME/.local/state`. Caller must free.
pub fn xdgStateHome(allocator: Allocator, env: ?*const EnvMap) ![]u8 {
    if (try getAbsEnvVar(allocator, env, "XDG_STATE_HOME")) |v| return v;
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".local", "state" });
}

/// `$XDG_CACHE_HOME` or `$HOME/.cache`. Caller must free.
pub fn xdgCacheHome(allocator: Allocator, env: ?*const EnvMap) ![]u8 {
    if (try getAbsEnvVar(allocator, env, "XDG_CACHE_HOME")) |v| return v;
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".cache" });
}

/// `$HOME/.local/bin` (no env var override per spec). Caller must free.
pub fn xdgExecutableHome(allocator: Allocator, env: ?*const EnvMap) ![]u8 {
    const home = try getHomeDir(allocator, env);
    defer allocator.free(home);
    return std.mem.join(allocator, "/", &.{ home, ".local", "bin" });
}

/// `$XDG_RUNTIME_DIR` or null if unset.
/// Uses `getEnvVarOwned` for cross-platform compatibility (no posix.getenv).
/// Caller must free the returned slice when non-null.
pub fn xdgRuntimeDir(allocator: Allocator) !?[]u8 {
    return std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
}

// ── Directory list accessors ──────────────────────────────────────────────────

/// `[xdgDataHome] ++ $XDG_DATA_DIRS` (default: /usr/local/share, /usr/share).
/// Relative paths in the env var are silently skipped. Caller must `freeDirs`.
pub fn xdgDataDirs(allocator: Allocator, env: ?*const EnvMap) ![][]u8 {
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
/// Relative paths in the env var are silently skipped. Caller must `freeDirs`.
pub fn xdgConfigDirs(allocator: Allocator, env: ?*const EnvMap) ![][]u8 {
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

// ── File search helpers ───────────────────────────────────────────────────────

/// Search data dirs for a relative `resource` path; return first existing match.
/// Caller must free the returned path (when non-null).
pub fn findDataFile(allocator: Allocator, env: ?*const EnvMap, resource: []const u8) !?[]u8 {
    const dirs = try xdgDataDirs(allocator, env);
    defer freeDirs(allocator, dirs);
    for (dirs) |dir| {
        const candidate = try std.mem.join(allocator, "/", &.{ dir, resource });
        if (std.fs.accessAbsolute(candidate, .{})) |_| {
            return candidate;
        } else |_| {
            allocator.free(candidate);
        }
    }
    return null;
}

/// Search config dirs for a relative `resource` path; return first existing match.
/// Caller must free the returned path (when non-null).
pub fn findConfigFile(allocator: Allocator, env: ?*const EnvMap, resource: []const u8) !?[]u8 {
    const dirs = try xdgConfigDirs(allocator, env);
    defer freeDirs(allocator, dirs);
    for (dirs) |dir| {
        const candidate = try std.mem.join(allocator, "/", &.{ dir, resource });
        if (std.fs.accessAbsolute(candidate, .{})) |_| {
            return candidate;
        } else |_| {
            allocator.free(candidate);
        }
    }
    return null;
}

// ── Memory management ─────────────────────────────────────────────────────────

/// Free a slice of owned path strings returned by xdgDataDirs / xdgConfigDirs.
pub fn freeDirs(allocator: Allocator, dirs: [][]u8) void {
    for (dirs) |d| allocator.free(d);
    allocator.free(dirs);
}

// ── Unit tests ────────────────────────────────────────────────────────────────

fn makeEnv(allocator: Allocator) !EnvMap {
    var env = EnvMap.init(allocator);
    try env.put("HOME", "/home/testuser");
    return env;
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
    try env.put("XDG_DATA_DIRS", "/opt/data:/srv/data");
    const dirs = try xdgDataDirs(allocator, &env);
    defer freeDirs(allocator, dirs);
    try std.testing.expectEqual(@as(usize, 3), dirs.len);
    try std.testing.expectEqualStrings("/opt/data", dirs[1]);
    try std.testing.expectEqualStrings("/srv/data", dirs[2]);
}

test "xdgDataDirs: relative paths in XDG_DATA_DIRS are filtered out" {
    const allocator = std.testing.allocator;
    var env = try makeEnv(allocator);
    defer env.deinit();
    try env.put("XDG_DATA_DIRS", "/valid:relative_bad:/also_valid");
    const dirs = try xdgDataDirs(allocator, &env);
    defer freeDirs(allocator, dirs);
    // home + /valid + /also_valid (relative_bad filtered)
    try std.testing.expectEqual(@as(usize, 3), dirs.len);
    try std.testing.expectEqualStrings("/valid", dirs[1]);
    try std.testing.expectEqualStrings("/also_valid", dirs[2]);
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
