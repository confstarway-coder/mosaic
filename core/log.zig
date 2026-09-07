extern "env" fn log(ptr: [*]const u8, len: usize) void;

const std = @import("std");


var log_buf: [1024]u8 = undefined;
var log_len: usize = 0;

pub fn write(msg: []const u8) void {
    log(msg.ptr, msg.len);
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&log_buf, fmt, args) catch @as([]const u8, "Error during logging");
    log(msg.ptr, msg.len);
}
