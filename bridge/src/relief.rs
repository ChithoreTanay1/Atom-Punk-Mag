//! `ReliefBank`: bakes the temple's carved wall at load time, with no texture
//! files. A height field is painted from rounded shapes, then turned into a
//! normal map and an albedo with cavity shading.
//!
//! The wall follows refs/kcarving: a frieze of figures and elephants with
//! machinery cut in among them (telex keys, tape reels, cassettes, dials,
//! switches, vents, and a curved conduit running through it all). The figures
//! are generic court attendants and guardians. Per LORE rule 3 no deity is
//! depicted and nothing sacred is drawn holding the machinery: tech sits in
//! its own panels beside the figures.

use godot::classes::image::Format;
use godot::classes::{Image, ImageTexture};
use godot::prelude::*;

const SIZE: usize = 1024;

/// Height (0..1) plus what emits there.
struct Field {
    h: Vec<f32>,
    /// 0 none, 1 amber, 2 green.
    glow: Vec<u8>,
}

impl Field {
    fn new() -> Self {
        Self { h: vec![0.42; SIZE * SIZE], glow: vec![0; SIZE * SIZE] }
    }

    fn at(&self, x: i32, y: i32) -> f32 {
        self.h[y.rem_euclid(SIZE as i32) as usize * SIZE + x.rem_euclid(SIZE as i32) as usize]
    }

    fn put(&mut self, x: i32, y: i32, v: f32) {
        let i = y.rem_euclid(SIZE as i32) as usize * SIZE + x.rem_euclid(SIZE as i32) as usize;
        self.h[i] = v;
    }

    /// Domed ellipse: rises by `height` above the existing surface.
    fn dome(&mut self, cx: f32, cy: f32, rx: f32, ry: f32, height: f32) {
        for y in (cy - ry) as i32..=(cy + ry) as i32 {
            for x in (cx - rx) as i32..=(cx + rx) as i32 {
                let (dx, dy) = ((x as f32 - cx) / rx, (y as f32 - cy) / ry);
                let d = dx * dx + dy * dy;
                if d < 1.0 {
                    let v = 0.42 + height * (1.0 - d).sqrt();
                    if v > self.at(x, y) { self.put(x, y, v); }
                }
            }
        }
    }

    /// Bevelled slab. `height` < 0 cuts into the wall.
    fn slab(&mut self, x0: f32, y0: f32, x1: f32, y1: f32, height: f32, bevel: f32) {
        for y in y0 as i32..=y1 as i32 {
            for x in x0 as i32..=x1 as i32 {
                let e = (x as f32 - x0).min(x1 - x as f32).min(y as f32 - y0).min(y1 - y as f32);
                let k = (e / bevel.max(0.5)).clamp(0.0, 1.0);
                let v = 0.42 + height * k;
                let cur = self.at(x, y);
                if height >= 0.0 { if v > cur { self.put(x, y, v); } } else if v < cur { self.put(x, y, v); }
            }
        }
    }

    /// Rounded limb from a to b, tapering from ra to rb.
    fn limb(&mut self, a: (f32, f32), b: (f32, f32), ra: f32, rb: f32, height: f32) {
        let n = (((b.0 - a.0).abs() + (b.1 - a.1).abs()) / (ra.min(rb) * 0.5).max(1.0)).ceil() as i32 + 1;
        for i in 0..=n {
            let t = i as f32 / n as f32;
            let r = ra + (rb - ra) * t;
            self.dome(a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, r, r, height);
        }
    }

    fn ring(&mut self, cx: f32, cy: f32, r0: f32, r1: f32, height: f32) {
        for y in (cy - r1) as i32..=(cy + r1) as i32 {
            for x in (cx - r1) as i32..=(cx + r1) as i32 {
                let d = ((x as f32 - cx).powi(2) + (y as f32 - cy).powi(2)).sqrt();
                if d >= r0 && d <= r1 {
                    let v = 0.42 + height;
                    self.put(x, y, v);
                }
            }
        }
    }

    fn light(&mut self, x0: f32, y0: f32, x1: f32, y1: f32, kind: u8) {
        for y in y0 as i32..=y1 as i32 {
            for x in x0 as i32..=x1 as i32 {
                let i = y.rem_euclid(SIZE as i32) as usize * SIZE + x.rem_euclid(SIZE as i32) as usize;
                self.glow[i] = kind;
            }
        }
    }
}

// ---- Figures -------------------------------------------------------------

