#[cfg(windows)]
mod platform;

fn main() {
    #[cfg(windows)]
    if let Err(error) = platform::run(std::env::args().skip(1).collect()) {
        eprintln!("{error}");
        std::process::exit(1);
    }
    #[cfg(not(windows))]
    {
        eprintln!("gpuidart-windows-tool requires Windows");
        std::process::exit(1);
    }
}
