pub const std_options_debug_io: std.Io = std.Io.failing;
const std = @import("std");
const log = @import("log.zig");
const api = @import("api.zig");

const vec = @import("vec_simd.zig");
const Vec = vec.Vec;

const globals = @import("globals.zig");
const ctx = &globals.ctx;
const conf = &globals.conf;

var redraw_frame: bool = true;

var pieces: []globals.Piece = undefined;

const Cursor = struct {
    old_pos: Vec = .fromScalar(0),
    pos: Vec = .fromScalar(0),
    delta: Vec = .fromScalar(0),

    dragging: bool = false,

    fn updateDelta(m: *Cursor) void {
        m.delta = m.pos.subVec(m.old_pos);
        m.old_pos = m.pos;
    }
};
const max_touches = 10;
var cursors: [1 + max_touches]Cursor = @splat(.{});

inline fn mouseIdx() usize {
    return 0;
}
inline fn touchIdx(i: usize) usize {
    return 1 + i;
}

export fn setConf(bg_color: u32, shadow_color: u32,
                  frame_color: u32, frame_width: f32,
                  border_width: f32, dragging_offset: f32,
                  puzzle_w: u32, puzzle_h: u32,
                  snap_radius: f32,
                  reserved_frame_scale: f32,
                  bounce_xvel: f32, bounce_yvel: f32,
                  bounce_slowing: f32, g: f32) void {
    conf.* = .{
        .bg_color = @bitCast(bg_color),
        .shadow_color = @bitCast(shadow_color),
        .frame_color = @bitCast(frame_color),
        .frame_width = frame_width,
        .border_width = border_width,
        .dragging_offset = dragging_offset,
        .puzzle_w = @intCast(puzzle_w),
        .puzzle_h = @intCast(puzzle_h),
        .snap_radius = snap_radius,
        .reserved_frame_scale = reserved_frame_scale,
        .bounce_xvel = bounce_xvel,
        .bounce_yvel = bounce_yvel,
        .bounce_slowing = bounce_slowing,
        .g = g,
    };
}

export fn init(win_w: f32, win_h: f32, img_w: u32, img_h: u32, seed: u64) bool {
    if (win_w == 0 or win_h == 0 or img_w == 0 or img_h == 0) return false;
    ctx.* = .init(win_w, win_h, img_w, img_h, seed);

    // Init pieces
    var gpa = std.heap.wasm_allocator;
    pieces = gpa.alloc(globals.Piece, ctx.misplaced_pieces) catch return false;

    for (pieces, 0..) |*piece, i| {
        const grid_pos = Vec.fromXY(@floatFromInt(i % conf.puzzle_w),
                                    @floatFromInt(@divFloor(i, conf.puzzle_w)));
        const pos = grid_pos.mulVec(ctx.piece_sz)
            .mulScalar(conf.reserved_frame_scale)
            .addVec(Vec.fromXY(ctx.frame_sz.x(), 0));
        const img_rect_sz = ctx.img_sz.divVec(.fromXY(conf.puzzle_w, conf.puzzle_h));
        const img_pos = grid_pos.mulVec(img_rect_sz);
        piece.* = .init(pos, img_pos);
    }
    // Shuffle
    const rng = ctx.prng.random();
    for (0..pieces.len - 1) |i| {
        const j: usize = rng.intRangeLessThan(usize, i + 1, pieces.len);
        std.mem.swap(Vec, &pieces[i].pos, &pieces[j].pos);
    }
    return true;
}

export fn resizeWin(win_w: u32, win_h: u32) void {
    ctx.win_sz = .fromXY(@floatFromInt(win_w), @floatFromInt(win_h));

    const old_scale = ctx.img_scale;
    ctx.updateScale();
    const scale_dt = old_scale / ctx.img_scale;

    for (pieces) |*piece| {
        piece.pos = piece.pos.mulScalar(scale_dt);
    }

    redraw_frame = true;
}




