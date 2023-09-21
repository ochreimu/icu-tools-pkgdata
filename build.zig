const std = @import("std");
const builtin = @import("builtin");

const version = std.SemanticVersion.parse("74.0.0") catch unreachable;

pub fn build(b: *std.Build) !void {
    const Linkage = std.Build.Step.Compile.Linkage;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(Linkage, "linkage", "The linking mode for libraries") orelse .static;
    const build_data_without_assembly = b.option(bool, "buildDataWithoutAssembly", "Should build data without Assembly") orelse false;
    const can_write_obj_code = b.option(bool, "canWriteObjectCode", "Can write object code") orelse false;
    const use_stub = b.option(bool, "useStubData", "Use stub data library") orelse false;
    const exe_name = "pkgdata";
    const icudt_name = std.fmt.comptimePrint("icudt{d}", .{version.major});

    const exe = std.Build.Step.Compile.create(b, .{
        .name = exe_name,
        .kind = .exe,
        .target = target,
        .optimize = optimize,
    });

    const common = b.dependency("common", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });
    const icuuc = common.artifact("icuuc");

    const internationalization = b.dependency("internationalization", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });
    const icui18n = internationalization.artifact("icui18n");

    const toolutil = b.dependency("toolutil", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .canGenerateObjects = can_write_obj_code,
    });
    const icutu = toolutil.artifact("icutu");

    // TODO: To be continued when ICUDT can be compiled. This tool depends on ICUDT.
    const data = b.dependency(if (use_stub) "stubdata" else "data", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });
    const icudt = data.artifact(icudt_name);

    // HACK This is an ugly hack
    const icuuc_root = common.builder.pathFromRoot("cpp");
    const icui18n_root = internationalization.builder.pathFromRoot("cpp");
    const icutu_root = toolutil.builder.pathFromRoot("cpp");

    // Configuration
    if (build_data_without_assembly) exe.defineCMacro("BUILD_DATA_WITHOUT_ASSEMBLY", null);
    if (can_write_obj_code) exe.defineCMacro("CAN_WRITE_OBJ_CODE", null);

    exe.linkLibCpp();
    exe.linkLibrary(icuuc);
    exe.linkLibrary(icui18n);
    exe.linkLibrary(icutu);
    exe.linkLibrary(icudt);
    exe.installLibraryHeaders(icuuc);
    exe.installLibraryHeaders(icui18n);
    exe.installLibraryHeaders(icutu);
    exe.installLibraryHeaders(icudt);

    addSourceFiles(b, exe, &.{ "-fno-exceptions", "-Icpp", "-I", icuuc_root, "-I", icui18n_root, "-I", icutu_root }) catch @panic("OOM");
    b.installArtifact(exe);
}

fn addSourceFiles(b: *std.Build, artifact: *std.Build.Step.Compile, flags: []const []const u8) !void {
    var files = std.ArrayList([]const u8).init(b.allocator);
    var sources_txt = try std.fs.cwd().openFile(b.pathFromRoot("cpp/sources.txt"), .{});
    var reader = sources_txt.reader();
    var buffer: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |l| {
        const line = std.mem.trim(u8, l, " \t\r\n");
        try files.append(b.pathJoin(&.{ "cpp", line }));
    }

    artifact.addCSourceFiles(files.items, flags);
}
