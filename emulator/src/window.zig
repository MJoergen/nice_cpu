//! The window of `--window` (doc/DEVICES.md §1), on SDL 3. It shows the
//! frame of frame.zig and queues the keys of keys.zig. Only a build with
//! `-Dwindow` has it.

const std = @import("std");
const c = @import("sdl");
const cpu_ = @import("cpu.zig");
const Cpu = cpu_.Cpu;
const frame = @import("frame.zig");
const keys = @import("keys.zig");

/// The time between two redraws, about 60 a second.
const redraw_ms = 16;
/// The time of each half of the cursor's blink, so that it blinks about
/// twice a second.
const blink_ms = 250;

pub const Window = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,
    frame: frame.Frame,
    /// The rows that the window shows.
    size: frame.Size,
    /// The console's input, which the keys go into.
    queue: keys.Queue,
    /// The SDL time of the last redraw, in ms.
    drawn_at: u64 = 0,

    /// Open the window, as high as the rows of `size`. `file` is the input
    /// of `--input`, if given, which the console reads before the keys.
    pub fn open(self: *Window, gpa: std.mem.Allocator, invert: bool, size: frame.Size, file: ?*std.Io.Reader) !void {
        const height: c_int = @intCast(size.height());
        // A signal ends the run as without the window, not as a close.
        _ = c.SDL_SetHint(c.SDL_HINT_NO_SIGNAL_HANDLERS, "1");
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return sdlError("SDL_Init");
        errdefer c.SDL_Quit();
        var window: ?*c.SDL_Window = null;
        var renderer: ?*c.SDL_Renderer = null;
        if (!c.SDL_CreateWindowAndRenderer("niceemu", frame.width, height, c.SDL_WINDOW_RESIZABLE, &window, &renderer))
            return sdlError("SDL_CreateWindowAndRenderer");
        errdefer c.SDL_DestroyWindow(window);
        errdefer c.SDL_DestroyRenderer(renderer);
        // A resized window scales the frame and keeps its aspect.
        if (!c.SDL_SetRenderLogicalPresentation(renderer, frame.width, height, c.SDL_LOGICAL_PRESENTATION_LETTERBOX))
            return sdlError("SDL_SetRenderLogicalPresentation");
        const texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STREAMING, frame.width, height) orelse
            return sdlError("SDL_CreateTexture");
        errdefer c.SDL_DestroyTexture(texture);
        _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST);
        if (!c.SDL_StartTextInput(window)) return sdlError("SDL_StartTextInput");
        self.* = .{
            .window = window.?,
            .renderer = renderer.?,
            .texture = texture,
            .frame = try frame.Frame.init(gpa, invert),
            .size = size,
            .queue = .{ .file = file },
        };
    }

    pub fn close(self: *Window, gpa: std.mem.Allocator) void {
        self.frame.deinit(gpa);
        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    /// Handle the events that have come, waiting up to `timeout_ms` for
    /// the first, and redraw the screen at `base` if it is time. Returns
    /// false when the window has been closed.
    pub fn pump(self: *Window, cpu: *const Cpu, base: u32, timeout_ms: i32) bool {
        var ev: c.SDL_Event = undefined;
        var got = if (timeout_ms > 0) c.SDL_WaitEventTimeout(&ev, timeout_ms) else c.SDL_PollEvent(&ev);
        while (got) : (got = c.SDL_PollEvent(&ev)) {
            if (!self.handle(&ev)) return false;
        }
        const now = c.SDL_GetTicks();
        if (now -% self.drawn_at >= redraw_ms) {
            self.drawn_at = now;
            self.redraw(cpu, base, now / blink_ms % 2 == 0);
        }
        return true;
    }

    /// Queue the bytes of a key event. Returns false for a close.
    fn handle(self: *Window, ev: *const c.SDL_Event) bool {
        switch (ev.type) {
            c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => return false,
            c.SDL_EVENT_KEY_DOWN => {
                if (control(ev.key.key, ev.key.mod)) |b| {
                    self.queue.push(&.{b});
                } else if (key(ev.key.key)) |k| self.queue.push(keys.bytes(k));
            },
            c.SDL_EVENT_TEXT_INPUT => {
                // Ctrl with a letter is the key event's, above.
                if (c.SDL_GetModState() & c.SDL_KMOD_CTRL != 0) return true;
                const text = std.mem.span(ev.text.text);
                for (text) |b| {
                    if (keys.typed(b)) self.queue.push(&.{b});
                }
            },
            else => {},
        }
        return true;
    }

    /// Draw the cells or the pixels that changed, as the mode word selects
    /// (doc/DEVICES.md §1.10), and show the frame.
    fn redraw(self: *Window, cpu: *const Cpu, base: u32, blink_on: bool) void {
        if (self.drawn(cpu, base, blink_on)) {
            _ = c.SDL_UpdateTexture(self.texture, null, self.frame.pixels.ptr, frame.width * 4);
        }
        _ = c.SDL_RenderClear(self.renderer);
        _ = c.SDL_RenderTexture(self.renderer, self.texture, null, null);
        _ = c.SDL_RenderPresent(self.renderer);
    }

    /// Draw the frame, and return whether it changed. The rows after those
    /// of the size are drawn black, below the texture.
    fn drawn(self: *Window, cpu: *const Cpu, base: u32, blink_on: bool) bool {
        if (cpu.peek(cpu_.screen_mode) == cpu_.mode_chunky) {
            var px: [frame.pixels]u32 = @splat(0);
            cpu.mem.peekWords(base, px[0 .. self.size.pixel_rows * frame.pixel_cols]);
            return self.frame.drawPixels(&px);
        }
        var glyphs: frame.Glyphs = undefined;
        var words: [frame.cells]u32 = @splat(0);
        for (words[0 .. self.size.rows * frame.cols], 0..) |*w, i| w.* = cpu.peek(base +% @as(u32, @intCast(i)));
        const cursor: frame.Cursor = .{
            .state = cpu.peek(frame.cursor_base),
            .col = cpu.peek(frame.cursor_base + 1),
            .row = cpu.peek(frame.cursor_base + 2),
        };
        return self.frame.draw(&words, frame.fontOf(cpu, &glyphs), cursor, blink_on);
    }
};

