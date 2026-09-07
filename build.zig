const std = @import("std");
const Build = std.Build;

const exe_name = "app";

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.resolveTargetQuery(.{
        .cpu_arch        = .wasm32,
        .os_tag          = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            .simd128,
            .bulk_memory,
            .nontrapping_fptoint,
            .sign_ext,
        }),
    });


    // --- Module ---
    // In Zig 0.16.0, addExecutable requires a pre-built Module via
    // b.createModule(). The old flat-field API (passing root_source_file
    // directly to addExecutable) was removed in 0.14.0 and is gone.
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("core/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Executable ---
    // Despite the name "Executable", this also produces .wasm libraries.
    // A WASM "library" with exported functions is still technically an
    // executable from the linker's perspective.
    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = wasm_module,
    });
    exe.entry = .disabled;
    exe.rdynamic = true; // Dont optimize out exported symbols

    // --- Install ---
    // Copies the final .wasm into zig-out/bin/.
    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);

    // Additional optimization via wasm_opt
    const wasm_opt = b.addSystemCommand(&.{
        b.fmt("{s}/util/wasm-opt.sh", .{b.build_root.path orelse "./"}),
        "-q", "--enable-simd", "--enable-bulk-memory",
        "--enable-nontrapping-float-to-int", "--enable-sign-ext",
        if (optimize == .Debug) "-g" else "--strip-debug",
        switch (optimize) {
            .ReleaseFast => "-O3",
            .ReleaseSafe => "-O2",
            .ReleaseSmall => "-Oz",
            .Debug => "-O0",
        },
    });
    wasm_opt.addArg("-o");
    const optimized = wasm_opt.addOutputFileArg(exe_name++".wasm");
    wasm_opt.addFileArg(exe.getEmittedBin());
    const install_optimized = b.addInstallFileWithDir(optimized, .bin, exe_name++".wasm");
    b.getInstallStep().dependOn(&install_optimized.step);

    // Generate base64 encoded exe for embedding into js
    const base64_encoder = b.addExecutable(.{
        .name = "base64_encoder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("util/base64_encoder.zig"),
            .target = b.graph.host,
        }),
    });
    const encoder_step = b.addRunArtifact(base64_encoder);
    encoder_step.addFileArg(optimized);
    const encoded = encoder_step.addOutputFileArg(exe_name++".base64");
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(encoded, .bin, exe_name++".base64").step);
}
