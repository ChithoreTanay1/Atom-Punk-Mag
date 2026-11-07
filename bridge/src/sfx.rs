//! `SfxBank`: synthesises every short sound effect at load time. No sample
//! files, no licenses to track (own work). 22.05 kHz mono 16-bit.

use godot::classes::audio_stream_wav::{Format, LoopMode};
use godot::classes::AudioStreamWav;
use godot::prelude::*;

use magadha_core::rng::Rng;

pub const RATE: f32 = 22050.0;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct SfxBank {
    base: Base<RefCounted>,
}

struct Lp(f32);
impl Lp {
    fn run(&mut self, x: f32, a: f32) -> f32 {
        self.0 += (x - self.0) * a;
        self.0
    }
}

fn render(secs: f32, mut f: impl FnMut(f32, &mut Rng) -> f32, seed: u64) -> Vec<f32> {
    let n = (secs * RATE) as usize;
    let mut rng = Rng::new(seed);
    (0..n).map(|i| f(i as f32 / RATE, &mut rng)).collect()
}

fn noise(r: &mut Rng) -> f32 {
    r.next_f32() * 2.0 - 1.0
}

fn tau() -> f32 {
    std::f32::consts::TAU
}

fn synth(name: &str) -> (Vec<f32>, bool) {
    let mut lp = Lp(0.0);
    let mut lp2 = Lp(0.0);
    match name {
        // Carbine report: sharp crack + low body thump + tail.
        "shot" => (render(0.55, |t, r| {
            let crack = noise(r) * (-t * 60.0).exp();
            let body = (tau() * 95.0 * t).sin() * (-t * 14.0).exp() * 0.9;
            let tail = lp.run(noise(r), 0.08) * (-t * 6.0).exp() * 1.6;
            (crack * 0.9 + body + tail).clamp(-1.0, 1.0)
        }, 1), false),
        // Distant guard rifle: duller.
        "shot_far" => (render(0.6, |t, r| {
            let x = lp.run(noise(r), 0.12) * (-t * 9.0).exp() * 2.2;
            let b = (tau() * 70.0 * t).sin() * (-t * 10.0).exp() * 0.5;
            (x + b).clamp(-1.0, 1.0) * 0.8
        }, 2), false),
        "dry" => (render(0.06, |t, r| noise(r) * (-t * 120.0).exp() * 0.5, 3), false),
        "reload" => (render(0.9, |t, r| {
            let c1 = if t < 0.05 { noise(r) * (-t * 90.0).exp() } else { 0.0 };
            let t2 = t - 0.55;
            let c2 = if t2 > 0.0 { noise(r) * (-t2 * 70.0).exp() + (tau() * 1800.0 * t2).sin() * (-t2 * 50.0).exp() * 0.3 } else { 0.0 };
            (c1 + c2) * 0.6
        }, 4), false),
        "step" => (render(0.09, |t, r| lp.run(noise(r), 0.25) * (-t * 45.0).exp() * 0.9, 5), false),
        "land" => (render(0.18, |t, r| {
            lp.run(noise(r), 0.15) * (-t * 22.0).exp() * 1.4 + (tau() * 60.0 * t).sin() * (-t * 25.0).exp() * 0.5
        }, 6), false),
        "hit" => (render(0.12, |t, r| (noise(r) * 0.6 + (tau() * 220.0 * t).sin() * 0.4) * (-t * 35.0).exp(), 7), false),
        "flesh" => (render(0.15, |t, r| lp.run(noise(r), 0.2) * (-t * 30.0).exp() * 1.3, 8), false),
        "thud" => (render(0.4, |t, r| {
            (tau() * 55.0 * t).sin() * (-t * 9.0).exp() + lp.run(noise(r), 0.1) * (-t * 14.0).exp()
        }, 9), false),
        // Static lure: crackling AM hiss with a buried tone. Loops.
        "static" => (render(1.0, |t, r| {
            let crackle = if r.chance(0.004) { noise(r) * 3.0 } else { 0.0 };
            let hiss = (noise(r) - lp.run(noise(r), 0.3)) * 0.45;
            let tone = (tau() * 440.0 * t).sin() * 0.12 * (0.5 + 0.5 * (tau() * 3.0 * t).sin());
            (hiss + crackle + tone).clamp(-1.0, 1.0)
        }, 10), true),
        // Tape motor: soft whir with flutter.
        "tape" => (render(0.7, |t, r| {
            let w = (tau() * (120.0 + 6.0 * (tau() * 7.0 * t).sin()) * t).sin() * 0.3;
            let n = lp.run(noise(r), 0.05) * 0.5;
            (w + n) * (1.0 - (-t * 30.0).exp()) * (-((t - 0.6).max(0.0)) * 30.0).exp()
        }, 11), false),
        // Telex: rapid hammer clicks.
        "telex" => (render(1.6, |t, r| {
            let ph = (t * 14.0).fract();
            noise(r) * (-ph * 90.0).exp() * 0.7 + (tau() * 50.0 * t).sin() * 0.05
        }, 12), false),
        // Two-tone siren, loops.
        "alarm" => (render(1.2, |t, _| {
            let f = if t < 0.6 { 620.0 } else { 470.0 };
            let x = (tau() * f * t).sin();
            (x * 1.8).clamp(-1.0, 1.0) * 0.35
        }, 13), true),
        "beep" => (render(0.09, |t, _| (tau() * 1320.0 * t).sin() * 0.35 * (1.0 - (-t * 200.0).exp()) * (-t * 18.0).exp(), 14), false),
        "beep_low" => (render(0.14, |t, _| (tau() * 660.0 * t).sin() * 0.35 * (-t * 14.0).exp(), 15), false),
        "pour" => (render(1.2, |t, r| {
            let x = noise(r) - lp.run(noise(r), 0.6);
            lp2.run(x, 0.5) * 0.35 * (1.0 - (-t * 8.0).exp()) * (-(t - 1.0).max(0.0) * 10.0).exp()
        }, 16), false),
        "throw" => (render(0.25, |t, r| lp.run(noise(r), 0.3) * (t * 12.0).sin().abs() * (-t * 10.0).exp() * 0.6, 17), false),
        "door" => (render(0.5, |t, r| lp.run(noise(r), 0.04) * (-t * 6.0).exp() * 1.6, 18), false),
        // Ambient: distant city hum + wind, loops.
        "ambience" => (render(4.0, |t, r| {
            let wind = lp.run(noise(r), 0.01) * 2.4;
            let hum = (tau() * 55.0 * t).sin() * 0.05 + (tau() * 110.0 * t).sin() * 0.02;
            (wind * (0.7 + 0.3 * (tau() * 0.25 * t).sin()) + hum) * 0.5
        }, 19), true),
        _ => (vec![0.0; 10], false),
    }
}

