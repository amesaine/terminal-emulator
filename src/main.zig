// Variables in SCREAMING_CASE have arbitrary values

const std = @import("std");
const ArrayList = std.ArrayList;
const mem = std.mem;
const Allocator = mem.Allocator;
const math = std.math;
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

var scratch_buffer: [math.maxInt(u16)]u8 = undefined;

pub fn main() !void {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    const allocator = arena.allocator();

    const width = 800;
    const height = 450;
    const font_size = 12;
    c.InitWindow(width, height, "Smear");
    defer c.CloseWindow();

    var terminal = try Terminal.init(allocator, .{});
    defer terminal.deinit();

    const font = c.LoadFontEx("assets/0xProto/0xProto_Regular.otf", font_size, 0, 250);
    _ = font;

    while (!c.WindowShouldClose()) {
        while (try terminal.poll() == true) {
            _ = try terminal.read(&scratch_buffer);
            std.debug.print("{s}\n", .{scratch_buffer});
            scratch_buffer = undefined;
        }

        c.BeginDrawing();
        c.ClearBackground(c.BLACK);

        c.EndDrawing();
    }
}