/// The control code of a key event: Ctrl with a letter, but not with Alt
/// too, as AltGr is Ctrl and Alt on some layouts, and types a character.
fn control(code: c.SDL_Keycode, mod: c.SDL_Keymod) ?u8 {
    if (mod & c.SDL_KMOD_CTRL == 0 or mod & c.SDL_KMOD_ALT != 0) return null;
    if (code >= 0x80) return null;
    return keys.ctrl(@intCast(code));
}

/// The key of an SDL keycode, if it is one that does not type a character.
fn key(code: c.SDL_Keycode) ?keys.Key {
    return switch (code) {
        c.SDLK_RETURN, c.SDLK_KP_ENTER => .enter,
        c.SDLK_BACKSPACE => .backspace,
        c.SDLK_DELETE => .delete,
        c.SDLK_TAB => .tab,
        c.SDLK_ESCAPE => .escape,
        c.SDLK_UP => .up,
        c.SDLK_DOWN => .down,
        c.SDLK_RIGHT => .right,
        c.SDLK_LEFT => .left,
        c.SDLK_F1 => .f1,
        c.SDLK_F2 => .f2,
        c.SDLK_F3 => .f3,
        c.SDLK_F4 => .f4,
        c.SDLK_F5 => .f5,
        c.SDLK_F6 => .f6,
        c.SDLK_F7 => .f7,
        c.SDLK_F8 => .f8,
        c.SDLK_F9 => .f9,
        c.SDLK_F10 => .f10,
        c.SDLK_F11 => .f11,
        c.SDLK_F12 => .f12,
        else => null,
    };
}

fn sdlError(what: []const u8) error{Sdl} {
    std.debug.print("niceemu: {s}: {s}\n", .{ what, c.SDL_GetError() });
    return error.Sdl;
}

const testing = std.testing;

test "the keys that type no character, from SDL's keycodes" {
    try testing.expectEqual(.enter, key(c.SDLK_RETURN));
    try testing.expectEqual(.enter, key(c.SDLK_KP_ENTER));
    try testing.expectEqual(.backspace, key(c.SDLK_BACKSPACE));
    try testing.expectEqual(.delete, key(c.SDLK_DELETE));
    try testing.expectEqual(.escape, key(c.SDLK_ESCAPE));
    try testing.expectEqual(.left, key(c.SDLK_LEFT));
    try testing.expectEqual(.f1, key(c.SDLK_F1));
    try testing.expectEqual(.f12, key(c.SDLK_F12));
    // Characters come as text input.
    try testing.expectEqual(null, key(c.SDLK_C));
    try testing.expectEqual(null, key(c.SDLK_SPACE));
    try testing.expectEqual(null, key(c.SDLK_LSHIFT));
}

