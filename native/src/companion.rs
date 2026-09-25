//! Private Unix socket transport. The public JSON and ordinary FFI ABI stay unchanged.
use crate::{Command, Events, Host, boundary, datasets::Initial, protocol::Event, trace::Trace};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{
    io::{self, Read, Write},
    net::Shutdown,
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::{net::UnixStream, process::CommandExt},
    },
    process::{Command as ProcessCommand, Stdio},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

// Serialization can add default window fields and the internal command envelope.
const MAX_FRAME: usize = crate::protocol::MAX_MESSAGE_BYTES + 4096;

#[derive(Deserialize)]
struct Launch {
    launcher: String,
    library: String,
}

#[derive(Serialize, Deserialize)]
struct Start {
    version: u32,
    initial: Initial,
    trace_limit: usize,
}

#[derive(Serialize, Deserialize)]
enum Reply {
    Event(Event),
    Finished { trace: Vec<u8> },
}

fn write_frame(writer: &mut impl Write, value: &impl Serialize) -> Result<(), String> {
    let bytes = serde_json::to_vec(value).map_err(|e| e.to_string())?;
    if bytes.len() > MAX_FRAME {
        return Err("Companion frame exceeds limit".into());
    }
    writer
        .write_all(&(bytes.len() as u32).to_le_bytes())
        .and_then(|_| writer.write_all(&bytes))
        .and_then(|_| writer.flush())
        .map_err(|e| e.to_string())
}

fn read_frame<T: DeserializeOwned>(reader: &mut impl Read) -> Result<T, String> {
    let mut length = [0; 4];
    reader
        .read_exact(&mut length)
        .map_err(|e| format!("Companion header: {e}"))?;
    let length = u32::from_le_bytes(length) as usize;
    if length == 0 || length > MAX_FRAME {
        return Err("Invalid companion frame length".into());
    }
    let mut bytes = vec![0; length];
    reader
        .read_exact(&mut bytes)
        .map_err(|e| format!("Companion body: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| format!("Companion JSON: {e}"))
}

#[unsafe(no_mangle)]
pub extern "C" fn gd_companion_version() -> u32 {
    1
}

/// Blocking companion runner. Paths are UTF-8 JSON, copied before launching.
/// Keep host and its event callback alive until this function returns.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_run_companion(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || {
        if bytes.is_null() || len > 16 * 1024 {
            return -1;
        }
        let Ok(launch) =
            serde_json::from_slice::<Launch>(unsafe { std::slice::from_raw_parts(bytes, len) })
        else {
            return -2;
        };
        unsafe { crate::run_with(host, |host, initial| run(host, initial, launch)) }
    })
}

