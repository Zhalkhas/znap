const std = @import("std");
const znap = @import("root.zig");

pub fn main() !void {
    const sock_path = std.posix.getenv("NIRI_SOCKET") orelse
        return error.MissingNiriSockPath;
    std.debug.print("connecting to {s}\n", .{sock_path});

    const listen_stream = try std.net.connectUnixSocket(sock_path);
    const cmd_stream = try std.net.connectUnixSocket(sock_path);

    try znap.run(listen_stream, cmd_stream);
}
