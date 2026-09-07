pub extern "env" fn jsDrawRect(x: f32, y: f32, w: f32, h: f32, clr: u32) void;
pub extern "env" fn jsDrawImgPart(x: f32, y: f32, sx: f32, sy: f32, sw: f32, sh: f32, scale: f32) void;

const std = @import("std");
const globals = @import("globals.zig");
const ctx = &globals.ctx;
const conf = &globals.conf;
const Vec = @import("vec_simd.zig").Vec;

pub fn redrawFrame(pieces: []const globals.Piece) void {
    drawRect(Vec.fromScalar(0), ctx.win_sz, conf.bg_color);

    // Frame
    const frame_width = conf.frame_width * ctx.base_scalar;
    drawRect(Vec.fromScalar(0), ctx.frame_sz, conf.frame_color);
    drawRect(Vec.fromScalar(frame_width),
             ctx.frame_sz.subScalar(frame_width*2),
             @bitCast(conf.bg_color));

    for (0..pieces.len) |i_front| {
        const i = pieces.len - i_front - 1;
        const piece = pieces[i];
        const offset: f32 = if (piece.dragged_by == null) 0 else
            ctx.base_scalar * conf.dragging_offset;

        // Border
        if (i < ctx.misplaced_pieces) {
            const bwidth = conf.border_width * ctx.base_scalar;
            const bpos = piece.pos.subScalar(offset + bwidth);
            const bsz = ctx.piece_sz.addScalar(bwidth * 2);
            drawRect(bpos, bsz, conf.shadow_color);

            // Shadow
            if (piece.dragged_by != null) {
                drawRect(piece.pos, ctx.piece_sz, conf.shadow_color);
            }
        }

        // Image part
        drawImgPart(piece.pos.subScalar(offset), piece.img_pos,
                    ctx.piece_sz, ctx.img_scale);
    }
}

fn drawRect(pos: Vec, size: Vec, color: globals.Color) void {
    return jsDrawRect(pos.x(), pos.y(), size.x(), size.y(), @bitCast(color));
}
fn drawImgPart(pos: Vec, src_pos: Vec, size: Vec, scale: f32) void {
    return jsDrawImgPart(pos.x(), pos.y(), src_pos.x(), src_pos.y(), size.x(), size.y(), scale);
}