fn run(host: &Host, initial: Initial, launch: Launch) -> Result<(), String> {
    let (mut socket, child_socket) = UnixStream::pair().map_err(|e| e.to_string())?;
    let fd = child_socket.as_raw_fd();
    let mut command = ProcessCommand::new(&launch.launcher);
    command
        .args(["--ui-host", &launch.library, &fd.to_string()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit());
    unsafe {
        command.pre_exec(move || {
            // Only async-signal-safe libc calls are allowed before exec.
            if libc::fcntl(fd, libc::F_SETFD, 0) == -1 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let mut child = command
        .spawn()
        .map_err(|e| format!("Start native companion: {e}"))?;
    drop(child_socket);
    let trace_limit = host.trace.begin_remote();
    let abort = AtomicBool::new(false);
    // Clones are created before worker startup; all paths below reap the child.
    let writer_socket = socket.try_clone();
    let watch_socket = socket.try_clone();
    let (Ok(mut writer_socket), Ok(watch_socket)) = (writer_socket, watch_socket) else {
        let _ = child.kill();
        let _ = child.wait();
        return Err("Clone companion socket".into());
    };
    std::thread::scope(|scope| {
        let watch = scope.spawn(|| {
            let mut closing = None;
            loop {
                match child.try_wait() {
                    Ok(Some(status)) => return Ok(status),
                    Err(error) => {
                        let _ = child.kill();
                        let _ = child.wait();
                        let _ = watch_socket.shutdown(Shutdown::Both);
                        return Err(error.to_string());
                    }
                    _ => {}
                }
                if host.sender.is_closed() { closing.get_or_insert_with(Instant::now); }
                if abort.load(Ordering::Acquire) || closing.is_some_and(|t: Instant| t.elapsed() >= Duration::from_secs(4)) {
                    let _ = child.kill();
                    let _ = child.wait();
                    let _ = watch_socket.shutdown(Shutdown::Both);
                    return Err("Native companion was terminated after transport failure or shutdown deadline".into());
                }
                std::thread::sleep(Duration::from_millis(10));
            }
        });
        let writer = scope.spawn(|| {
            let result = (|| {
                write_frame(
                    &mut writer_socket,
                    &Start {
                        version: 1,
                        initial,
                        trace_limit,
                    },
                )?;
                let mut sent_close = false;
                while let Ok(command) = host.receiver.recv_blocking() {
                    let close = matches!(command, Command::Close);
                    write_frame(&mut writer_socket, &command)?;
                    if close {
                        sent_close = true;
                        break;
                    }
                }
                if !sent_close {
                    write_frame(&mut writer_socket, &Command::Close)?;
                }
                Ok::<_, String>(())
            })();
            let _ = writer_socket.shutdown(Shutdown::Write);
            if result.is_err() {
                host.sender.close();
            }
            result
        });
        let mut remote_error = None;
        let result = loop {
            match read_frame::<Reply>(&mut socket) {
                Ok(Reply::Event(Event::Error { message })) => {
                    remote_error.get_or_insert(message);
                }
                Ok(Reply::Event(Event::Closed)) => {
                    break Err("Unexpected companion closed event".into());
                }
                Ok(Reply::Event(event)) => host.events.emit(event),
                Ok(Reply::Finished { trace }) => break host.trace.import_remote(&trace),
                Err(error) => break Err(error),
            }
        };
        host.sender.close();
        if result.is_err() {
            abort.store(true, Ordering::Release);
        }
        let status = watch.join().map_err(|_| "Companion monitor panicked")?;
        let _written = writer.join().map_err(|_| "Companion writer panicked")?;
        result?;
        let status = status?;
        if !status.success() {
            return Err(format!("Native companion exited with {status}"));
        }
        remote_error.map_or(Ok(()), Err)
    })
}

/// Consumes an inherited, connected socket. Called once by the native launcher
/// on its process main thread; macOS AppKit can terminate this process on quit.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_ui_process_main(fd: i32) -> i32 {
    boundary::call(-4, || {
        if fd < 3 {
            return -1;
        }
        let socket = unsafe { UnixStream::from_raw_fd(fd) };
        if unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) } == -1 {
            return -1;
        }
        match child_main(socket) {
            Ok(()) => 0,
            Err(error) => {
                eprintln!("GPUI companion: {error}");
                -3
            }
        }
    })
}

fn child_main(mut socket: UnixStream) -> Result<(), String> {
    let Start {
        version,
        initial,
        trace_limit,
    } = read_frame(&mut socket)?;
    if version != 1 {
        return Err("Incompatible companion transport".into());
    }
    let trace = Arc::new(Trace::default());
    if trace_limit != 0 {
        trace
            .enable(trace_limit)
            .map_err(|_| "Invalid trace capacity")?;
    }
    let output = Arc::new(Mutex::new(socket.try_clone().map_err(|e| e.to_string())?));
    let event_trace = trace.clone();
    let event_output = output.clone();
    let events = Events(Arc::new(move |event| {
        if trace_limit != 0
            && let Some(key) = event.trace_key()
        {
            event_trace.point(
                "native.emit",
                key,
                serde_json::to_vec(&event).ok().map(|v| v.len()),
                None,
            );
        }
        if write_frame(
            &mut *event_output.lock().unwrap_or_else(|e| e.into_inner()),
            &Reply::Event(event),
        )
        .is_err()
        {
            // Parent death closes the socket. The reader also closes the UI queue.
            let _ = event_output
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .shutdown(Shutdown::Both);
        }
    }));
    let finished = AtomicBool::new(false);
    let run_trace = trace.clone();
    let before_quit: Arc<dyn Fn() + Send + Sync> = Arc::new(move || {
        if !finished.swap(true, Ordering::AcqRel) {
            trace.point(
                "native.emit",
                crate::trace::Key {
                    operation: "close",
                    request: 0,
                },
                None,
                None,
            );
            if let Ok(trace) = trace.snapshot() {
                let _ = write_frame(
                    &mut *output.lock().unwrap_or_else(|e| e.into_inner()),
                    &Reply::Finished { trace },
                );
            }
        }
    });
    let (sender, receiver) = async_channel::bounded(64);
    let reader_events = events.clone();
    std::thread::spawn(move || {
        loop {
            let command = match read_frame::<Command>(&mut socket) {
                Ok(command) => command,
                Err(message) => {
                    reader_events.emit(Event::Error { message });
                    break;
                }
            };
            let close = matches!(command, Command::Close);
            if sender.send_blocking(command).is_err() {
                break;
            }
            if close {
                break;
            }
        }
        sender.close();
    });
    let result = boundary::catch(|| {
        crate::ui::run(
            initial,
            receiver,
            events.clone(),
            run_trace,
            Some(before_quit.clone()),
        )
    });
    let result = result.unwrap_or_else(|error| Err(format!("Native UI panic: {error}")));
    if let Err(message) = &result {
        events.emit(Event::Error {
            message: message.clone(),
        });
    }
    before_quit();
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn initial() -> Initial {
        Initial::parse(br#"{"snapshot":{"revision":1,"root":{"kind":"text","id":"a","text":"a"}},"datasets":[]}"#).unwrap()
    }

    fn host() -> Host {
        let (sender, receiver) = async_channel::bounded(64);
        Host {
            initial: Mutex::new(None),
            sender,
            receiver,
            events: Events(Arc::new(|_| {})),
            running: AtomicBool::new(false),
            trace: Arc::new(Trace::default()),
            panic_on_run: AtomicBool::new(false),
        }
    }

    #[test]
    fn frames_preserve_commands_and_reject_oversize_truncation_and_bad_json() {
        let mut bytes = Vec::new();
        write_frame(&mut bytes, &Command::Publish(initial().snapshot)).unwrap();
        let Command::Publish(snapshot) = read_frame(&mut bytes.as_slice()).unwrap() else {
            panic!("wrong command")
        };
        assert_eq!(snapshot.revision, 1);
        for bytes in [
            vec![0, 0, 0, 0],
            ((MAX_FRAME + 1) as u32).to_le_bytes().to_vec(),
            vec![1, 0, 0, 0],
            vec![1, 0, 0, 0, b'{'],
        ] {
            assert!(read_frame::<Command>(&mut bytes.as_slice()).is_err());
        }
    }

    #[test]
    fn companion_start_failure_early_exit_and_hung_close_are_bounded_and_reaped() {
        assert!(
            run(
                &host(),
                initial(),
                Launch {
                    launcher: "/gpuidart-missing-launcher".into(),
                    library: "unused".into()
                }
            )
            .unwrap_err()
            .contains("Start native companion")
        );
        let directory =
            std::env::temp_dir().join(format!("gpuidart-companion-test-{}", std::process::id()));
        std::fs::create_dir(&directory).unwrap();
        let script = directory.join("launcher");
        let pid_path = directory.join("pid");
        let launch = || Launch {
            launcher: script.to_string_lossy().into(),
            library: pid_path.to_string_lossy().into(),
        };
        std::fs::write(&script, "#!/bin/sh\nexit 7\n").unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o700)).unwrap();
        let start = Instant::now();
        assert!(run(&host(), initial(), launch()).is_err());
        assert!(start.elapsed() < Duration::from_secs(2));
        std::fs::write(&script, "#!/bin/sh\necho $$ > \"$2\"\nexec /bin/sleep 60\n").unwrap();
        let host = host();
        host.sender.close();
        let start = Instant::now();
        assert!(run(&host, initial(), launch()).is_err());
        assert!(start.elapsed() < Duration::from_secs(6));
        let pid = std::fs::read_to_string(&pid_path)
            .unwrap()
            .trim()
            .parse::<i32>()
            .unwrap();
        assert_eq!(
            unsafe { libc::kill(pid, 0) },
            -1,
            "companion must be reaped before returning"
        );
        std::fs::remove_dir_all(directory).unwrap();
    }
}
