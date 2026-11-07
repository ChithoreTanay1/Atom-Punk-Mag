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

fn shot() -> Vec<f32> {
    let n = (1.6 * RATE) as usize;
    let mut r = Rng::new(1);
    let mut dry = vec![0.0f32; n];
    let mut lp = Lp(0.0);
    let mut lp_tail = Lp(0.0);
    let mut phase = 0.0f32;
    for (i, d) in dry.iter_mut().enumerate() {
        let t = i as f32 / RATE;
        let crack = noise(&mut r) * (-t * 90.0).exp() * 1.4;
        // Thump: 160 Hz falling to 45 Hz.
        let f = 45.0 + 115.0 * (-t * 30.0).exp();
        phase += tau() * f / RATE;
        let thump = phase.sin() * (-t * 11.0).exp() * 1.3;
        let body = lp.run(noise(&mut r), 0.25) * (-t * 22.0).exp() * 1.6;
        let t2 = t - 0.045;
        let clack = if t2 > 0.0 { (noise(&mut r) * 0.6 + (tau() * 2400.0 * t2).sin() * 0.4) * (-t2 * 110.0).exp() * 0.35 } else { 0.0 };
        let tail = lp_tail.run(noise(&mut r), 0.04) * (-t * 2.6).exp() * 2.2;
        *d = crack + thump + body + clack + tail;
    }
    // Slap-back echoes off building faces: delayed, darker, quieter.
    let mut out = dry.clone();
    for (delay, gain, a) in [(0.11f32, 0.32f32, 0.18f32), (0.23, 0.2, 0.1), (0.41, 0.1, 0.06)] {
        let k = (delay * RATE) as usize;
        let mut f = Lp(0.0);
        for i in k..n {
            out[i] += f.run(dry[i - k], a) * gain * 2.0;
        }
    }
    let peak = out.iter().fold(0.0f32, |m, x| m.max(x.abs())).max(1e-6);
    // Soft clip for density, then normalise.
    out.iter().map(|x| ((x / peak) * 1.6).tanh() * 0.98).collect()
}

fn synth(name: &str) -> (Vec<f32>, bool) {
    let mut lp = Lp(0.0);
    let mut lp2 = Lp(0.0);
    match name {
        // Carbine report, layered: supersonic crack, chest thump (pitch-dropping
        // sine), mechanical action clack, then two street slap-back echoes and a
        // long low rumble tail. Normalised hard so it is the loudest thing.
        "shot" => (shot(), false),
        // Spent brass hitting stone: a few bright inharmonic pings.
        "shell" => (render(0.35, |t, r| {
            let ping = |f: f32, d: f32| (tau() * f * t).sin() * (-t * d).exp();
            let bounce = |t0: f32| if t > t0 { (tau() * 5200.0 * (t - t0)).sin() * (-(t - t0) * 60.0).exp() * 0.5 } else { 0.0 };
            (ping(3900.0, 28.0) * 0.5 + ping(6100.0, 40.0) * 0.3 + ping(8300.0, 55.0) * 0.2 + bounce(0.11) + bounce(0.19) * 0.6
                + noise(r) * (-t * 200.0).exp() * 0.3) * 0.55
        }, 30), false),
        // Hit confirmation tick (UI, dry and short).
        "hitmark" => (render(0.07, |t, _| ((tau() * 2600.0 * t).sin() * 0.6 + (tau() * 5200.0 * t).sin() * 0.25) * (-t * 70.0).exp(), 31), false),
        // Near-miss: supersonic snap plus a short air tear.
        "whiz" => (render(0.22, |t, r| {
            let snap = noise(r) * (-t * 160.0).exp() * 0.9;
            let tear = (noise(r) - lp.run(noise(r), 0.35)) * (t * 30.0).min(1.0) * (-t * 18.0).exp() * 0.8;
            snap + tear
        }, 32), false),
        // Dull impact into earth / wood / plaster with grit.
        "impact" => (render(0.18, |t, r| {
            lp.run(noise(r), 0.35) * (-t * 40.0).exp() * 1.2 + (tau() * 140.0 * t).sin() * (-t * 30.0).exp() * 0.4
                + if r.chance(0.02) { noise(r) * (-t * 10.0).exp() } else { 0.0 }
        }, 33), false),
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
        // Rain on stone and roofs: band-passed hiss plus scattered drop ticks. Loops.
        "rain" => (render(3.0, |t, r| {
            let hiss = noise(r) - lp.run(noise(r), 0.35);
            let body = lp2.run(hiss, 0.45) * 0.5;
            let drop = if r.chance(0.0035) { noise(r) * 1.4 } else { 0.0 };
            let swell = 0.85 + 0.15 * (tau() * 0.33 * t).sin();
            (body * swell + drop * 0.5) * 0.8
        }, 34), true),
        // Snow: soft gusting wind, no drops. Loops.
        "wind" => (render(4.0, |t, r| {
            let w = lp.run(noise(r), 0.012) * 3.0;
            let gust = 0.6 + 0.4 * (tau() * 0.25 * t).sin() * (tau() * 0.5 * t + 1.0).sin();
            let whistle = (tau() * 420.0 * t + (tau() * 0.5 * t).sin() * 3.0).sin() * 0.02 * gust;
            (w * gust + whistle) * 0.7
        }, 35), true),
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
            "shot", "shell", "hitmark", "whiz", "impact", "shot_far", "dry", "reload", "step", "land", "hit", "flesh", "thud", "static", "tape",
            "telex", "alarm", "beep", "beep_low", "pour", "throw", "door", "ambience", "rain", "wind",
        ]
        .iter()
        .map(|x| GString::from(*x))
        .collect()
    }
}
