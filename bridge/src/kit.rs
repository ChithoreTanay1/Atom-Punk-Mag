//! `KitBuilder`: batches boxes, cylinders and ramps into one ArrayMesh with
//! one surface per material slot, plus one StaticBody3D of box colliders.
//! A whole building becomes ~5-10 draw calls instead of hundreds.
//! Vertex colours carry a cheap baked "ambient occlusion" gradient.

use godot::classes::mesh::{ArrayType, PrimitiveType};
use godot::classes::{
    ArrayMesh, BoxShape3D, CollisionShape3D, Material, MeshInstance3D, Node3D, StaticBody3D,
};
use godot::prelude::*;

#[derive(Default)]
struct Surface {
    verts: Vec<Vector3>,
    normals: Vec<Vector3>,
    colors: Vec<Color>,
    indices: Vec<i32>,
}

impl Surface {
    fn quad(&mut self, p: [Vector3; 4], n: Vector3, c: [f32; 4]) {
        let base = self.verts.len() as i32;
        for i in 0..4 {
            self.verts.push(p[i]);
            self.normals.push(n);
            self.colors.push(Color::from_rgb(c[i], c[i], c[i]));
        }
        // Godot treats clockwise triangles as front faces: with points listed
        // so that (p2-p0)x(p1-p0) is the outward normal, emit 0-1-2, 0-2-3.
        self.indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    fn tri(&mut self, p: [Vector3; 3], n: Vector3, c: [f32; 3]) {
        let base = self.verts.len() as i32;
        for i in 0..3 {
            self.verts.push(p[i]);
            self.normals.push(n);
            self.colors.push(Color::from_rgb(c[i], c[i], c[i]));
        }
        self.indices.extend_from_slice(&[base, base + 1, base + 2]);
    }
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct KitBuilder {
    surfaces: Vec<Surface>,
    colliders: Vec<(Transform3D, Vector3)>,
    /// Ambient-occlusion strength at the bottom of shapes (0 = none).
    #[var]
    ao: f32,
    base: Base<RefCounted>,
}

fn ao_shade(local_y_from_bottom: f32, h: f32, strength: f32) -> f32 {
    let t = (local_y_from_bottom / h.clamp(0.5, 3.0)).clamp(0.0, 1.0);
    1.0 - strength * (1.0 - t)
}

impl KitBuilder {
    fn surf(&mut self, slot: i64) -> &mut Surface {
        let slot = slot.max(0) as usize;
        if self.surfaces.len() <= slot {
            self.surfaces.resize_with(slot + 1, Surface::default);
        }
        &mut self.surfaces[slot]
    }

    fn strength(&self) -> f32 {
        if self.ao == 0.0 { 0.0 } else { self.ao }
    }
}

#[godot_api]
impl KitBuilder {
    #[func]
    fn set_ao_strength(&mut self, v: f32) {
        self.ao = v;
    }

    /// Axis-aligned (in `xf` space) box centred at the transform origin.
    #[func]
    fn add_box(&mut self, slot: i64, xf: Transform3D, size: Vector3) {
        let h = size / 2.0;
        let ao = self.strength();
        let b = xf.basis;
        let o = xf.origin;
        let p = |x: f32, y: f32, z: f32| o + b * Vector3::new(x, y, z);
        let n = |v: Vector3| (b * v).normalized();
        let bot = 1.0 - ao;
        let top = ao_shade(size.y, size.y, ao);
        let s = self.surf(slot);
        // +Y top
        s.quad([p(-h.x, h.y, -h.z), p(h.x, h.y, -h.z), p(h.x, h.y, h.z), p(-h.x, h.y, h.z)], n(Vector3::UP), [top; 4]);
        // -Y bottom
        s.quad([p(-h.x, -h.y, h.z), p(h.x, -h.y, h.z), p(h.x, -h.y, -h.z), p(-h.x, -h.y, -h.z)], n(Vector3::DOWN), [bot; 4]);
        // +Z
        s.quad([p(-h.x, -h.y, h.z), p(-h.x, h.y, h.z), p(h.x, h.y, h.z), p(h.x, -h.y, h.z)], n(Vector3::BACK), [bot, top, top, bot]);
        // -Z
        s.quad([p(h.x, -h.y, -h.z), p(h.x, h.y, -h.z), p(-h.x, h.y, -h.z), p(-h.x, -h.y, -h.z)], n(Vector3::FORWARD), [bot, top, top, bot]);
        // +X
        s.quad([p(h.x, -h.y, h.z), p(h.x, h.y, h.z), p(h.x, h.y, -h.z), p(h.x, -h.y, -h.z)], n(Vector3::RIGHT), [bot, top, top, bot]);
        // -X
        s.quad([p(-h.x, -h.y, -h.z), p(-h.x, h.y, -h.z), p(-h.x, h.y, h.z), p(-h.x, -h.y, h.z)], n(Vector3::LEFT), [bot, top, top, bot]);
    }

    /// Rough rock: a box of size `size` whose faces are displaced and whose
    /// corners are rounded off, flat-shaded. Displacement depends only on
    /// position, so neighbouring faces meet. No collider; add boxes separately.
    #[func]
    fn add_rock(&mut self, slot: i64, xf: Transform3D, size: Vector3, seed: i64, segments: i64, rough: f32) {
        let seg = segments.clamp(1, 24) as i32;
        let h = size / 2.0;
        let sd = seed as f32 * 0.137;
        let bump = |p: Vector3| -> f32 {
            let q = p * 0.31 + Vector3::splat(sd);
            let a = (q.x * 2.1 + q.y * 1.3).sin() * (q.z * 1.7 - q.y * 0.9).cos();
            let b = (q.x * 5.3 - q.z * 3.1 + 1.7).sin() * (q.y * 4.7 + q.x).cos() * 0.5;
            let c = (q.y * 11.0 + q.z * 9.0).sin() * (q.x * 13.0).cos() * 0.25;
            (a + b + c) * rough
        };
        let shape = |u: Vector3| -> Vector3 {
            // Pull a point of the unit cube toward a rounded box.
            let v = Vector3::new(u.x * h.x, u.y * h.y, u.z * h.z);
            let n = Vector3::new(u.x.powi(3) / h.x.max(1.0), u.y.powi(3) / h.y.max(1.0), u.z.powi(3) / h.z.max(1.0)).normalized_or_zero();
            let d = Vector3::new(u.x * h.x.min(6.0), u.y * h.y.min(6.0), u.z * h.z.min(6.0)).normalized_or_zero();
            let mut p = v - Vector3::new(u.x.powi(5) * 0.0, 0.0, 0.0);
            let corner = (u.x.abs() * u.y.abs()).max(u.y.abs() * u.z.abs()).max(u.x.abs() * u.z.abs()).powi(4);
            p -= n * corner * h.x.min(h.y).min(h.z) * 0.22;
            p + d * bump(p)
        };
        let faces: [(Vector3, Vector3, Vector3); 6] = [
            (Vector3::RIGHT, Vector3::BACK, Vector3::UP),
            (Vector3::LEFT, Vector3::FORWARD, Vector3::UP),
            (Vector3::UP, Vector3::RIGHT, Vector3::BACK),
            (Vector3::DOWN, Vector3::RIGHT, Vector3::FORWARD),
            (Vector3::BACK, Vector3::LEFT, Vector3::UP),
            (Vector3::FORWARD, Vector3::RIGHT, Vector3::UP),
        ];
        let ao = self.strength();
        let basis = xf.basis;
        let origin = xf.origin;
        let s = self.surf(slot);
        for (n, ua, va) in faces {
            for j in 0..seg {
                for i in 0..seg {
                    let corner = |a: i32, b: i32| {
                        let (x, y) = (a as f32 / seg as f32 * 2.0 - 1.0, b as f32 / seg as f32 * 2.0 - 1.0);
                        shape(n + ua * x + va * y)
                    };
                    let (a, b, c, d) = (corner(i, j), corner(i + 1, j), corner(i + 1, j + 1), corner(i, j + 1));
                    let tri_n = (c - a).cross(b - a).normalized_or_zero();
                    let tri_n = if tri_n.dot(n) < 0.0 { -tri_n } else { tri_n };
                    let shade = |p: Vector3| 1.0 - ao * (1.0 - ((p.y + h.y) / 3.0).clamp(0.0, 1.0));
                    let w = |p: Vector3| origin + basis * p;
                    let wn = (basis * tri_n).normalized_or_zero();
                    // Winding: pick the order whose geometric normal is outward.
                    let order = (d - a).cross(c - a).dot(n) > 0.0;
                    let q = if order { [a, b, c, d] } else { [a, d, c, b] };
                    s.quad([w(q[0]), w(q[1]), w(q[2]), w(q[3])], wn, [shade(q[0]), shade(q[1]), shade(q[2]), shade(q[3])]);
                }
            }
        }
    }

    /// Ramp: footprint `size.x` by `size.z`, rising from 0 at -Z to `size.y`
    /// at +Z. Origin at the centre of the footprint, on the ground.
    #[func]
    fn add_ramp(&mut self, slot: i64, xf: Transform3D, size: Vector3) {
        let (hx, hz, y) = (size.x / 2.0, size.z / 2.0, size.y);
        let b = xf.basis;
        let o = xf.origin;
        let p = |x: f32, yy: f32, z: f32| o + b * Vector3::new(x, yy, z);
        let n = |v: Vector3| (b * v).normalized();
        let ao = self.strength();
        let lo = 1.0 - ao;
        let s = self.surf(slot);
        let slope_n = Vector3::new(0.0, size.z, -size.y).normalized();
        s.quad([p(-hx, 0.0, -hz), p(hx, 0.0, -hz), p(hx, y, hz), p(-hx, y, hz)], n(slope_n), [lo, lo, 1.0, 1.0]);
        s.quad([p(-hx, 0.0, hz), p(-hx, y, hz), p(hx, y, hz), p(hx, 0.0, hz)], n(Vector3::BACK), [lo, 1.0, 1.0, lo]);
        s.tri([p(hx, 0.0, hz), p(hx, y, hz), p(hx, 0.0, -hz)], n(Vector3::RIGHT), [lo, 1.0, lo]);
        s.tri([p(-hx, 0.0, -hz), p(-hx, y, hz), p(-hx, 0.0, hz)], n(Vector3::LEFT), [lo, 1.0, lo]);
        s.quad([p(-hx, 0.0, hz), p(hx, 0.0, hz), p(hx, 0.0, -hz), p(-hx, 0.0, -hz)], n(Vector3::DOWN), [lo; 4]);
    }

    /// Cylinder / cone / disc along local Y, centred at the transform origin.
    #[func]
    fn add_cylinder(&mut self, slot: i64, xf: Transform3D, r_bottom: f32, r_top: f32, height: f32, segments: i64, caps: bool) {
        let seg = segments.clamp(3, 64) as usize;
        let hy = height / 2.0;
        let ao = self.strength();
        let lo = 1.0 - ao;
        let hi = ao_shade(height, height, ao);
        let b = xf.basis;
        let o = xf.origin;
        let p = |v: Vector3| o + b * v;
        let nn = |v: Vector3| (b * v).normalized();
        let slope = (r_bottom - r_top) / height.max(1e-4);
        let s = self.surf(slot);
        for i in 0..seg {
            let a0 = i as f32 / seg as f32 * std::f32::consts::TAU;
            let a1 = (i + 1) as f32 / seg as f32 * std::f32::consts::TAU;
            let (c0, s0, c1, s1) = (a0.cos(), a0.sin(), a1.cos(), a1.sin());
            let n0 = Vector3::new(c0, slope, s0).normalized();
            let n1 = Vector3::new(c1, slope, s1).normalized();
            let v = [
                p(Vector3::new(c0 * r_bottom, -hy, s0 * r_bottom)),
                p(Vector3::new(c0 * r_top, hy, s0 * r_top)),
                p(Vector3::new(c1 * r_top, hy, s1 * r_top)),
                p(Vector3::new(c1 * r_bottom, -hy, s1 * r_bottom)),
            ];
            let base = s.verts.len() as i32;
            let ns = [nn(n0), nn(n0), nn(n1), nn(n1)];
            let cs = [lo, hi, hi, lo];
            for k in 0..4 {
                s.verts.push(v[k]);
                s.normals.push(ns[k]);
                s.colors.push(Color::from_rgb(cs[k], cs[k], cs[k]));
            }
            s.indices.extend_from_slice(&[base, base + 2, base + 1, base, base + 3, base + 2]);
            if caps {
                if r_top > 0.0 {
                    s.tri([p(Vector3::new(0.0, hy, 0.0)), v[1], v[2]], nn(Vector3::UP), [hi; 3]);
                }
                if r_bottom > 0.0 {
                    s.tri([p(Vector3::new(0.0, -hy, 0.0)), v[3], v[0]], nn(Vector3::DOWN), [lo; 3]);
                }
            }
        }
    }

    /// Loft: a convex side profile in the Z/Y plane, extruded across X with a
    /// half-width per vertex (`profile[i] = (z, y, half_width)`), so a body can
    /// narrow toward the roof (tumblehome) or the nose. Flat-shaded; winding
    /// is chosen per triangle from the shape's centroid, so any vertex order
    /// works. Used for the wedge car body and its canopy. `open_edge` = i skips
    /// the band between vertex i and i+1 (-1 keeps the loft closed).
    #[func]
    fn add_loft(&mut self, slot: i64, xf: Transform3D, profile: PackedVector3Array, open_edge: i64) {
        self.add_loft_open(slot, xf, profile, PackedInt32Array::from(&[open_edge as i32][..]));
    }

    /// `add_loft` leaving several bands out.
    #[func]
    fn add_loft_open(&mut self, slot: i64, xf: Transform3D, profile: PackedVector3Array, open: PackedInt32Array) {
        let pts: Vec<Vector3> = profile.as_slice().to_vec();
        let n = pts.len();
        if n < 3 { return; }
        let ao = self.strength();
        let (mut ymin, mut ymax) = (f32::MAX, f32::MIN);
        let mut centre = Vector3::ZERO;
        for q in &pts {
            ymin = ymin.min(q.y);
            ymax = ymax.max(q.y);
            centre += Vector3::new(0.0, q.y, q.x);
        }
        centre /= n as f32;
        let b = xf.basis;
        let o = xf.origin;
        let shade = |y: f32| 1.0 - ao * (1.0 - ((y - ymin) / (ymax - ymin).clamp(0.5, 3.0)).clamp(0.0, 1.0));
        let s = self.surf(slot);
        let mut emit = |a: Vector3, bb: Vector3, c: Vector3| {
            let (mut p1, mut p2) = (bb, c);
            let mut nn = (p2 - a).cross(p1 - a);
            if nn.length_squared() < 1e-12 { return; }
            let out = (a + bb + c) / 3.0 - centre;
            if nn.dot(out) < 0.0 {
                std::mem::swap(&mut p1, &mut p2);
                nn = -nn;
            }
            let nw = (b * nn.normalized()).normalized();
            s.tri([o + b * a, o + b * p1, o + b * p2], nw, [shade(a.y), shade(p1.y), shade(p2.y)]);
        };
        let side = |i: usize, sx: f32| Vector3::new(sx * pts[i].z, pts[i].y, pts[i].x);
        for sx in [1.0f32, -1.0] {
            for i in 1..n - 1 {
                emit(side(0, sx), side(i, sx), side(i + 1, sx));
            }
        }
        for i in 0..n {
            // `open_edge` leaves one band out (e.g. the underside of a canopy).
            if open.as_slice().contains(&(i as i32)) { continue; }
            let j = (i + 1) % n;
            let (a, bb, c, d) = (side(i, 1.0), side(j, 1.0), side(j, -1.0), side(i, -1.0));
            emit(a, bb, c);
            emit(a, c, d);
        }
    }

    /// Register a box collider (same convention as `add_box`).
    #[func]
    fn add_collider(&mut self, xf: Transform3D, size: Vector3) {
        self.colliders.push((xf, size));
    }

    #[func]
    fn triangle_count(&self) -> i64 {
        self.surfaces.iter().map(|s| s.indices.len() / 3).sum::<usize>() as i64
    }

    /// Build the ArrayMesh. `materials[i]` is applied to slot i. Empty slots
    /// are skipped, so only used materials cost a draw call.
    #[func]
    fn build_mesh(&self, materials: Array<Gd<Material>>) -> Gd<ArrayMesh> {
        let mut mesh = ArrayMesh::new_gd();
        let mut surface_idx = 0;
        for (slot, s) in self.surfaces.iter().enumerate() {
            if s.indices.is_empty() { continue; }
            let mut arrays = VarArray::new();
            arrays.resize(ArrayType::MAX.ord() as usize, &Variant::nil());
            arrays.set(ArrayType::VERTEX.ord() as usize, &PackedVector3Array::from(s.verts.as_slice()).to_variant());
            arrays.set(ArrayType::NORMAL.ord() as usize, &PackedVector3Array::from(s.normals.as_slice()).to_variant());
            arrays.set(ArrayType::COLOR.ord() as usize, &PackedColorArray::from(s.colors.as_slice()).to_variant());
            arrays.set(ArrayType::INDEX.ord() as usize, &PackedInt32Array::from(s.indices.as_slice()).to_variant());
            mesh.add_surface_from_arrays(PrimitiveType::TRIANGLES, &arrays.upcast_any_array());
            if slot < materials.len() {
                if let Some(m) = materials.get(slot) {
                    mesh.surface_set_material(surface_idx, &m);
                }
            }
            surface_idx += 1;
        }
        mesh
    }

    /// Build mesh + colliders under `parent`. Returns the MeshInstance3D.
    #[func]
    fn commit(&mut self, mut parent: Gd<Node3D>, materials: Array<Gd<Material>>, name: GString, collision_layer: i64) -> Gd<MeshInstance3D> {
        let mesh = self.build_mesh(materials);
        let mut mi = MeshInstance3D::new_alloc();
        mi.set_mesh(&mesh);
        mi.set_name(&StringName::from(&name));
        parent.add_child(&mi);
        if !self.colliders.is_empty() {
            let mut body = StaticBody3D::new_alloc();
            body.set_name(&StringName::from(format!("{name}_col").as_str()));
            body.set_collision_layer(collision_layer as u32);
            body.set_collision_mask(0);
            for (xf, size) in self.colliders.drain(..) {
                let mut shape = BoxShape3D::new_gd();
                shape.set_size(size);
                let mut cs = CollisionShape3D::new_alloc();
                cs.set_shape(&shape);
                cs.set_transform(xf);
                body.add_child(&cs);
            }
            parent.add_child(&body);
        }
        self.surfaces.clear();
        mi
    }

    #[func]
    fn clear(&mut self) {
        self.surfaces.clear();
        self.colliders.clear();
    }
}
