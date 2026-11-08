//! Every tunable number for movement, driving and cameras. Loaded from
//! `data/tuning.ron`, edited live by the in-game tuning panel (F1), and saved
//! back to the same file. No magic numbers in the controllers.

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug)]
pub struct FieldInfo {
    pub name: &'static str,
    pub min: f32,
    pub max: f32,
    pub doc: &'static str,
}

macro_rules! tunable_struct {
    ($name:ident { $($field:ident : $def:expr, $min:expr, $max:expr, $doc:expr;)* }) => {
        #[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
        #[serde(default)]
        pub struct $name { $(pub $field: f32,)* }

        impl Default for $name {
            fn default() -> Self { Self { $($field: $def,)* } }
        }

        impl $name {
            pub const FIELDS: &'static [FieldInfo] = &[
                $(FieldInfo { name: stringify!($field), min: $min, max: $max, doc: $doc },)*
            ];
            pub fn get(&self, key: &str) -> Option<f32> {
                match key { $(stringify!($field) => Some(self.$field),)* _ => None }
            }
            pub fn set(&mut self, key: &str, v: f32) -> bool {
                match key { $(stringify!($field) => { self.$field = v; true })* _ => false }
            }
        }
    };
}

tunable_struct!(MovementTuning {
    walk_speed: 4.3, 1.0, 10.0, "Ground speed walking (m/s)";
    sprint_speed: 7.2, 2.0, 14.0, "Ground speed sprinting (m/s)";
    crouch_speed: 2.3, 0.5, 6.0, "Ground speed crouched (m/s)";
    ground_accel: 11.0, 1.0, 30.0, "Ground acceleration factor (Quake-style)";
    ground_friction: 8.0, 0.5, 20.0, "Ground friction factor";
    stop_speed: 2.0, 0.1, 6.0, "Below this speed friction acts as if at this speed";
    air_accel: 2.2, 0.0, 20.0, "Air acceleration factor";
    air_max_speed: 1.2, 0.2, 6.0, "Max wish speed added in air (limits air control)";
    gravity: 21.0, 5.0, 50.0, "Gravity (m/s^2)";
    fall_gravity_mult: 1.3, 1.0, 3.0, "Extra gravity when falling";
    jump_velocity: 6.6, 2.0, 12.0, "Upward velocity on jump";
    coyote_time: 0.12, 0.0, 0.4, "Seconds after leaving ground where jump still works";
    jump_buffer: 0.13, 0.0, 0.4, "Seconds a jump press is remembered before landing";
    step_height: 0.42, 0.0, 0.8, "Max ledge height stepped up automatically (m)";
    max_slope_deg: 47.0, 10.0, 70.0, "Steepest walkable slope (deg)";
    stand_height: 1.78, 1.2, 2.2, "Capsule height standing (m)";
    crouch_height: 1.05, 0.6, 1.6, "Capsule height crouched (m)";
    eye_below_top: 0.12, 0.0, 0.4, "Eye distance below capsule top (m)";
    crouch_rate: 11.0, 1.0, 30.0, "Crouch height transition rate";
    slide_min_speed: 5.6, 1.0, 12.0, "Speed needed to start a slide";
    slide_boost: 1.6, 0.0, 6.0, "Instant speed added at slide start";
    slide_friction: 1.6, 0.0, 10.0, "Friction during slide";
    slide_duration: 0.85, 0.1, 3.0, "Max slide time (s)";
    slide_cooldown: 0.45, 0.0, 3.0, "Time before another slide (s)";
    mantle_reach: 0.85, 0.3, 1.5, "How far ahead a ledge is detected (m)";
    mantle_height: 1.45, 0.5, 2.5, "Max ledge height above feet for mantle (m)";
    mantle_time: 0.3, 0.05, 1.0, "Mantle duration (s)";
});

