use gpuidart_platform_probe::{gdp_run, report, run_companion};

fn main() {
    report("executable_main", serde_json::Value::Null);
    let worker = std::env::args().any(|arg| arg == "--worker");
    let companion = std::env::args().any(|arg| arg == "--stdio");
    let status = if companion {
        run_companion()
    } else if worker {
        std::thread::spawn(|| gdp_run(None)).join().unwrap_or(-21)
    } else {
        gdp_run(None)
    };
    report(
        "exit",
        serde_json::json!({"status": status, "worker": worker}),
    );
    if status != 0 {
        std::process::exit(1);
    }
}
