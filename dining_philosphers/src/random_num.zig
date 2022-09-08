const std = @import("std");
const print = std.debug.print;

test "Seed" {
    print("\n", .{});

    const seed = 123;
    var prng = std.rand.DefaultPrng.init(seed);

    var i: usize = 0;
    while (i < 5) : (i += 1)
        print("random i32[{d}]: {d}\n", .{ i, prng.random().int(i32) });

    print("\n", .{});
    i = 0;
    prng.seed(seed); // Reset the seed.

    while (i < 5) : (i += 1)
        print("random i32[{d}]: {d}\n", .{ i, prng.random().int(i32) });
}
