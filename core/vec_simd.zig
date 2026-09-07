const std = @import("std");

pub const Vec = struct {
    const VecType = @Vector(2, f32);
    const x_i = 0;
    const y_i = 1;

    dm: VecType,


    pub inline fn x(v: Vec) f32 {
        return v.dm[x_i];
    }
    pub inline fn y(v: Vec) f32 {
        return v.dm[y_i];
    }

    pub fn fromXY(xx: f32, yy: f32) Vec {
        return .{.dm = [2]f32{xx, yy}};
    }
    pub fn fromScalar(scalar: f32) Vec {
        return .{.dm = @splat(scalar)};
    }

    pub fn addVec(v1: Vec, v2: Vec) Vec {
        return .{.dm = v1.dm + v2.dm};
    }
    pub fn subVec(v1: Vec, v2: Vec) Vec {
        return .{.dm = v1.dm - v2.dm};
    }
    pub fn mulVec(v1: Vec, v2: Vec) Vec {
        return .{.dm = v1.dm * v2.dm};
    }
    pub fn divVec(v1: Vec, v2: Vec) Vec {
        return .{.dm = v1.dm / v2.dm};
    }

    pub fn addScalar(v: Vec, scalar: f32) Vec {
        return .{.dm = v.dm + @as(VecType, @splat(scalar))};
    }
    pub fn subScalar(v: Vec, scalar: f32) Vec {
        return .{.dm = v.dm - @as(VecType, @splat(scalar))};
    }
    pub fn mulScalar(v: Vec, scalar: f32) Vec {
        return .{.dm = v.dm * @as(VecType, @splat(scalar))};
    }
    pub fn divScalar(v: Vec, scalar: f32) Vec {
        return .{.dm = v.dm / @as(VecType, @splat(scalar))};
    }


    pub fn dot(v1: Vec, v2: Vec) f32 {
        return @reduce(.Add, v1.dm * v2.dm);
    }
    pub fn module(v: Vec) f32 {
        return @sqrt(Vec.dot(v, v));
    }

    pub fn eql(v1: Vec, v2: Vec) bool {
        return @reduce(.And, v1.dm == v2.dm);
    }
    pub fn notEql(v1: Vec, v2: Vec) bool {
        return @reduce(.Or, v1.dm != v2.dm);
    }


    pub fn clamp(v: Vec, lo: Vec, hi: Vec) Vec {
        return .{.dm = std.math.clamp(v.dm, lo.dm, hi.dm)};
    }
};

pub fn isPointInsideRect(pt: Vec, rect_pos: Vec, rect_sz: Vec) bool {
    return isPointInsideRectPoints(pt, rect_pos, rect_pos.addVec(rect_sz));
}

pub fn isPointInsideRectPoints(pt: Vec, rect_start: Vec, rect_end: Vec) bool {
    return @reduce(.And, pt.dm >= rect_start.dm) and
           @reduce(.And, pt.dm <= rect_end.dm);
}