tunable_struct!(CameraTuning {
    mouse_sensitivity: 0.0022, 0.0002, 0.01, "Radians per mouse pixel (never smoothed)";
    fov_base: 80.0, 55.0, 110.0, "On-foot base FOV (deg)";
    fov_speed_gain: 5.0, 0.0, 20.0, "Extra FOV at sprint speed (deg)";
    fov_rate: 6.0, 0.5, 20.0, "FOV change rate";
    bob_amount: 0.018, 0.0, 0.08, "Head-bob height (m)";
    bob_frequency: 0.55, 0.1, 2.0, "Head-bob cycles per metre";
    land_dip: 0.07, 0.0, 0.3, "Camera dip on hard landing (m)";
    land_recover: 9.0, 1.0, 30.0, "Land-dip spring stiffness";
    slide_roll_deg: 3.0, 0.0, 12.0, "Camera roll while sliding (deg)";
    step_smooth: 14.0, 2.0, 40.0, "Camera catch-up rate after a step-up";
    ads_fov: 52.0, 20.0, 80.0, "FOV while aiming down sights (deg)";
    car_fov_base: 72.0, 50.0, 100.0, "Chase cam base FOV (deg)";
    car_fov_gain: 16.0, 0.0, 40.0, "Chase cam extra FOV at top speed (deg)";
    car_distance: 5.6, 2.0, 12.0, "Chase cam distance (m)";
    car_height: 1.9, 0.5, 5.0, "Chase cam height (m)";
    car_stiffness: 9.0, 1.0, 30.0, "Chase cam follow stiffness";
    car_lookahead: 0.32, 0.0, 1.5, "Look-ahead into turns (rad per rad/s yaw)";
    car_shake: 0.035, 0.0, 0.2, "Shake amount on rough surfaces";
    car_recenter: 3.5, 0.2, 15.0, "Recenter rate after mouse look (1/s)";
});

tunable_struct!(VehicleTuning {
    mass: 1100.0, 400.0, 4000.0, "Body mass (kg)";
    com_height: -0.2, -1.0, 0.5, "Centre of mass offset (m, below origin is stable)";
    susp_rest: 0.52, 0.2, 1.2, "Suspension ray length at rest (m)";
    susp_spring: 32000.0, 5000.0, 90000.0, "Spring rate per wheel (N/m)";
    susp_damp: 3400.0, 200.0, 12000.0, "Damper per wheel (N per m/s)";
    wheel_radius: 0.36, 0.2, 0.7, "Wheel radius (m)";
    engine_force: 12500.0, 1000.0, 30000.0, "Peak drive force (N)";
    max_speed: 52.0, 10.0, 90.0, "Top speed (m/s)";
    reverse_force: 5200.0, 500.0, 15000.0, "Reverse drive force (N)";
    brake_force: 16000.0, 2000.0, 40000.0, "Brake force (N)";
    rear_drive_bias: 0.72, 0.0, 1.0, "Share of drive on rear axle";
    grip_front: 1.35, 0.3, 3.0, "Front tyre friction coefficient";
    grip_rear: 1.25, 0.3, 3.0, "Rear tyre friction coefficient";
    slip_peak_deg: 7.0, 1.0, 25.0, "Slip angle at peak grip (deg)";
    grip_falloff: 0.72, 0.2, 1.0, "Grip fraction left in a full slide";
    handbrake_grip: 0.42, 0.05, 1.0, "Rear grip multiplier on handbrake";
    drag: 0.42, 0.0, 3.0, "Air drag coefficient";
    rolling_resistance: 90.0, 0.0, 600.0, "Rolling resistance (N)";
    downforce: 2.6, 0.0, 15.0, "Downforce (N per (m/s)^2)";
    anti_roll: 9500.0, 0.0, 40000.0, "Anti-roll bar stiffness (N/m)";
    steer_max_deg: 33.0, 5.0, 50.0, "Max steering angle at low speed (deg)";
    steer_high_speed: 0.32, 0.05, 1.0, "Steering fraction at top speed";
    steer_rate: 5.5, 0.5, 20.0, "Steering response rate";
    steer_assist: 0.55, 0.0, 1.5, "Auto counter-steer in slides";
    yaw_damping: 0.35, 0.0, 3.0, "Extra yaw stability";
    air_righting: 7.0, 0.0, 30.0, "Self-righting torque in the air / when tilted";
    idle_rpm: 900.0, 400.0, 2000.0, "Idle RPM (audio)";
    max_rpm: 6800.0, 3000.0, 10000.0, "Redline RPM (audio)";
    gears: 5.0, 1.0, 8.0, "Gear count (audio only)";
});

