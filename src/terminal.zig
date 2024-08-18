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

const c = @cImport({
    @cDefine("_XOPEN_SOURCE", "600");
    @cDefine("_GNU_SOURCE", {});
    @cInclude("pty.h");
});

const Terminal = @This();

allocator: Allocator,
// reppresent 2d array as 1d array because nested ArrayLists dont have
// proper autocomplete
// https://github.com/zigtools/zls/issues/1392
cells: ArrayList(Cell),
rows: usize,
columns: usize,
cursor: Cursor = .{ .row = 0, .column = 0 },
master_pt: fs.File,

// based on alacritty and foot rendering
const BASE_FONT_SIZE = 12;
const BASE_CELL_WIDTH = 10;
const BASE_CELL_WIDTH_HEIGHT_RATIO = 2;

const master_pseudoterminal_path = "/dev/ptmx";

pub const Config = struct {
    font_size: i32 = 12,
    cell_height_scale: i32 = 1,
    cell_width_scale: i32 = 1,
    screen_height: i32 = 450,
    screen_width: i32 = 800,
};

pub fn init(allocator: Allocator, cfg: Terminal.Config) !Terminal {
    const cell_scale = math.divCeil(i32, cfg.font_size, BASE_FONT_SIZE) catch unreachable;
    const cell_width = cell_scale * BASE_CELL_WIDTH * cfg.cell_width_scale;
    const cell_height = cell_width * BASE_CELL_WIDTH_HEIGHT_RATIO * cfg.cell_height_scale;

    const rows = math.divFloor(i32, cfg.screen_height, cell_height) catch {
        @panic("failed to set rows");
    };

    const columns = math.divFloor(i32, cfg.screen_width, cell_width) catch {
        @panic("failed to set columns");
    };

    const cells = ArrayList(Cell).initCapacity(allocator, @intCast(columns * rows)) catch unreachable;

    var map = try process.getEnvMap(allocator);
    defer map.deinit();
    const max_env = 1000;
    var env: [max_env:null]?[*:0]u8 = undefined;

    var i: usize = 0;
    var iter = map.iterator();
    while (iter.next()) |entry| : (i += 1) {
        const keyval = try std.fmt.allocPrintZ(
            allocator,
            "{s}={s}",
            .{ entry.key_ptr.*, entry.value_ptr.* },
        );
        env[i] = keyval;
    } else {
        env[i] = null;
    }

    var master_pt = fs.File{ .handle = undefined };
    const pid = c.forkpty(&master_pt.handle, null, null, null);
    if (pid < 0) {
        @panic("forkpty failed");
    } else if (pid == 0) {
        const args = [_:null]?[*:0]u8{
            @constCast("bash"),
            null,
        };

        posix.execvpeZ(args[0].?, &args, &env) catch unreachable;
        process.cleanExit();
    }

    return Terminal{
        .allocator = allocator,
        .cells = cells,
        .rows = @intCast(rows),
        .columns = @intCast(columns),
        .master_pt = master_pt,
    };
}

pub fn deinit(self: *Terminal) void {
    self.cells.deinit();
    self.master_pt.close();
}

pub fn poll(self: *Terminal) !bool {
    var fds = [_]posix.pollfd{
        .{
            .fd = self.master_pt.handle,
            .events = posix.POLL.IN,
            .revents = undefined,
        },
    };
    const ready = try posix.poll(&fds, 0);
    return ready == 1;
}

pub fn read(self: *Terminal, buffer: []u8) !usize {
    return self.master_pt.read(buffer);
}

pub fn write(self: *Terminal, bytes: []const u8) !usize {
    return self.master_pt.write(bytes);
}

pub fn parseBytes(allocator: Allocator, bytes: []const u8) []Token {}

pub const Color = enum {
    red,
    blue,
    white,
    black,
    transparent,
};

pub const Cell = struct {
    text: u8,
    foreground: Color,
    background: Color,
};

pub const Cursor = struct {
    row: usize,
    column: usize,
};
