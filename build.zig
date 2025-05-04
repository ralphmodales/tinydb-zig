const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "tinydb",
        .root_source_file = b.path("src/database.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "tinydb",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the tinydb executable");
    run_step.dependOn(&run_cmd.step);

    const document_module = b.addModule("document", .{
        .root_source_file = b.path("src/document.zig"),
    });

    const storage_module = b.addModule("storage", .{
        .root_source_file = b.path("src/storage.zig"),
    });
    storage_module.addImport("document", document_module);

    const test_step = b.step("test", "Run all tests");

    const document_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_document.zig"),
        .target = target,
        .optimize = optimize,
    });
    document_tests.root_module.addImport("document", document_module);
    test_step.dependOn(&document_tests.step);

    const storage_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_storage.zig"),
        .target = target,
        .optimize = optimize,
    });
    storage_tests.root_module.addImport("storage", storage_module);
    storage_tests.root_module.addImport("document", document_module);
    test_step.dependOn(&storage_tests.step);

    const example = b.addExecutable(.{
        .name = "basic_usage",
        .root_source_file = b.path("examples/basic_usage.zig"),
        .target = target,
        .optimize = optimize,
    });
    const example_run = b.addRunArtifact(example);
    const example_step = b.step("example", "Run basic usage example");
    example_step.dependOn(&example_run.step);
}
