const std = @import("std");
const fs = std.fs;
const ascii = std.ascii;
const heap = std.heap;
const process = std.process;
const posix = std.posix;
const linux = std.os.linux;

const Terminal = @import("terminal.zig");

const c = @cImport({
    @cDefine("_XOPEN_SOURCE", "600");
    @cDefine("_GNU_SOURCE", {});
    @cInclude("raylib.h");
    @cInclude("pty.h");
});

const screen_width = 800;
const screen_height = 450;

pub fn main() !void {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();
    var iter = env_map.iterator();
    const max_env = 1000;
    var env: [max_env:null]?[*:0]u8 = undefined;

    var index: usize = 0;
    while (iter.next()) |entry| : (index += 1) {
        const keyval = try std.fmt.allocPrintZ(allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* });
        env[index] = keyval;
    } else {
        env[index] = null;
    }

    var master = fs.File{ .handle = undefined };
    const procid = c.forkpty(&master.handle, null, null, null);

    const master_reader = master.reader();
    _ = master_reader; // autofix
    const master_writer = master.writer();

    switch (procid) {
        -1 => return error.ForkPty,
        0 => {
            const args = [_:null]?[*:0]u8{
                @constCast("bash"),
                null,
            };

            const result = posix.execvpeZ(args[0].?, &args, &env);

            // if we reach this, ggwp
            std.debug.print("goofed up = {any}", .{result});
        },
        else => {
            // c.SetConfigFlags(c.FLAG_VSYNC_HINT);
            c.InitWindow(screen_width, screen_height, "Smear");
            defer c.CloseWindow();

            var fds = [_]posix.pollfd{
                .{
                    .fd = master.handle,
                    .events = posix.POLL.IN,
                    .revents = undefined,
                },
            };
            const timeout_ms = 0;

            while (!c.WindowShouldClose()) {
                const buffer_size = 10000;
                var buffer: [buffer_size]u8 = undefined;

                var ready = try posix.poll(&fds, timeout_ms);
                while (ready == 1) {
                    _ = try master.reader().read(&buffer);
                    // std.debug.print("{s}", .{buffer});
                    ready = try posix.poll(&fds, timeout_ms);
                }

                var printable = false;
                var escape_code = false;
                for (buffer, 0..) |byte, i| {
                    printable = ascii.isPrint(byte);
                    if (printable) {}
                }

                var char: u8 = @intCast(c.GetCharPressed());
                while (char > 0) : (char = @intCast(c.GetCharPressed())) {
                    try master_writer.writeByte(char);
                }

                var key = c.GetKeyPressed();
                while (key > 0) : (key = c.etKeyPressed()) {
                    switch (key) {
                        c.KEY_THREE => try master_writer.writeByte('\n'),
                        c.KEY_COMMA => try master_writer.writeByte(8),
                        c.KEY_UP => try master_writer.writeAll(escape_codes.up.bytes()),
                        c.KEY_DOWN => try master_writer.writeAll(escape_codes.down.bytes()),
                        c.KEY_LEFT => try master_writer.writeAll(escape_codes.left.bytes()),
                        c.KEY_RIGHT => try master_writer.writeAll(escape_codes.right.bytes()),
                        else => continue,
                    }
                }

                c.BeginDrawing();

                c.ClearBackground(c.BLACK);
                c.DrawFPS(screen_width * 0.9, screen_height * 0.9);

                c.EndDrawing();
            }
        },
    }
}

const escape_codes = enum {
    up,
    down,
    left,
    right,
    invisible_text,
    blinking,

    fn bytes(self: escape_codes) []const u8 {
        return switch (self) {
            .up => "\x1BOA",
            .down => "\x1BOB",
            .right => "\x1BOC",
            .left => "\x1BOD",
            .invisible_text => "\x1B[8m",
            .blinking => "\x1B[5m",
        };
    }
};
