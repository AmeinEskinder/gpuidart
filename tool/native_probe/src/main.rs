use serde_json::Value;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(windows)]
mod windows;

#[cfg(target_os = "linux")]
use linux as platform;
#[cfg(target_os = "macos")]
use macos as platform;
#[cfg(windows)]
use windows as platform;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

struct Request {
    process: i32,
    operation: String,
    name: String,
    value: String,
    id: String,
}

fn run(args: &[String]) -> Result<Option<Value>> {
    match args.first().map(String::as_str) {
        Some("accessibility") if args.len() == 6 => {
            let request = Request {
                process: args[1].parse()?,
                operation: args[2].clone(),
                name: args[3].clone(),
                value: args[4].clone(),
                id: args[5].clone(),
            };
            if request.process <= 0 {
                return Err("PID must be positive".into());
            }
            if !["query", "invoke", "toggle", "set-value", "set-range", "focus", "select", "hover", "invoke-menu"].contains(&request.operation.as_str()) {
                return Err(format!("Unknown accessibility operation {}", request.operation).into());
            }
            platform::accessibility(&request).map(Some)
        }
        #[cfg(target_os = "linux")]
        Some("cache-events") if args.len() == 3 => linux::cache_events(args[1].parse()?, &args[2]).map(|()| None),
        #[cfg(target_os = "macos")]
        Some("metal") if args.len() == 1 => macos::metal().map(Some),
        #[cfg(windows)]
        Some("environment") if args.len() == 1 => windows::environment().map(Some),
        _ => Err("Usage: gpuidart-native-probe accessibility PID OP NAME VALUE ID | cache-events PID OUTPUT (Linux) | metal (macOS) | environment (Windows)".into()),
    }
}

fn main() {
    match run(&std::env::args().skip(1).collect::<Vec<_>>()) {
        Ok(Some(report)) => println!("{report}"),
        Ok(None) => (),
        Err(error) => {
            eprintln!("{error}");
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            if error.downcast_ref::<platform::StaleTree>().is_some() {
                std::process::exit(75);
            }
            std::process::exit(1);
        }
    }
}