tunable_struct!(BikeTuning {
    mass: 170.0, 80.0, 400.0, "Bike and rider mass (kg)";
    com_height: -0.25, -1.0, 0.5, "Centre of mass offset (m)";
    susp_rest: 0.34, 0.1, 0.8, "Suspension ray length at rest (m)";
    susp_spring: 12000.0, 2000.0, 40000.0, "Spring rate per wheel (N/m)";
    susp_damp: 1100.0, 100.0, 5000.0, "Damper per wheel (N per m/s)";
    wheel_radius: 0.31, 0.2, 0.5, "Wheel radius (m)";
    max_speed: 58.0, 15.0, 90.0, "Top speed (m/s)";
    drive_force: 2300.0, 300.0, 6000.0, "Peak drive force at the top of the powerband (N)";
    below_band: 0.3, 0.05, 1.0, "Share of drive below the powerband (a two-stroke bogs)";
    band_start: 0.62, 0.2, 0.95, "Rev fraction where the powerband starts";
    band_snap: 0.08, 0.01, 0.4, "Rev fractions it takes to come on the pipe (smaller is snappier)";
    gears: 6.0, 2.0, 7.0, "Gears (auto)";
    shift_cut: 0.09, 0.0, 0.4, "Drive cut on a gear change (s)";
    reverse_force: 320.0, 50.0, 1500.0, "Paddling backwards (N)";
    brake_force: 3200.0, 500.0, 8000.0, "Brake force (N)";
    grip: 1.25, 0.3, 3.0, "Sideways grip";
    slide_at: 0.85, 0.2, 2.0, "Sideways slip (m/s) above which the tyres let go";
    steer_low: 2.9, 0.5, 6.0, "Yaw rate at low speed (rad/s)";
    steer_high: 0.72, 0.1, 2.5, "Yaw rate at top speed (rad/s)";
    steer_rate: 7.5, 0.5, 25.0, "Steering response rate";
    yaw_gain: 9.0, 1.0, 30.0, "How hard the body follows the steering";
    upright_gain: 90.0, 5.0, 300.0, "Upright stabilizer stiffness";
    upright_damp: 14.0, 0.5, 60.0, "Upright stabilizer damping";
    lean_max_deg: 42.0, 0.0, 60.0, "Visual lean at full turn (deg)";
    lean_rate: 7.0, 0.5, 25.0, "Visual lean rate";
    wheelie_deg: 7.0, 0.0, 30.0, "Visual front-wheel lift on the pipe (deg)";
    drag: 0.1, 0.0, 1.0, "Air drag coefficient";
    idle_rpm: 1600.0, 500.0, 3000.0, "Idle RPM";
    max_rpm: 11500.0, 5000.0, 16000.0, "Redline RPM";
    eye_height: 1.46, 1.0, 2.0, "Rider's eye above the road (m)";
    eye_back: 0.1, -0.4, 0.6, "Rider's eye behind the bike's centre (m)";
    horizon_roll: 0.4, 0.0, 1.0, "How much of the lean tilts the view";
    fov: 76.0, 55.0, 100.0, "Riding FOV at rest (deg)";
    fov_gain: 14.0, 0.0, 30.0, "Extra FOV at top speed (deg)";
});

