const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) {
        std.debug.print("Not enough arguments\n", .{});
        return 1;
    }
    const src_path = args[1];
    const dst_path = args[2];

    const src = try Io.Dir.cwd().readFileAlloc(io, src_path, arena, .unlimited);

    const dst_file = try Io.Dir.cwd().createFile(io, dst_path, .{});
    defer dst_file.close(io);
    var write_buf: [2048]u8 = undefined;
    var dst_writer = dst_file.writer(io, &write_buf);

    const encoder = std.base64.standard.Encoder;
    try encoder.encodeWriter(&dst_writer.interface, src);
    try dst_writer.flush();

    return 0;
}
