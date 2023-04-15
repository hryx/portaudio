const std = @import("std");

const HostApi = enum {
    alsa,
    asihpi,
    asio,
    coreaudio,
    dsound,
    jack,
    oss,
    wasapi,
    wdmks,
    wmme,

    const defaults_macos = [_]HostApi{.coreaudio};
    const defaults_linux = [_]HostApi{.alsa};
    const defaults_windows = [_]HostApi{.wasapi};

    // TODO: remove when std.Build can parse list of enums
    fn fromString(s: []const u8) HostApi {
        return std.meta.stringToEnum(HostApi, s) orelse {
            std.log.err("unknown host API '{s}'", .{s});
            std.debug.print("available options are:\n", .{});
            for (std.meta.fieldNames(HostApi)) |name| {
                std.debug.print("  {s}\n", .{name});
            }
            std.os.exit(1);
        };
    }
};

fn unsupportedOs(os: std.Target.Os.Tag) noreturn {
    std.log.err("unsupported OS: {s}", .{@tagName(os)});
    std.os.exit(1);
}

fn unsupportedHostApi(os: std.Target.Os.Tag, api: HostApi) noreturn {
    std.log.err("host API {s} is unsupported on {s}", .{ @tagName(api), @tagName(os) });
    std.os.exit(1);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const shared = b.option(bool, "shared", "Create shared library instead of static") orelse false;
    const lib = if (shared) b.addSharedLibrary(.{
        .name = "portaudio",
        .target = target,
        .optimize = optimize,
    }) else b.addStaticLibrary(.{
        .name = "portaudio",
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath("include");
    lib.addIncludePath("src/common");
    lib.addCSourceFiles(src_common, &.{});
    lib.linkLibC();

    const t = lib.target_info.target;

    // TODO: std.Build cannot parse list of enums yet
    // TODO: prevent duplicates
    const host_apis = blk: {
        const opt_strs = b.option([]const []const u8, "host-api", "Enable specific host audio APIs");
        if (opt_strs) |strs| {
            const opts = b.allocator.alloc(HostApi, strs.len) catch @panic("OOM");
            for (strs, opts) |s, *opt| {
                opt.* = HostApi.fromString(s);
            }
            break :blk opts;
        } else {
            break :blk switch (t.os.tag) {
                .macos => &HostApi.defaults_macos,
                .linux => &HostApi.defaults_linux,
                .windows => &HostApi.defaults_windows,
                else => unsupportedOs(t.os.tag),
            };
        }
    };

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    switch (t.os.tag) {
        .macos => {
            for (host_apis) |api| {
                switch (api) {
                    .coreaudio => {
                        try flags.append("-DPA_USE_COREAUDIO=1");
                        lib.addIncludePath("src/hostapi/coreaudio");
                        lib.addCSourceFiles(src_hostapi_coreaudio, &.{});
                        lib.linkFramework("AudioToolbox");
                        lib.linkFramework("AudioUnit");
                        lib.linkFramework("CoreAudio");
                        lib.linkFramework("CoreServices");
                    },
                    else => unsupportedHostApi(t.os.tag, api),
                }
            }
            lib.addIncludePath("src/os/unix");
            lib.addCSourceFiles(src_os_unix, flags.items);
        },
        .linux => {
            for (host_apis) |api| {
                switch (api) {
                    .alsa => {
                        try flags.append("-DPA_USE_ALSA=1");
                        lib.addIncludePath("src/hostapi/alsa");
                        lib.addCSourceFiles(src_hostapi_alsa, &.{});
                        lib.linkSystemLibrary("alsa");
                    },
                    .asihpi => {
                        try flags.append("-DPA_USE_ASIHPI=1");
                        lib.addIncludePath("src/hostapi/asihpi");
                        lib.addCSourceFiles(src_hostapi_asihpi, &.{});
                        lib.linkSystemLibrary("asihpi");
                    },
                    .jack => {
                        try flags.append("-DPA_USE_JACK=1");
                        lib.addIncludePath("src/hostapi/jack");
                        lib.addCSourceFiles(src_hostapi_jack, &.{});
                        lib.linkSystemLibrary("jack2");
                    },
                    .oss => {
                        try flags.append("-DPA_USE_OSS=1");
                        lib.addIncludePath("src/hostapi/oss");
                        lib.addCSourceFiles(src_hostapi_oss, &.{});
                    },
                    else => unsupportedHostApi(t.os.tag, api),
                }
            }
            lib.addIncludePath("src/os/unix");
            lib.addCSourceFiles(src_os_unix, flags.items);
        },
        .windows => {
            for (host_apis) |api| {
                switch (api) {
                    .asio => {
                        // lib.addIncludePath("src/hostapi/asio");
                        // lib.addCSourceFiles(src_hostapi_asio, &.{});
                        // try flags.append("-DPA_USE_ASIO=1");
                        std.log.err("TODO: ASIO on Windows", .{});
                        std.os.exit(1);
                    },
                    .dsound => {
                        try flags.append("-DPA_USE_DS=1");
                        lib.addIncludePath("src/hostapi/dsound");
                        lib.addCSourceFiles(src_hostapi_dsound, &.{});
                    },
                    .wasapi => {
                        try flags.append("-DPA_USE_WASAPI=1");
                        lib.addIncludePath("src/hostapi/wasapi");
                        lib.addCSourceFiles(src_hostapi_wasapi, &.{});
                    },
                    .wdmks => {
                        try flags.append("-DPA_USE_WDMKS=1");
                        lib.addIncludePath("src/hostapi/wdmks");
                        lib.addCSourceFiles(src_hostapi_wdmks, &.{});
                    },
                    .wmme => {
                        try flags.append("-DPA_USE_WMME=1");
                        lib.addIncludePath("src/hostapi/wmme");
                        lib.addCSourceFiles(src_hostapi_wmme, &.{});
                    },
                    else => unsupportedHostApi(t.os.tag, api),
                }
            }
            lib.addIncludePath("src/os/win");
            lib.addCSourceFiles(src_os_win, flags.items);
        },
        else => unsupportedOs(t.os.tag),
    }

    b.installArtifact(lib);
}

const src_common = &.{
    "src/common/pa_allocation.c",
    "src/common/pa_converters.c",
    "src/common/pa_cpuload.c",
    "src/common/pa_debugprint.c",
    "src/common/pa_dither.c",
    "src/common/pa_front.c",
    "src/common/pa_process.c",
    "src/common/pa_ringbuffer.c",
    "src/common/pa_stream.c",
    "src/common/pa_trace.c",
};

const src_os_unix = &.{
    "src/os/unix/pa_unix_hostapis.c",
    "src/os/unix/pa_unix_util.c",
};

const src_os_win = &.{
    "src/os/win/pa_win_coinitialize.c",
    "src/os/win/pa_win_hostapis.c",
    "src/os/win/pa_win_util.c",
    "src/os/win/pa_win_waveformat.c",
    "src/os/win/pa_win_wdmks_utils.c",
    "src/os/win/pa_x86_plain_converters.c",
};

const src_hostapi_alsa = &.{
    "src/hostapi/alsa/pa_linux_alsa.c",
};

const src_hostapi_asihpi = &.{
    "src/hostapi/asihpi/pa_linux_asihpi.c",
};

// const src_hostapi_asio = &.{
//     "src/hostapi/asio/iasiothiscallresolver.cpp",
//     "src/hostapi/asio/pa_asio.cpp",
// };

const src_hostapi_coreaudio = &.{
    "src/hostapi/coreaudio/pa_mac_core.c",
    "src/hostapi/coreaudio/pa_mac_core_blocking.c",
    "src/hostapi/coreaudio/pa_mac_core_utilities.c",
};

const src_hostapi_dsound = &.{
    "src/hostapi/dsound/pa_win_ds.c",
    "src/hostapi/dsound/pa_win_ds_dynlink.c",
};

const src_hostapi_jack = &.{
    "src/hostapi/jack/pa_jack.c",
};

const src_hostapi_oss = &.{
    "src/hostapi/oss/pa_unix_oss.c",
};

const src_hostapi_wasapi = &.{
    "src/hostapi/wasapi/pa_win_wasapi.c",
};

const src_hostapi_wdmks = &.{
    "src/hostapi/wdmks/pa_win_wdmks.c",
};

const src_hostapi_wmme = &.{
    "src/hostapi/wmme/pa_win_wmme.c",
};
