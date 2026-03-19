const std = @import("std");

pub fn build(b: *std.Build) void {
    const mod_name = "xdg";

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule(
        mod_name,
        .{
            .root_source_file = b.path("src/lib/root.zig"),
            .target = target,
            .optimize = optimize,
        },
    );

    const docs_step = b.step("docs", "Generate the documentation");

    const docs_lib = b.addLibrary(.{
        .name = mod_name,
        .root_module = lib_mod,
    });

    const docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs.step);

    const tests_step = b.step("tests", "Run the test suite");

    const test_suite = b.createModule(.{
        .root_source_file = b.path("tests/suite.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = mod_name, .module = lib_mod },
        },
    });

    const integration_tests = b.addTest(.{
        .name = "integration tests",
        .root_module = test_suite,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);
    tests_step.dependOn(&run_integration_tests.step);

    const unit_tests = b.addTest(.{
        .name = "unit tests",
        .root_module = lib_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    tests_step.dependOn(&run_unit_tests.step);
}