/// A standing attendant in a long robe with a tiered headdress. `s` is the
/// total height in pixels; `offer` raises one arm to carry a tray.
fn attendant(f: &mut Field, x: f32, foot: f32, s: f32, offer: bool) {
    let h = 0.12;
    let top = foot - s;
    // Robe, narrow at the waist, flaring to the hem.
    f.limb((x, top + s * 0.28), (x, top + s * 0.55), s * 0.085, s * 0.07, h);
    f.limb((x, top + s * 0.55), (x, foot - s * 0.04), s * 0.075, s * 0.14, h * 0.95);
    // Drapery folds cut down the skirt.
    for k in [-1.0f32, 0.0, 1.0] {
        f.slab(x + k * s * 0.05 - 1.0, top + s * 0.6, x + k * s * 0.05 + 1.0, foot - s * 0.08, 0.05, 1.0);
    }
    f.slab(x - s * 0.1, top + s * 0.52, x + s * 0.1, top + s * 0.55, 0.15, 2.0); // girdle
    // Shoulders, arms.
    f.dome(x, top + s * 0.25, s * 0.13, s * 0.05, h);
    f.limb((x - s * 0.12, top + s * 0.26), (x - s * 0.15, top + s * 0.5), s * 0.03, s * 0.024, h);
    if offer {
        f.limb((x + s * 0.12, top + s * 0.26), (x + s * 0.2, top + s * 0.34), s * 0.03, s * 0.024, h);
        f.limb((x + s * 0.2, top + s * 0.34), (x + s * 0.2, top + s * 0.2), s * 0.024, s * 0.02, h);
        f.slab(x + s * 0.12, top + s * 0.16, x + s * 0.28, top + s * 0.19, 0.14, 2.0);
    } else {
        f.limb((x + s * 0.12, top + s * 0.26), (x + s * 0.15, top + s * 0.5), s * 0.03, s * 0.024, h);
    }
    // Head, ears, necklace, stepped headdress.
    f.dome(x, top + s * 0.14, s * 0.058, s * 0.07, h + 0.03);
    f.ring(x, top + s * 0.24, s * 0.05, s * 0.065, 0.13);
    for (k, w) in [(0.0f32, 0.07f32), (1.0, 0.055), (2.0, 0.038)] {
        let y = top + s * (0.075 - k * 0.028);
        f.slab(x - s * w, y - s * 0.024, x + s * w, y, 0.16, 1.5);
    }
}

/// A large guardian, frontal, hands resting on a staff. Deliberately a court
/// figure: armoured and plain, with no attributes of any god.
fn guardian(f: &mut Field, x: f32, foot: f32, s: f32) {
    let h = 0.18;
    let top = foot - s;
    f.limb((x - s * 0.07, top + s * 0.55), (x - s * 0.09, foot), s * 0.06, s * 0.06, h);
    f.limb((x + s * 0.07, top + s * 0.55), (x + s * 0.09, foot), s * 0.06, s * 0.06, h);
    f.dome(x, top + s * 0.4, s * 0.16, s * 0.2, h);
    f.dome(x, top + s * 0.25, s * 0.2, s * 0.06, h);
    // Lamellar rows on the chest.
    let mut y = top + s * 0.28;
    while y < top + s * 0.54 {
        let mut px = x - s * 0.12;
        while px < x + s * 0.12 {
            f.dome(px, y, s * 0.012, s * 0.008, h + 0.06);
            px += s * 0.03;
        }
        y += s * 0.022;
    }
    f.slab(x - s * 0.15, top + s * 0.54, x + s * 0.15, top + s * 0.58, h + 0.06, 2.0);
    f.limb((x - s * 0.19, top + s * 0.27), (x - s * 0.2, top + s * 0.48), s * 0.045, s * 0.035, h);
    f.limb((x + s * 0.19, top + s * 0.27), (x + s * 0.2, top + s * 0.48), s * 0.045, s * 0.035, h);
    f.limb((x - s * 0.2, top + s * 0.48), (x, top + s * 0.5), s * 0.035, s * 0.03, h + 0.02);
    f.limb((x + s * 0.2, top + s * 0.48), (x, top + s * 0.5), s * 0.035, s * 0.03, h + 0.02);
    // Staff, grounded between the feet.
    f.slab(x - s * 0.012, top + s * 0.16, x + s * 0.012, foot, h + 0.1, 1.5);
    f.dome(x, top + s * 0.15, s * 0.028, s * 0.028, h + 0.1);
    // Head and a plain crested helmet.
    f.dome(x, top + s * 0.14, s * 0.07, s * 0.085, h + 0.04);
    f.slab(x - s * 0.085, top + s * 0.08, x + s * 0.085, top + s * 0.105, h + 0.08, 2.0);
    f.limb((x, top + s * 0.09), (x, top + s * 0.01), s * 0.03, s * 0.015, h + 0.06);
}