/// Find piece under cursor, move it to top ensuring other dragging indices
/// preserved.
/// Return true if there were piece under cursor.
fn fixatePieceUnderCursor(cursor_i: usize) bool {
    const cursor = &cursors[cursor_i];
    for (pieces[0..ctx.misplaced_pieces], 0..) |piece, i| {
        if (piece.dragged_by != null or
            !vec.isPointInsideRect(cursor.pos, piece.pos, ctx.piece_sz)) continue;

        @memmove(pieces[1..i+1], pieces.ptr);
        pieces[0] = piece;

        pieces[0].dragged_by = cursor_i;
        cursor.dragging = true;
        redraw_frame = true;
        return true;
    }

    return false;
}

/// touchstart. Return index of touch + 1 in touches or 0 if no piece fixated.
/// Maybe should use Touch.radius[XY] for finding piece under.
export fn eventTouchNew(x: f32, y: f32) usize {
    for (0..max_touches) |i| {
        const touch = &cursors[touchIdx(i)];
        if (touch.dragging) continue;
        touch.pos = .fromXY(x, y);

        if (fixatePieceUnderCursor(touchIdx(i))) {
            touch.old_pos = touch.pos;
            touch.delta = Vec.fromXY(x, y);
            return touchIdx(i);
        }
        break;
    }
    return 0;
}

/// mousedown
export fn eventMouseDown() void {
    _ = fixatePieceUnderCursor(mouseIdx());
}

/// mouseup / touchend
export fn eventCursorUp(idx: usize) void {
    if (cursors[idx].dragging) {
        cursors[idx].dragging = false;
        redraw_frame = true;
    }
}

/// mousemove / touchmove
export fn eventCursorMove(idx: usize, x: f32, y: f32) void {
    cursors[idx].pos = .fromXY(x, y);
}

/// Check if piece is still dragged, and set dragged_by to null if not.
fn updatePieceDraggedStatus(piece: *globals.Piece) void {
    if (piece.dragged_by) |cursor_i| {
        if (!cursors[cursor_i].dragging) piece.dragged_by = null;
    }
}

fn dragAllPieces(dt: f32) void {
    var n: usize = 1;
    while (n <= ctx.misplaced_pieces) : (n += 1) {
        const i = n - 1;
        updatePieceDraggedStatus(&pieces[i]);
        if (pieces[i].dragged_by) |cursor| {
            pieces[i].drag(dt, cursors[cursor].delta);
        } else {
            pieces[i].inertion(dt);
        }
        redraw_frame = pieces[i].move(dt) or redraw_frame;

        if (pieces[i].trySnap()) {
            ctx.misplaced_pieces -= 1;
            const moving_piece = pieces[i];
            @memmove(pieces[i..ctx.misplaced_pieces], pieces.ptr + i + 1);
            pieces[ctx.misplaced_pieces] = moving_piece;
            n -= 1;
        }
    }
}


fn startBouncing() void {
    const rng = ctx.prng.random();
    for (pieces) |*piece| {
        const xdir = @as(f32, rng.int(u1)) * 2 - 1;
        piece.vel = .fromXY(conf.bounce_xvel * (0.5 + rng.float(f32)) * xdir,
                            -conf.bounce_yvel * (0.5 + rng.float(f32)));
    }
}

export fn timeoutPassed() void {
    startBouncing();
    ctx.misplaced_pieces = pieces.len;
    ctx.state = .win;
}

pub extern "env" fn win() void;

export fn update(dt_unlim: f32) void {
    const dt = if (dt_unlim > 0.5) 0.5 else dt_unlim;

    for (cursors[0..]) |*cursor| {
        cursor.updateDelta();
    }

    switch (ctx.state) {
        .in_progress => {
            if (ctx.misplaced_pieces > 0) {
                dragAllPieces(dt);
            } else {
                win();
                ctx.state = .timeout;
            }
        },
        .timeout => {},
        .win => {
            for (pieces) |*piece| {
                updatePieceDraggedStatus(piece);
                if (piece.dragged_by) |cursor| {
                    piece.drag(dt, cursors[cursor].delta);
                } else {
                    piece.bounce(dt);
                }
                redraw_frame = piece.move(dt) or redraw_frame;
            }
        },
    }

    if (redraw_frame) {
        api.redrawFrame(pieces);
        redraw_frame = false;
    }
}
