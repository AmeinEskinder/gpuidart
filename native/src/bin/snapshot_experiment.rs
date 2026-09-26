fn main() {
    if let Err(error) = gpuidart::run_snapshot_experiment() {
        eprintln!("Snapshot experiment: {error}");
        std::process::exit(1);
    }
}