/// A caparisoned elephant in profile; `dir` is +1 facing right, -1 left.
fn elephant(f: &mut Field, x: f32, foot: f32, s: f32, dir: f32) {
    let h = 0.2;
    let body_y = foot - s * 0.6;
    // Body, rump, head.
    f.dome(x - dir * s * 0.1, body_y, s * 0.4, s * 0.32, h);
    f.dome(x + dir * s * 0.32, body_y - s * 0.12, s * 0.2, s * 0.22, h + 0.02);
    // Legs.
    for lx in [-0.34f32, -0.14, 0.1, 0.28] {
        f.limb((x + dir * s * lx, body_y + s * 0.15), (x + dir * s * lx, foot), s * 0.08, s * 0.085, h - 0.01);
        f.slab(x + dir * s * lx - s * 0.09, foot - s * 0.03, x + dir * s * lx + s * 0.09, foot, h + 0.03, 1.5);
    }
    // Trunk, curling down and in.
    let mut p = (x + dir * s * 0.46, body_y - s * 0.08);
    for (dx, dy, r) in [(0.1, 0.16, 0.06), (0.03, 0.18, 0.05), (-0.02, 0.14, 0.04), (-0.08, 0.08, 0.03)] {
        let q = (p.0 + dir * s * dx, p.1 + s * dy);
        f.limb(p, q, s * r, s * (r - 0.008), h + 0.04);
        p = q;
    }
    // Ear, eye, tusk.
    f.dome(x + dir * s * 0.2, body_y - s * 0.13, s * 0.11, s * 0.15, h + 0.07);
    f.dome(x + dir * s * 0.42, body_y - s * 0.17, s * 0.012, s * 0.012, h + 0.1);
    f.limb((x + dir * s * 0.42, body_y + s * 0.02), (x + dir * s * 0.56, body_y + s * 0.09), s * 0.018, s * 0.008, h + 0.1);
    // Caparison: an embroidered cloth, with a tasselled hem.
    let (cx0, cx1) = if dir > 0.0 { (x - s * 0.36, x + s * 0.1) } else { (x - s * 0.1, x + s * 0.36) };
    f.slab(cx0, body_y - s * 0.3, cx1, body_y + s * 0.12, h + 0.05, 2.0);
    f.slab(cx0 + s * 0.03, body_y - s * 0.27, cx1 - s * 0.03, body_y + s * 0.09, h + 0.09, 1.5);
    let mut px = cx0 + s * 0.05;
    while px < cx1 - s * 0.03 {
        f.dome(px, body_y - s * 0.09, s * 0.018, s * 0.018, h + 0.12);
        f.limb((px, body_y + s * 0.12), (px, body_y + s * 0.17), s * 0.007, s * 0.004, h + 0.05);
        px += s * 0.075;
    }
}

// ---- Machinery -----------------------------------------------------------

fn telex(f: &mut Field, x0: f32, y0: f32, w: f32, h: f32) {
    f.slab(x0, y0, x0 + w, y0 + h, -0.22, 3.0);
    // Paper window, lit amber.
    f.slab(x0 + w * 0.1, y0 + h * 0.08, x0 + w * 0.9, y0 + h * 0.3, 0.02, 1.0);
    // Lines of type, not a solid slab of light.
    for l in 0..4 {
        let ly = y0 + h * (0.11 + l as f32 * 0.045);
        f.light(x0 + w * 0.13, ly, x0 + w * (0.87 - (l % 3) as f32 * 0.14), ly + h * 0.018, 1);
    }
    let (rows, cols) = (4, 10);
    for r in 0..rows {
        for c in 0..cols {
            let kx = x0 + w * 0.08 + (c as f32 + r as f32 * 0.25) * w * 0.082;
            let ky = y0 + h * 0.4 + r as f32 * h * 0.135;
            f.slab(kx, ky, kx + w * 0.058, ky + h * 0.09, -0.06, 1.0);
            f.dome(kx + w * 0.029, ky + h * 0.045, w * 0.022, h * 0.04, 0.03);
        }
    }
}

