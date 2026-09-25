use std::{ffi::OsString, process::ExitCode};

fn main() -> ExitCode {
    match run(std::env::args_os().skip(1).collect()) {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("gpuidart-launcher: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run(args: Vec<OsString>) -> Result<u8, String> {
    match args.first().and_then(|arg| arg.to_str()) {
        Some("--session") if args.len() >= 2 => session(&args[1..]),
        Some("--ui-host") if args.len() == 3 => unsafe {
            // The SDK loads its own sibling library. Keep it loaded until the UI exits.
            let library = libloading::Library::new(&args[1]).map_err(|e| e.to_string())?;
            let version: libloading::Symbol<unsafe extern "C" fn() -> u32> = library
                .get(b"gd_companion_version")
                .map_err(|e| e.to_string())?;
            if version() != 2 {
                return Err("incompatible companion extension; rebuild the package".into());
            }
            let path = args[2].to_str().ok_or("invalid companion socket path")?;
            let main: libloading::Symbol<unsafe extern "C" fn(*const u8, usize) -> i32> = library
                .get(b"gd_ui_process_main")
                .map_err(|e| e.to_string())?;
            Ok(if main(path.as_ptr(), path.len()) == 0 {
                0
            } else {
                1
            })
        },
        _ => Err("expected --session PROGRAM [ARGS...] or --ui-host LIBRARY SOCKET".into()),
    }
}

#[cfg(unix)]
fn session(args: &[OsString]) -> Result<u8, String> {
    use std::os::unix::process::CommandExt;
    // Process.start creates a child that is not a process-group leader.
    // This new session owns the full Dart/native descendant group.
    if unsafe { libc::setsid() } == -1 {
        return Err(format!("setsid: {}", std::io::Error::last_os_error()));
    }
    Err(std::process::Command::new(&args[0])
        .args(&args[1..])
        .exec()
        .to_string())
}

#[cfg(not(unix))]
fn session(_: &[OsString]) -> Result<u8, String> {
    Err("session launch is Unix-only; Windows uses taskkill /T".into())
}
