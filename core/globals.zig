const Random = @import("std").Random;
const vec = @import("vec_simd.zig");
const Vec = vec.Vec;

pub const Color = packed struct(u32) {
    a: u8,
    b: u8,
    g: u8,
    r: u8,
};


pub const Ctx = struct {
    state: enum {in_progress, timeout, win},

    win_sz: Vec,
    img_sz: Vec,

    img_scale: f32, // image to frame scale
    frame_sz: Vec,
    piece_sz: Vec,
    img_piece_sz: Vec,
    base_scalar: f32,
    frame_diagonal: f32,

    misplaced_pieces: u32,

    prng: Random.DefaultPrng,

    pub fn init(win_w: f32, win_h: f32, img_w: u32, img_h: u32, seed: u64) Ctx {
        var c: Ctx = undefined;
        c.state = .in_progress;
        c.win_sz = Vec.fromXY(win_w, win_h);
        c.img_sz = Vec.fromXY(@floatFromInt(img_w), @floatFromInt(img_h));
        c.img_piece_sz = c.img_sz.divVec(.fromXY(conf.puzzle_w, conf.puzzle_h));
        c.misplaced_pieces = conf.puzzle_w * conf.puzzle_h;
        c.prng = .init(seed);
        c.updateScale();

        return c;
    }

    pub fn updateScale(c: *Ctx) void {
        c.img_scale = @max((c.img_sz.x() * (1 + conf.reserved_frame_scale)) / c.win_sz.x(),
                           c.img_sz.y() / c.win_sz.y());
        c.frame_sz = c.img_sz.divScalar(c.img_scale);
        c.piece_sz = c.frame_sz.divVec(.fromXY(conf.puzzle_w, conf.puzzle_h));
        c.base_scalar = c.win_sz.module();
        c.frame_diagonal = c.frame_sz.module();
    }
};
pub var ctx: Ctx = undefined;

pub var conf: struct {
    bg_color: Color,
    shadow_color: Color,

    frame_color: Color,
    frame_width: f32,

    border_width: f32,
    dragging_offset: f32,

    puzzle_w: u16,
    puzzle_h: u16,

    snap_radius: f32,

    reserved_frame_scale: f32,

    bounce_xvel: f32,
    bounce_yvel: f32,
    bounce_slowing: f32,

    g: f32,
} = undefined;

pub const Piece = struct {
    pos: Vec,
    img_pos: Vec,
    vel: Vec,
    dragged_by: ?usize,

    pub fn init(pos: Vec, img_pos: Vec) Piece {
        return .{
            .pos = pos,
            .img_pos = img_pos,
            .vel = .fromScalar(0),
            .dragged_by = null,
        };
    }

    /// Move by velocity. Return true if position is changed.
    pub fn move(piece: *Piece, dt: f32) bool {
        const old_pos = piece.pos;
        piece.pos = piece.pos.addVec(piece.vel.mulScalar(dt * ctx.base_scalar))
            .clamp(.fromScalar(0), ctx.win_sz.subVec(ctx.piece_sz));
        return piece.pos.notEql(old_pos);
    }

    /// Drag piece with cursor (dc - delta cursor)
    pub fn drag(piece: *Piece, dt: f32, dc: Vec) void {
        piece.vel = dc.divScalar(dt * ctx.base_scalar);

    }

    /// Slower piece with time
    pub fn inertion(piece: *Piece, dt: f32) void {
        piece.vel = piece.vel.divScalar(@exp2(dt * 36));
    }

    /// Final bounce animation.
    pub fn bounce(piece: *Piece, dt: f32) void {
        const lower = Vec.fromScalar(0);
        const upper = ctx.win_sz.subVec(ctx.piece_sz);
        const future_pos = piece.pos.addVec(piece.vel);

        const bounce_x = future_pos.x() >= upper.x() or future_pos.x() <= lower.x();
        const bounce_y = future_pos.y() >= upper.y() or future_pos.y() <= lower.y();

        if (bounce_y) {
            var module = piece.vel.module();
            if (module > 0) {
                const cos_sin = piece.vel.divScalar(module);
                module -= @min(module, conf.bounce_slowing);
                piece.vel = cos_sin.mulScalar(module);
            }
        }
        piece.vel = piece.vel.mulVec(
            Vec.fromXY(@intFromBool(bounce_x), @intFromBool(bounce_y)).mulScalar(-2).addScalar(1)
        );
        piece.vel = piece.vel.addVec(.fromXY(0, conf.g * dt));
    }

    /// Tryes to snap piece to its destination place.
    /// Return true if snapped.
    pub fn trySnap(piece: *Piece) bool {
        if (piece.dragged_by != null) return false;

        const target = piece.img_pos.divScalar(ctx.img_scale);
        const radius = conf.snap_radius * ctx.frame_diagonal;

        if (vec.isPointInsideRectPoints(piece.pos,
                                        target.subScalar(radius),
                                        target.addScalar(radius))) {
            piece.pos = target;
            piece.vel = .fromScalar(0);
            piece.dragged_by = null;

            return true;
        }
        return false;
    }
};