test "Ctrl with a letter gives its control code, but not with Alt" {
    try testing.expectEqual(0x03, control(c.SDLK_C, c.SDL_KMOD_LCTRL));
    try testing.expectEqual(0x1A, control(c.SDLK_Z, c.SDL_KMOD_RCTRL | c.SDL_KMOD_LSHIFT));
    try testing.expectEqual(null, control(c.SDLK_C, c.SDL_KMOD_NONE));
    try testing.expectEqual(null, control(c.SDLK_C, c.SDL_KMOD_LSHIFT));
    try testing.expectEqual(null, control(c.SDLK_C, c.SDL_KMOD_LCTRL | c.SDL_KMOD_RALT));
    try testing.expectEqual(null, control(c.SDLK_RETURN, c.SDL_KMOD_LCTRL));
    try testing.expectEqual(null, control(c.SDLK_F1, c.SDL_KMOD_LCTRL));
}

/// Whether the lines of the frame above `lines` are all white, and those
/// from it on all black.
fn whiteAbove(f: *const frame.Frame, lines: usize) bool {
    for (f.pixels, 0..) |p, i| {
        const want: u32 = if (i / frame.width < lines) 0xFFFF_FFFF else 0xFF00_0000;
        if (p != want) return false;
    }
    return true;
}

/// The color of a pixel of a surface, as 0xRRGGBB.
fn colorAt(surface: *c.SDL_Surface, x: c_int, y: c_int) !u32 {
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    if (!c.SDL_ReadSurfacePixel(surface, x, y, &r, &g, &b, null)) return sdlError("SDL_ReadSurfacePixel");
    return @as(u32, r) << 16 | @as(u32, g) << 8 | b;
}

test "the window is as high as its rows, and shows no word after them (DEVICES §1.1, §1.3)" {
    // The window is 1280×896, and 1280×800 with -2004, whose screen is at
    // 0x400.
    const cases = [_]struct { size: frame.Size, base: u32, lines: c_int }{
        .{ .size = frame.size_full, .base = 0xFFFF_0000, .lines = 896 },
        .{ .size = frame.size_2004, .base = 0x400, .lines = 800 },
    };
    for (cases) |case| {
        // SDL's dummy video driver needs no display. SDL_Quit, in close,
        // forgets the hint, so each window sets it.
        _ = c.SDL_SetHintWithPriority(c.SDL_HINT_VIDEO_DRIVER, "dummy", c.SDL_HINT_OVERRIDE);
        var cpu = Cpu.init(testing.allocator);
        defer cpu.deinit();
        // White on white in all the words of the full screen, in either
        // mode. With -2004, the words after its rows are the program's,
        // and must not show.
        for (0..frame.pixels) |i| try cpu.write(case.base + @as(u32, @intCast(i)), 0xFFFF_FF20);
        var w: Window = undefined;
        try w.open(testing.allocator, false, case.size, null);
        defer w.close(testing.allocator);
        var width: c_int = 0;
        var height: c_int = 0;
        try testing.expect(c.SDL_GetWindowSize(w.window, &width, &height));
        try testing.expectEqual(1280, width);
        try testing.expectEqual(case.lines, height);
        for ([_]u32{ 0, cpu_.mode_chunky }) |mode| {
            try cpu.write(cpu_.screen_mode, mode);
            w.redraw(&cpu, case.base, true);
            // The frame is black after the rows of the size.
            try testing.expect(whiteAbove(&w.frame, @intCast(case.lines)));
            // And the window shows the lines before that, with its last
            // row at its bottom edge.
            const shot: *c.SDL_Surface = c.SDL_RenderReadPixels(w.renderer, null) orelse return sdlError("SDL_RenderReadPixels");
            defer c.SDL_DestroySurface(shot);
            try testing.expectEqual(1280, shot.w);
            try testing.expectEqual(case.lines, shot.h);
            for ([_]c_int{ 0, 1279 }) |x| {
                for ([_]c_int{ 0, case.lines - 1 }) |y| try testing.expectEqual(0xFFFFFF, try colorAt(shot, x, y));
            }
        }
    }
}