fn reel(f: &mut Field, cx: f32, cy: f32, r: f32) {
    f.dome(cx, cy, r, r, 0.06);
    f.ring(cx, cy, r * 0.9, r, 0.12);
    f.ring(cx, cy, r * 0.2, r * 0.3, 0.14);
    for k in 0..3 {
        let a = k as f32 * std::f32::consts::TAU / 3.0 + 0.5;
        let (dx, dy) = (a.cos(), a.sin());
        f.dome(cx + dx * r * 0.58, cy + dy * r * 0.58, r * 0.2, r * 0.2, -0.2);
    }
}

fn cassette(f: &mut Field, x0: f32, y0: f32, w: f32) {
    let h = w * 0.62;
    f.slab(x0, y0, x0 + w, y0 + h, 0.1, 2.0);
    f.slab(x0 + w * 0.08, y0 + h * 0.1, x0 + w * 0.92, y0 + h * 0.3, 0.14, 1.0);
    f.slab(x0 + w * 0.16, y0 + h * 0.36, x0 + w * 0.84, y0 + h * 0.72, 0.02, 1.0);
    f.ring(x0 + w * 0.32, y0 + h * 0.54, w * 0.05, w * 0.09, 0.14);
    f.ring(x0 + w * 0.68, y0 + h * 0.54, w * 0.05, w * 0.09, 0.14);
}

fn dial(f: &mut Field, cx: f32, cy: f32, r: f32) {
    f.ring(cx, cy, r * 0.85, r, 0.14);
    f.dome(cx, cy, r * 0.85, r * 0.85, -0.14);
    for k in 0..9 {
        let a = 2.4 + k as f32 * 0.57;
        f.limb((cx + a.cos() * r * 0.62, cy + a.sin() * r * 0.62), (cx + a.cos() * r * 0.75, cy + a.sin() * r * 0.75), 1.0, 1.0, 0.08);
    }
    f.limb((cx, cy), (cx + r * 0.5, cy - r * 0.42), 2.0, 1.0, 0.12);
    f.dome(cx, cy, r * 0.12, r * 0.12, 0.14);
}

fn switches(f: &mut Field, x0: f32, y0: f32, n: i32, step: f32) {
    f.slab(x0 - 8.0, y0 - 16.0, x0 + n as f32 * step, y0 + 24.0, -0.1, 2.0);
    for i in 0..n {
        let x = x0 + i as f32 * step + step * 0.3;
        f.dome(x, y0 + 4.0, 7.0, 7.0, 0.06);
        let up = i % 3 != 1;
        f.limb((x, y0 + 4.0), (x, y0 + if up { -9.0 } else { 17.0 }), 3.0, 2.2, 0.14);
    }
    f.light(x0 + step * 0.1, y0 - 13.0, x0 + step * 0.42, y0 - 9.0, 2);
    f.light(x0 + step * 2.1, y0 - 13.0, x0 + step * 2.42, y0 - 9.0, 1);
}

fn vents(f: &mut Field, x0: f32, y0: f32, w: f32, rows: i32) {
    for r in 0..rows {
        let y = y0 + r as f32 * 13.0;
        f.slab(x0, y, x0 + w, y + 7.0, -0.2, 1.5);
    }
}

/// The conduit that runs through the whole wall, wrapping seamlessly in x.
fn conduit(f: &mut Field, y: f32, amp: f32, r: f32) {
    let steps = 400;
    for i in 0..steps {
        let t = i as f32 / steps as f32;
        let px = t * SIZE as f32;
        let py = y + (t * std::f32::consts::TAU).sin() * amp;
        f.dome(px, py, r, r, 0.17);
    }
    // Collars.
    for k in 0..9 {
        let t = k as f32 / 9.0;
        let px = t * SIZE as f32;
        let py = y + (t * std::f32::consts::TAU).sin() * amp;
        f.slab(px - 5.0, py - r * 1.3, px + 5.0, py + r * 1.3, 0.23, 1.5);
    }
}

