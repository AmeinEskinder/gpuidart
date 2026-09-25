//! Private Unix socket transport. Dart owns child creation, exit status and reaping.
use crate::{Command, Events, Host, boundary, datasets::Initial, protocol::Event, trace::Trace};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{
    io::{self, Read, Write},
    net::Shutdown,
    os::unix::net::{UnixListener, UnixStream},
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

const MAX_FRAME: usize = crate::protocol::MAX_MESSAGE_BYTES + 4096;

pub(crate) struct Endpoint {
    directory: PathBuf,
    listener: UnixListener,
}
impl Endpoint {
    fn new() -> Result<Self, String> {
        let mut template = b"/tmp/gpuidart-XXXXXX\0".to_vec();
        let path = unsafe { libc::mkdtemp(template.as_mut_ptr().cast()) };
        if path.is_null() {
            return Err(io::Error::last_os_error().to_string());
        }
        let directory = PathBuf::from(
            unsafe { std::ffi::CStr::from_ptr(path) }
                .to_string_lossy()
                .into_owned(),
        );
        let listener = match UnixListener::bind(directory.join("ui.sock")) {
            Ok(listener) => listener,
            Err(error) => {
                let _ = std::fs::remove_dir(&directory);
                return Err(error.to_string());
            }
        };
        let endpoint = Self {
            directory,
            listener,
        };
        endpoint
            .listener
            .set_nonblocking(true)
            .map_err(|e| e.to_string())?;
        Ok(endpoint)
    }
    fn path(&self) -> PathBuf {
        self.directory.join("ui.sock")
    }
}
impl Drop for Endpoint {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(self.path());
        let _ = std::fs::remove_dir(&self.directory);
    }
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
    2
}

/// Prepare once before starting the child. Free returned socket path with gd_free_event.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_companion_prepare(host: *const Host, length: *mut usize) -> *mut u8 {
    if length.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *length = 0;
    }
    boundary::call(std::ptr::null_mut(), || {
        let Some(host) = (unsafe { host.as_ref() }) else {
            return std::ptr::null_mut();
        };
        let mut stored = host.companion.lock().unwrap_or_else(|e| e.into_inner());
        if stored.is_some() || host.running.load(Ordering::Acquire) {
            return std::ptr::null_mut();
        }
        let Ok(endpoint) = Endpoint::new() else {
            return std::ptr::null_mut();
        };
        let bytes = endpoint
            .path()
            .to_string_lossy()
            .as_bytes()
            .to_vec()
            .into_boxed_slice();
        *stored = Some(endpoint);
        unsafe {
            *length = bytes.len();
        }
        Box::into_raw(bytes).cast()
    })
}

/// Dart reports child exit before releasing the host, including startup failures.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_companion_exited(host: *const Host) {
    if let Some(host) = unsafe { host.as_ref() } {
        host.companion_exited.store(true, Ordering::Release);
    }
}

/// Blocking transport runner. Dart must also wait for its Process.exitCode before destroy.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_run_companion(host: *const Host) -> i32 {
    boundary::call(-4, || unsafe {
        crate::run_with(host, |host, initial| {
            let endpoint = host
                .companion
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .take()
                .ok_or("Companion was not prepared")?;
            let started = Instant::now();
            let socket = loop {
                match endpoint.listener.accept() {
                    Ok((socket, _)) => break socket,
                    Err(error) if error.kind() == io::ErrorKind::WouldBlock => {}
                    Err(error) => return Err(error.to_string()),
                }
                if host.companion_exited.load(Ordering::Acquire)
                    || host.sender.is_closed()
                    || started.elapsed() > Duration::from_secs(30)
                {
                    return Err(
                        "Native companion did not connect before exit or startup deadline".into(),
                    );
                }
                std::thread::sleep(Duration::from_millis(10));
            };
            run(host, initial, socket)
        })
    })
}

fn run(host: &Host, initial: Initial, mut socket: UnixStream) -> Result<(), String> {
    let trace_limit = host.trace.begin_remote();
    let mut writer_socket = socket.try_clone().map_err(|e| e.to_string())?;
    std::thread::scope(|scope| {
        let writer = scope.spawn(|| {
            let result = (|| {
                write_frame(
                    &mut writer_socket,
                    &Start {
                        version: 2,
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
                let _ = writer_socket.shutdown(Shutdown::Both);
            }
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
        let _ = socket.shutdown(Shutdown::Both);
        writer.join().map_err(|_| "Companion writer panicked")?;
        result?;
        remote_error.map_or(Ok(()), Err)
    })
}

/// Called by the native executable on its main thread. The path is copied before use.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_ui_process_main(bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || {
        if bytes.is_null() || len > 1024 {
            return -1;
        }
        let Ok(path) = std::str::from_utf8(unsafe { std::slice::from_raw_parts(bytes, len) })
        else {
            return -1;
        };
        match UnixStream::connect(path)
            .map_err(|e| e.to_string())
            .and_then(child_main)
        {
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
    if version != 2 {
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
                    // Parent death must also terminate a wedged UI process.
                    std::thread::spawn(|| {
                        std::thread::sleep(Duration::from_secs(4));
                        std::process::exit(70);
                    });
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
    #[test]
    fn frames_reject_oversize_truncation_and_bad_json() {
        let mut bytes = Vec::new();
        write_frame(&mut bytes, &Command::Close).unwrap();
        assert!(matches!(
            read_frame::<Command>(&mut bytes.as_slice()).unwrap(),
            Command::Close
        ));
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
    fn endpoint_is_private_and_removed_when_ownership_ends() {
        use std::os::unix::fs::PermissionsExt;
        let endpoint = Endpoint::new().unwrap();
        let directory = endpoint.directory.clone();
        assert_eq!(
            std::fs::metadata(&directory).unwrap().permissions().mode() & 0o777,
            0o700
        );
        assert!(endpoint.path().exists());
        drop(endpoint);
        assert!(!directory.exists());
    }
}