tunable_struct!(CrashTuning {
    min_impact: 4.5, 1.0, 15.0, "Speed change below which a hit is only a scrape (m/s)";
    injury_start: 8.0, 1.0, 30.0, "Speed change where it starts to hurt (m/s)";
    injury_per_ms: 3.2, 0.0, 15.0, "Damage to the person per m/s past that";
    bike_injury_mult: 1.4, 1.0, 4.0, "Injury multiplier with no car around you";
    bike_eject_at: 10.0, 3.0, 40.0, "Speed change that throws a rider off (m/s)";
    car_hull: 100.0, 10.0, 500.0, "Car structure";
    bike_hull: 70.0, 10.0, 300.0, "Bike structure";
    hull_per_ms: 3.0, 0.0, 20.0, "Hull lost per m/s of impact";
    limp_fraction: 0.35, 0.05, 0.9, "Below this hull fraction the engine limps";
    limp_power: 0.45, 0.05, 1.0, "Engine power while limping";
    crack_at: 9.0, 2.0, 40.0, "Speed change that cracks a windshield (m/s)";
    shatter_at: 19.0, 4.0, 60.0, "Speed change that takes one out at once (m/s)";
    thrown_seconds: 2.4, 0.5, 8.0, "Time on the ground after being thrown (s)";
    deflate_seconds: 1.5, 0.1, 10.0, "A shot tyre goes flat over this long (s)";
    flat_grip: 0.42, 0.05, 1.0, "Grip left on a flat";
    flat_radius: 0.62, 0.3, 1.0, "Rolling radius left on a flat (share of full)";
    flat_drag: 3200.0, 0.0, 8000.0, "Drag of one flat tyre at speed (N)";
    dent_depth: 0.6, 0.0, 1.0, "How far the worst crash bends a panel in (m)";
    dent_radius: 1.1, 0.2, 2.0, "How wide the worst dent reaches (m)";
    drone_hp: 150.0, 10.0, 1000.0, "Saucer drone structure (a bullet does 30)";
});

#[derive(Clone, Debug, Serialize, Deserialize, Default, PartialEq)]
#[serde(default)]
pub struct Tuning {
    pub movement: MovementTuning,
    pub camera: CameraTuning,
    pub vehicle: VehicleTuning,
    pub bike: BikeTuning,
    pub crash: CrashTuning,
}

impl Tuning {
    pub const SECTIONS: &'static [&'static str] = &["movement", "camera", "vehicle", "bike", "crash"];

    pub fn fields(section: &str) -> &'static [FieldInfo] {
        match section {
            "movement" => MovementTuning::FIELDS,
            "camera" => CameraTuning::FIELDS,
            "vehicle" => VehicleTuning::FIELDS,
            "bike" => BikeTuning::FIELDS,
            "crash" => CrashTuning::FIELDS,
            _ => &[],
        }
    }

    pub fn get(&self, section: &str, key: &str) -> Option<f32> {
        match section {
            "movement" => self.movement.get(key),
            "camera" => self.camera.get(key),
            "vehicle" => self.vehicle.get(key),
            "bike" => self.bike.get(key),
            "crash" => self.crash.get(key),
            _ => None,
        }
    }

    pub fn set(&mut self, section: &str, key: &str, v: f32) -> bool {
        match section {
            "movement" => self.movement.set(key, v),
            "camera" => self.camera.set(key, v),
            "vehicle" => self.vehicle.set(key, v),
            "bike" => self.bike.set(key, v),
            "crash" => self.crash.set(key, v),
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_inside_ranges() {
        let t = Tuning::default();
        for s in Tuning::SECTIONS {
            for f in Tuning::fields(s) {
                let v = t.get(s, f.name).unwrap();
                assert!(v >= f.min && v <= f.max, "{s}.{} = {v} outside [{}, {}]", f.name, f.min, f.max);
            }
        }
    }

    #[test]
    fn ron_roundtrip_and_partial_files() {
        let mut t = Tuning::default();
        assert!(t.set("vehicle", "mass", 999.0));
        let s = ron::to_string(&t).unwrap();
        let back: Tuning = ron::from_str(&s).unwrap();
        assert_eq!(back, t);
        // A file missing fields falls back to defaults.
        let partial: Tuning = ron::from_str("(movement: (walk_speed: 3.0))").unwrap();
        assert_eq!(partial.movement.walk_speed, 3.0);
        assert_eq!(partial.vehicle.mass, VehicleTuning::default().mass);
    }
}
