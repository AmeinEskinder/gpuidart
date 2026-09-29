use anyhow::{bail, Result};

mod schedule;
#[cfg(windows)]
mod windows;

fn main() {
    if let Err(error) = run() {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args == ["--self-test"] {
        schedule::self_test();
        #[cfg(windows)]
        windows::self_test()?;
        println!("Driver self-test passed; no windows activated or input injected.");
        return Ok(());
    }
    #[cfg(windows)]
    {
        if args.len() == 3 && args[0] == "--extract-crt" {
            return windows::extract_crt(&args[1], &args[2]);
        }
        if args.len() == 2 && args[0] == "--config" {
            return windows::run(&args[1]);
        }
    }
    bail!("Usage: gpuidart-benchmark-driver --config CONFIG.json | --self-test. Window measurements require Windows.")
}