fn to_wav(samples: &[f32], looped: bool) -> Gd<AudioStreamWav> {
    let mut bytes = Vec::with_capacity(samples.len() * 2);
    // Short fade at both ends of one-shots avoids clicks.
    let n = samples.len();
    for (i, s) in samples.iter().enumerate() {
        let edge = if looped { 1.0 } else { ((i.min(n - 1 - i)) as f32 / 32.0).min(1.0) };
        let v = (s * edge * 32767.0).clamp(-32768.0, 32767.0) as i16;
        bytes.extend_from_slice(&v.to_le_bytes());
    }
    let mut w = AudioStreamWav::new_gd();
    w.set_format(Format::FORMAT_16_BITS);
    w.set_mix_rate(RATE as i32);
    w.set_stereo(false);
    w.set_data(&PackedByteArray::from(bytes.as_slice()));
    if looped {
        w.set_loop_mode(LoopMode::FORWARD);
        w.set_loop_end(n as i32);
    }
    w
}

#[godot_api]
impl SfxBank {
    #[func]
    fn make(&self, name: GString) -> Gd<AudioStreamWav> {
        let (s, looped) = synth(&name.to_string());
        to_wav(&s, looped)
    }

    #[func]
    fn names(&self) -> PackedStringArray {
        [
            "shot", "shot_far", "dry", "reload", "step", "land", "hit", "flesh", "thud", "static", "tape",
            "telex", "alarm", "beep", "beep_low", "pour", "throw", "door", "ambience",
        ]
        .iter()
        .map(|x| GString::from(*x))
        .collect()
    }
}
