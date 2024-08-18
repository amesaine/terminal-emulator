const std = @import("std");

pub const Name = enum {
    up,
    down,
    right,
    left,
    up_n,
    down_n,
    right_n,
    left_n,
};

pub const Code = std.StaticStringMap(Name).initComptime(.{
    .{ "\x1BOA", .up },
    .{ "\x1BOB", .down },
    .{ "\x1BOC", .right },
    .{ "\x1BOD", .left },
});
