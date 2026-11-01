// nice.zig: the heap, as test/rustheap.rs checks nice.rs's. It checks that
// a freed block is merged with its neighbor and reused, that an ArrayList
// and allocPrint work, that an alignment above 8 holds, that shrinking
// keeps the block, that the heap grows past the first page, and that it
// fails at the cap of --memory-pages 2. The output is that of rustheap.rs,
// but for the shrink: shrinkAndFree takes a length, and leaves the
// capacity at it, 2. main returns the number of lines it printed, 8.
const std = @import("std");
const nice = @import("nice");

const Aligned = struct { x: u8 align(64) };

export fn main() i32 {
    const a = nice.heap;

    // Blocks of 512 bytes each, header included: x and y next to each
    // other, and z after them. 1000 bytes need 1008. With only x free,
    // they come from the end of the heap; once y is freed and merged with
    // x, from x.
    const x = a.alloc(u8, 504) catch return -1;
    const y = a.alloc(u8, 504) catch return -1;
    const z = a.alloc(u8, 504) catch return -1;
    a.free(x);
    const p = a.alloc(u8, 1000) catch return -1;
    a.free(y);
    const q = a.alloc(u8, 1000) catch return -1;
    nice.print("{} {} {}\n", .{ y.ptr == x.ptr + 512, p.ptr != x.ptr, q.ptr == x.ptr });
    a.free(p);
    a.free(q);
    a.free(z);

    var v: std.ArrayList(u32) = .empty;
    for (0..1000) |i| v.append(a, @intCast(i * i)) catch return -1;
    var sum: u64 = 0;
    for (v.items) |e| sum += e;
    const s = std.fmt.allocPrint(a, "{s}-{d}", .{ "heap", sum }) catch return -1;
    nice.print("{s} {d}\n", .{ s, s.len });
    a.free(s);
    v.deinit(a);

    var boxes: [3]*Aligned = undefined;
    var ok = true;
    var bsum: u32 = 0;
    for (&boxes, 0..) |*b, i| {
        b.* = a.create(Aligned) catch return -1;
        b.*.x = @intCast(i);
    }
    for (boxes) |b| {
        ok = ok and @intFromPtr(b) % 64 == 0;
        bsum += b.x;
    }
    nice.print("{} {d}\n", .{ ok, bsum });
    for (boxes) |b| a.destroy(b);

    var w = std.ArrayList(u8).initCapacity(a, 100) catch return -1;
    w.appendSliceAssumeCapacity("abc");
    const wp = w.items.ptr;
    w.shrinkAndFree(a, 2);
    nice.print("{} {d}\n", .{ w.items.ptr == wp, w.capacity });
    w.deinit(a);

    // 80000 bytes are more than the first page has left.
    const before = @wasmMemorySize(0);
    var g: std.ArrayList(u32) = .empty;
    g.ensureTotalCapacityPrecise(a, 20000) catch return -1;
    for (0..20000) |i| g.appendAssumeCapacity(@intCast(i));
    var gsum: u64 = 0;
    for (g.items) |e| gsum += e;
    nice.print("{d} {d} {d}\n", .{ before, @wasmMemorySize(0), gsum });

    // The cap is 2 pages, so 80000 bytes more cannot be had, and the
    // memory stays at 2 pages.
    var h: std.ArrayList(u32) = .empty;
    const failed = if (h.ensureTotalCapacityPrecise(a, 20000)) false else |_| true;
    nice.print("{} {d}\n", .{ failed, @wasmMemorySize(0) });
    g.deinit(a);

    // With g freed, the same 80000 bytes fit.
    const fits = if (h.ensureTotalCapacityPrecise(a, 20000)) true else |_| false;
    nice.print("{}\n", .{fits});
    h.deinit(a);
    const huge = if (a.alloc(u8, 1 << 30)) |_| false else |_| true;
    nice.print("{}\n", .{huge});
    return 8;
}
