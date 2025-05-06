const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const document_module = b.addModule("document", .{
        .root_source_file = b.path("src/document.zig"),
    });

    const query_module = b.addModule("query", .{
        .root_source_file = b.path("src/query.zig"),
    });
    query_module.addImport("document", document_module);

    const storage_module = b.addModule("storage", .{
        .root_source_file = b.path("src/storage.zig"),
    });
    storage_module.addImport("document", document_module);

    const database_module = b.addModule("database", .{
        .root_source_file = b.path("src/database.zig"),
    });
    database_module.addImport("document", document_module);
    database_module.addImport("storage", storage_module);
    database_module.addImport("query", query_module);

    const utils_module = b.addModule("utils", .{
        .root_source_file = b.path("src/utils.zig"),
    });
    utils_module.addImport("query", query_module);

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
    exe.root_module.addImport("database", database_module);
    exe.root_module.addImport("query", query_module);
    exe.root_module.addImport("utils", utils_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the tinydb executable");
    run_step.dependOn(&run_cmd.step);

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

    const database_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_database.zig"),
        .target = target,
        .optimize = optimize,
    });
    database_tests.root_module.addImport("database", database_module);
    database_tests.root_module.addImport("document", document_module);
    database_tests.root_module.addImport("storage", storage_module);
    database_tests.root_module.addImport("query", query_module);
    test_step.dependOn(&database_tests.step);

    const query_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_query.zig"),
        .target = target,
        .optimize = optimize,
    });
    query_tests.root_module.addImport("query", query_module);
    query_tests.root_module.addImport("document", document_module);
    query_tests.root_module.addImport("database", database_module);
    query_tests.root_module.addImport("storage", storage_module);
    test_step.dependOn(&query_tests.step);

    const example = b.addExecutable(.{
        .name = "basic_usage",
        .root_source_file = b.path("examples/basic_usage.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("database", database_module);
    example.root_module.addImport("document", document_module);
    example.root_module.addImport("query", query_module);
    example.root_module.addImport("storage", storage_module);
    example.root_module.addImport("utils", utils_module);

    const example_run = b.addRunArtifact(example);
    const example_step = b.step("example", "Run basic usage example");
    example_step.dependOn(&example_run.step);
}