fn paint() -> Field {
    let mut f = Field::new();
    let s = SIZE as f32;

    // Coarse tool marks over the whole wall.
    let mut r = magadha_core::rng::Rng::new(4133);
    for _ in 0..5000 {
        let (x, y) = (r.range(0.0, s), r.range(0.0, s));
        let (rx, ry) = (r.range(2.0, 9.0), r.range(1.0, 3.0));
        f.dome(x, y, rx, ry, r.range(-0.02, 0.02));
    }

    // ---- Upper register: procession of attendants, a border above and below.
    f.slab(0.0, 8.0, s, 26.0, 0.14, 3.0);
    f.slab(0.0, 256.0, s, 276.0, 0.14, 3.0);
    let mut x = 40.0;
    let mut i = 0;
    while x < s - 20.0 {
        attendant(&mut f, x, 252.0, 210.0, i % 3 == 1);
        x += 76.0;
        i += 1;
    }

    conduit(&mut f, 300.0, 18.0, 13.0);

    // ---- Main register: elephants flanking a guardian, machinery between.
    f.slab(0.0, 730.0, s, 750.0, 0.15, 3.0);
    guardian(&mut f, s * 0.5, 728.0, 400.0);
    elephant(&mut f, s * 0.2, 728.0, 290.0, 1.0);
    elephant(&mut f, s * 0.8, 728.0, 290.0, -1.0);
    reel(&mut f, s * 0.385, 400.0, 46.0);
    reel(&mut f, s * 0.615, 400.0, 46.0);
    dial(&mut f, 60.0, 400.0, 34.0);
    dial(&mut f, s - 60.0, 400.0, 34.0);
    cassette(&mut f, 150.0, 350.0, 110.0);
    cassette(&mut f, s - 260.0, 350.0, 110.0);
    switches(&mut f, 40.0, 500.0, 5, 24.0);
    switches(&mut f, s - 170.0, 500.0, 5, 24.0);

    // ---- Lower register: the working panel, cut deep.
    f.slab(0.0, 1000.0, s, 1016.0, 0.14, 3.0);
    telex(&mut f, 26.0, 770.0, 280.0, 200.0);
    telex(&mut f, s - 306.0, 770.0, 280.0, 200.0);
    f.slab(s * 0.5 - 170.0, 770.0, s * 0.5 + 170.0, 980.0, -0.2, 3.0);
    reel(&mut f, s * 0.5 - 90.0, 850.0, 58.0);
    reel(&mut f, s * 0.5 + 90.0, 850.0, 58.0);
    vents(&mut f, s * 0.5 - 150.0, 925.0, 300.0, 4);
    f.light(s * 0.5 - 8.0, 800.0, s * 0.5 + 8.0, 816.0, 2);
    f.light(s * 0.5 - 8.0, 830.0, s * 0.5 + 8.0, 846.0, 1);
    f
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct ReliefBank {
    base: Base<RefCounted>,
}

#[godot_api]
impl ReliefBank {
    /// Returns { "albedo": ImageTexture (rgb cavity shade, a glow),
    /// "normal": ImageTexture (rg tangent-space slope) }.
    #[func]
    fn bake(&self) -> VarDictionary {
        let f = paint();
        let n = SIZE * SIZE;
        let mut alb = vec![0u8; n * 4];
        let mut nrm = vec![0u8; n * 4];
        for y in 0..SIZE as i32 {
            for x in 0..SIZE as i32 {
                let i = (y as usize * SIZE + x as usize) * 4;
                let h = f.at(x, y);
                let (dx, dy) = (f.at(x + 1, y) - f.at(x - 1, y), f.at(x, y - 1) - f.at(x, y + 1));
                nrm[i] = ((dx * 5.0).clamp(-1.0, 1.0) * 127.0 + 128.0) as u8;
                nrm[i + 1] = ((dy * 5.0).clamp(-1.0, 1.0) * 127.0 + 128.0) as u8;
                nrm[i + 2] = 255;
                nrm[i + 3] = 255;
                // Cavity: darker in the recesses and just under raised edges.
                let around = (f.at(x - 4, y) + f.at(x + 4, y) + f.at(x, y - 4) + f.at(x, y + 4)) * 0.25;
                let cavity = ((h - around) * 2.6 + 0.5 + (h - 0.42) * 1.1).clamp(0.08, 1.0);
                let v = (cavity * 255.0) as u8;
                let g = f.glow[y as usize * SIZE + x as usize];
                match g {
                    1 => { alb[i] = 235; alb[i + 1] = 118; alb[i + 2] = 26; alb[i + 3] = 255; }
                    2 => { alb[i] = 70; alb[i + 1] = 220; alb[i + 2] = 120; alb[i + 3] = 255; }
                    _ => { alb[i] = v; alb[i + 1] = v; alb[i + 2] = v; alb[i + 3] = 0; }
                }
            }
        }
        let make = |bytes: &[u8]| {
            let mut img = Image::create_from_data(SIZE as i32, SIZE as i32, false, Format::RGBA8, &PackedByteArray::from(bytes)).expect("relief image");
            img.generate_mipmaps();
            ImageTexture::create_from_image(&img).expect("relief texture")
        };
        vdict! { "albedo" => &make(&alb), "normal" => &make(&nrm) }
    }
}
