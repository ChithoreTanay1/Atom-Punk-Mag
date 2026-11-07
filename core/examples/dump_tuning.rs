//! Writes the default tuning file: `cargo run -p core --example dump_tuning`.
fn main() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../data/tuning.ron");
    magadha_core::write_ron(&path, &magadha_core::tuning::Tuning::default()).unwrap();
    println!("wrote {}", path.display());
}
