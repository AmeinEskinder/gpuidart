#[cfg(test)]
mod allocations;
mod boundary;
mod clock;
#[cfg(unix)]
mod companion;
mod datasets;
mod diagnostics;
#[cfg(feature = "snapshot-experiment")]
mod experiment;
mod input_control;
#[cfg(feature = "snapshot-experiment")]
pub use experiment::run as run_snapshot_experiment;
#[cfg(all(feature = "allocation-profile", not(test)))]
mod heap_profile;
#[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
#[path = "../../benchmarks/native/src/input_trace.rs"]
mod input_trace;
mod paint_trace;
mod protocol;
mod runtime_info;
mod trace;
mod ui;

use async_channel::{Receiver, Sender};
use protocol::{Event, MAX_MESSAGE_BYTES, Snapshot};
use std::{
    slice,
    sync::atomic::{AtomicBool, Ordering},
    sync::{Arc, Mutex},
    time::Instant,
};

#[derive(Clone)]
pub(crate) struct Events(Arc<dyn Fn(Event) + Send + Sync>);

impl Events {
    pub(crate) fn emit(&self, event: Event) {
        (self.0)(event);
    }

    /// An emitter whose events carry `window` once they reach Dart.
    pub(crate) fn for_window(&self, window: u32) -> Events {
        let inner = self.clone();
        Events(Arc::new(move |event| {
            inner.emit(Event::InWindow {
                window,
                event: Box::new(event),
            })
        }))
    }
}

#[derive(serde::Serialize, serde::Deserialize)]
/// Commands address a window: 0 is the main window, secondary windows carry
/// the ID Dart assigned when it opened them.
pub(crate) enum Command {
    Publish(u32, Snapshot),
    Update(u32, protocol::Update),
    Dataset(u32, datasets::Update, u64),
    Diagnostic(u32, diagnostics::Request),
    Input(u32, input_control::Request),
    OpenWindow(datasets::WindowOpen),
    CloseWindow(u32),
    Close,
}

impl Command {
    fn trace_key(&self) -> trace::Key {
        match self {
            Self::Publish(_, snapshot) => trace::Key {
                operation: "snapshot",
                request: snapshot.revision,
            },
            Self::Update(_, update) => trace::Key {
                operation: "snapshot",
                request: update.revision,
            },
            Self::Dataset(_, update, _) => trace::Key {
                operation: "dataset",
                request: update.request,
            },
            Self::Diagnostic(_, request) => trace::Key {
                operation: "diagnostic",
                request: request.id(),
            },
            Self::Input(_, request) => trace::Key {
                operation: "input_control",
                request: request.request,
            },
            Self::OpenWindow(open) => trace::Key {
                operation: "window",
                request: open.request,
            },
            Self::CloseWindow(window) => trace::Key {
                operation: "window",
                request: u64::from(*window),
            },
            Self::Close => trace::Key {
                operation: "close",
                request: 0,
            },
        }
    }
}

/// Queues a controlled-input read/write. Bytes are copied before returning.
/// The host and readable input buffer must be live for the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_input(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || unsafe { input(host, 0, bytes, len) })
}

/// `gd_input` addressed to a secondary window.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_window_input(
    host: *const Host,
    window: u32,
    bytes: *const u8,
    len: usize,
) -> i32 {
    boundary::call(-4, || unsafe { input(host, window, bytes, len) })
}

unsafe fn input(host: *const Host, window: u32, bytes: *const u8, len: usize) -> i32 {
    {
        if host.is_null() || bytes.is_null() || len == 0 || len > MAX_MESSAGE_BYTES {
            return -1;
        }
        let host = unsafe { &*host };
        let started = host.trace.start();
        match input_control::Request::parse(unsafe { slice::from_raw_parts(bytes, len) }) {
            Ok(request) => submit(host, Command::Input(window, request), len, started),
            Err(_) => {
                host.trace.complete(
                    "native.parse",
                    trace::Key {
                        operation: "input_control",
                        request: 0,
                    },
                    started,
                    Some(len),
                    Some(-2),
                );
                -2
            }
        }
    }
}

fn submit(host: &Host, command: Command, len: usize, started: Option<clock::Stamp>) -> i32 {
    let key = command.trace_key();
    host.trace
        .complete("native.parse", key, started, Some(len), None);
    host.trace.point("native.enqueue_attempt", key, None, None);
    let status = match host.sender.try_send(command) {
        Ok(()) => 0,
        Err(_) => -3,
    };
    host.trace
        .point("native.submit_return", key, None, Some(status));
    status
}

/// Queues an opt-in diagnostic request. Input is copied before returning.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_diagnostic(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || unsafe { diagnostic(host, 0, bytes, len) })
}

/// `gd_diagnostic` addressed to a secondary window.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_window_diagnostic(
    host: *const Host,
    window: u32,
    bytes: *const u8,
    len: usize,
) -> i32 {
    boundary::call(-4, || unsafe { diagnostic(host, window, bytes, len) })
}

unsafe fn diagnostic(host: *const Host, window: u32, bytes: *const u8, len: usize) -> i32 {
    if host.is_null() || bytes.is_null() || len > 4096 {
        return -1;
    }
    let host = unsafe { &*host };
    let started = host.trace.start();
    let Ok(request) = serde_json::from_slice(unsafe { slice::from_raw_parts(bytes, len) }) else {
        host.trace.complete(
            "native.parse",
            trace::Key {
                operation: "diagnostic",
                request: 0,
            },
            started,
            Some(len),
            Some(-2),
        );
        return -2;
    };
    submit(host, Command::Diagnostic(window, request), len, started)
}

pub struct Host {
    initial: Mutex<Option<datasets::Initial>>,
    sender: Sender<Command>,
    receiver: Receiver<Command>,
    events: Events,
    running: AtomicBool,
    trace: Arc<trace::Trace>,
    #[cfg(unix)]
    companion: Mutex<Option<companion::Endpoint>>,
    #[cfg(unix)]
    companion_exited: AtomicBool,
    #[cfg(test)]
    panic_on_run: AtomicBool,
}

type EventCallback = extern "C" fn(*mut u8, usize);

static HOST_ACTIVE: AtomicBool = AtomicBool::new(false);

/// Version of the FFI functions and JSON protocol required by this library.
#[unsafe(no_mangle)]
pub extern "C" fn gd_abi_version() -> u32 {
    1
}

/// `bytes` must remain readable for `len` bytes until this call returns.
/// The callback receives an owned allocation, released with `gd_free_event`.
/// Keep the callback alive until `gd_run` returns and `closed` is delivered.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_create(
    bytes: *const u8,
    len: usize,
    callback: EventCallback,
) -> *mut Host {
    boundary::call(std::ptr::null_mut(), || unsafe {
        create(bytes, len, callback, 0)
    })
}

/// Trace extension 2: enables tracing before initial decode and validation.
/// Pointer/callback ownership is identical to gd_create. Capacity is 1..=8192.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_create_traced(
    bytes: *const u8,
    len: usize,
    callback: EventCallback,
    capacity: usize,
) -> *mut Host {
    boundary::call(std::ptr::null_mut(), || {
        if !(1..=8192).contains(&capacity) {
            return std::ptr::null_mut();
        }
        unsafe { create(bytes, len, callback, capacity) }
    })
}

unsafe fn create(
    bytes: *const u8,
    len: usize,
    callback: EventCallback,
    capacity: usize,
) -> *mut Host {
    if bytes.is_null() || len > MAX_MESSAGE_BYTES {
        return std::ptr::null_mut();
    }
    let trace = Arc::new(trace::Trace::default());
    if capacity != 0 && trace.enable(capacity).is_err() {
        return std::ptr::null_mut();
    }
    let bytes = unsafe { slice::from_raw_parts(bytes, len) };
    let parsed = if capacity == 0 {
        datasets::Initial::parse(bytes)
    } else {
        let key = trace::Key {
            operation: "initial",
            request: 1,
        };
        trace
            .measure("native.initial_decode", key, Some(len), || {
                serde_json::from_slice::<datasets::Initial>(bytes).map_err(|e| e.to_string())
            })
            .and_then(|initial| {
                trace.measure("native.initial_validate", key, Some(len), || {
                    initial.validate()
                })?;
                Ok(initial)
            })
    };
    let Ok(initial) = parsed else {
        return std::ptr::null_mut();
    };
    let event_trace = trace.clone();
    let events = Events(Arc::new(move |event| {
        let encoded = match &event {
            Event::InWindow { window, event } => {
                let mut value = serde_json::to_value(&**event).expect("event serialization");
                value["window"] = serde_json::Value::from(*window);
                serde_json::to_vec(&value)
            }
            _ => serde_json::to_vec(&event),
        };
        let bytes = encoded.expect("event serialization").into_boxed_slice();
        let len = bytes.len();
        if !event_trace.is_remote()
            && let Some(key) = event.trace_key()
        {
            event_trace.point("native.emit", key, Some(len), None);
        }
        callback(Box::into_raw(bytes).cast(), len);
    }));
    let (sender, receiver) = async_channel::bounded(64);
    let host = Box::new(Host {
        initial: Mutex::new(Some(initial)),
        sender,
        receiver,
        events,
        running: AtomicBool::new(false),
        trace,
        #[cfg(unix)]
        companion: Mutex::new(None),
        #[cfg(unix)]
        companion_exited: AtomicBool::new(false),
        #[cfg(test)]
        panic_on_run: AtomicBool::new(false),
    });
    if HOST_ACTIVE
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return std::ptr::null_mut();
    }
    Box::into_raw(host)
}

/// Blocking Windows/Linux UI loop. Call exactly once, on a dedicated Dart isolate.
/// `host` must remain live until the function returns.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_run(host: *const Host) -> i32 {
    boundary::call(-4, || unsafe { run(host) })
}

/// Stack reserved for the thread that runs GPUI. Dart isolate threads get 1 MiB
/// on Windows, which unoptimized table rendering can exhaust; the overflow then
/// shows up as an access violation on an unrelated thread. The reservation is
/// virtual and only touched pages are committed.
/// The thread stays parked for the life of the process once the loop returns.
const UI_THREAD_STACK_BYTES: usize = 64 << 20;

unsafe fn run(host: *const Host) -> i32 {
    unsafe {
        run_with(host, |host, initial| {
            let receiver = host.receiver.clone();
            let events = host.events.clone();
            let trace = host.trace.clone();
            #[cfg(target_os = "macos")]
            {
                // GPUI needs the process main thread here; the companion
                // launcher provides it with the platform's default stack.
                ui::run(initial, receiver, events, trace, None)
            }
            #[cfg(not(target_os = "macos"))]
            {
                // The thread parks after the loop returns instead of exiting.
                // On Windows a thread exit tears down its COM apartment, which
                // pumps messages to disconnect the UIA objects an assistive
                // client created; the window procedure then runs on a thread
                // whose thread-locals are already destroyed and panics. The
                // Dart pool thread that used to run the loop never exited, and
                // this thread now matches it.
                let (result_sender, result_receiver) = std::sync::mpsc::channel();
                std::thread::Builder::new()
                    .name("gpuidart-ui".into())
                    .stack_size(UI_THREAD_STACK_BYTES)
                    .spawn(move || {
                        let result =
                            boundary::catch(|| ui::run(initial, receiver, events, trace, None));
                        let _ = result_sender.send(result);
                        loop {
                            std::thread::park();
                        }
                    })
                    .map_err(|error| format!("Could not start the UI thread: {error}"))?;
                match result_receiver.recv() {
                    Ok(Ok(result)) => result,
                    // Re-raise on the caller so the boundary reports -4 as before.
                    Ok(Err(message)) => std::panic::resume_unwind(Box::new(message)),
                    Err(_) => Err("The UI thread ended without a result".into()),
                }
            }
        })
    }
}

unsafe fn run_with(
    host: *const Host,
    execute: impl FnOnce(&Host, datasets::Initial) -> Result<(), String>,
) -> i32 {
    if host.is_null() {
        return -1;
    }
    let host = unsafe { &*host };
    host.trace.point(
        "native.runner_entry",
        trace::Key {
            operation: "initial",
            request: 1,
        },
        None,
        None,
    );
    let initial = {
        let Ok(mut initial) = host.initial.lock() else {
            return -4;
        };
        initial.take()
    };
    let Some(initial) = initial else {
        return -2;
    };
    host.running.store(true, Ordering::Release);
    struct RunGuard<'a>(&'a Host);
    impl Drop for RunGuard<'_> {
        fn drop(&mut self) {
            self.0.sender.close();
            self.0.running.store(false, Ordering::Release);
        }
    }
    let _running = RunGuard(host);
    let result = boundary::catch(|| {
        #[cfg(test)]
        assert!(
            !host.panic_on_run.load(Ordering::Acquire),
            "injected UI failure"
        );
        execute(host, initial)
    });
    let (result, status) = match result {
        Ok(result) => {
            let status = if result.is_ok() { 0 } else { -3 };
            (result, status)
        }
        Err(message) => (Err(format!("Native UI panic: {message}")), -4),
    };
    #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
    input_trace::save();
    host.sender.close();
    if let Err(message) = &result {
        host.events.emit(Event::Error {
            message: message.clone(),
        });
    }
    host.events.emit(Event::Closed);
    status
}

/// Copies and validates one full description. Zero means queued, not displayed.
/// -1: bad pointer/size, -2: invalid description, -3: closed or full queue.
/// -4: a Rust panic was caught; discard the host after closing it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_publish(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || unsafe { publish(host, 0, bytes, len) })
}

/// `gd_publish` addressed to a secondary window.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_window_publish(
    host: *const Host,
    window: u32,
    bytes: *const u8,
    len: usize,
) -> i32 {
    boundary::call(-4, || unsafe { publish(host, window, bytes, len) })
}

unsafe fn publish(host: *const Host, window: u32, bytes: *const u8, len: usize) -> i32 {
    if host.is_null() || bytes.is_null() || len > MAX_MESSAGE_BYTES {
        return -1;
    }
    let host = unsafe { &*host };
    let started = host.trace.start();
    match Snapshot::parse(unsafe { slice::from_raw_parts(bytes, len) }) {
        Ok(snapshot) => submit(host, Command::Publish(window, snapshot), len, started),
        Err(_) => {
            host.trace.complete(
                "native.parse",
                trace::Key {
                    operation: "snapshot",
                    request: 0,
                },
                started,
                Some(len),
                Some(-2),
            );
            -2
        }
    }
}

/// Copies and validates operations against the applied description. Same
/// statuses as `gd_publish`; a stale base revision or a failing operation is
/// reported asynchronously as `rejected` and leaves the applied description.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_update(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || unsafe { update(host, 0, bytes, len) })
}

/// `gd_update` addressed to a secondary window.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_window_update(
    host: *const Host,
    window: u32,
    bytes: *const u8,
    len: usize,
) -> i32 {
    boundary::call(-4, || unsafe { update(host, window, bytes, len) })
}

unsafe fn update(host: *const Host, window: u32, bytes: *const u8, len: usize) -> i32 {
    if host.is_null() || bytes.is_null() || len > MAX_MESSAGE_BYTES {
        return -1;
    }
    let host = unsafe { &*host };
    let started = host.trace.start();
    match protocol::Update::parse(unsafe { slice::from_raw_parts(bytes, len) }) {
        Ok(update) => submit(host, Command::Update(window, update), len, started),
        Err(_) => {
            host.trace.complete(
                "native.parse",
                trace::Key {
                    operation: "snapshot",
                    request: 0,
                },
                started,
                Some(len),
                Some(-2),
            );
            -2
        }
    }
}

/// Copies a revisioned dataset transaction. Application/rejection is asynchronous.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_dataset(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || unsafe { dataset(host, 0, bytes, len) })
}

/// `gd_dataset` addressed to a secondary window.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_window_dataset(
    host: *const Host,
    window: u32,
    bytes: *const u8,
    len: usize,
) -> i32 {
    boundary::call(-4, || unsafe { dataset(host, window, bytes, len) })
}

/// Opens a secondary window from `{request, id, initial}`. Statuses match
/// gd_publish; window_opened or window_rejected completes the request.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_window_open(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || unsafe { window_open(host, bytes, len) })
}

unsafe fn window_open(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    if host.is_null() || bytes.is_null() || len > MAX_MESSAGE_BYTES {
        return -1;
    }
    let host = unsafe { &*host };
    let started = host.trace.start();
    match datasets::WindowOpen::parse(unsafe { slice::from_raw_parts(bytes, len) }) {
        Ok(open) => submit(host, Command::OpenWindow(open), len, started),
        Err(_) => {
            host.trace.complete(
                "native.parse",
                trace::Key {
                    operation: "window",
                    request: 0,
                },
                started,
                Some(len),
                Some(-2),
            );
            -2
        }
    }
}

/// Asks native to close a secondary window; window_closed follows. Closing
/// window 0 closes the application like gd_close. -1 for a null host, -3
/// when the queue is closed or full.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_window_close(host: *const Host, window: u32) -> i32 {
    boundary::call(-4, || {
        if host.is_null() {
            return -1;
        }
        let host = unsafe { &*host };
        submit(host, Command::CloseWindow(window), 0, host.trace.start())
    })
}

unsafe fn dataset(host: *const Host, window: u32, bytes: *const u8, len: usize) -> i32 {
    if host.is_null() || bytes.is_null() || len > MAX_MESSAGE_BYTES {
        return -1;
    }
    let host = unsafe { &*host };
    let started = host.trace.start();
    let timer = Instant::now();
    let Ok(update) = datasets::Update::parse(unsafe { slice::from_raw_parts(bytes, len) }) else {
        host.trace.complete(
            "native.parse",
            trace::Key {
                operation: "dataset",
                request: 0,
            },
            started,
            Some(len),
            Some(-2),
        );
        return -2;
    };
    let parse_us = timer.elapsed().as_micros() as u64;
    submit(
        host,
        Command::Dataset(window, update, parse_us),
        len,
        started,
    )
}

/// Close is delivered even when the command queue is full.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_close(host: *const Host) {
    boundary::call((), || unsafe { close(host) });
}

unsafe fn close(host: *const Host) {
    if host.is_null() {
        return;
    }
    let host = unsafe { &*host };
    host.trace.point(
        "native.close",
        trace::Key {
            operation: "close",
            request: 0,
        },
        None,
        None,
    );
    let _ = host.sender.try_send(Command::Close);
    host.sender.close();
}

/// Call only after `gd_run` has returned and no other API calls are in flight.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_destroy(host: *mut Host) {
    boundary::call((), || unsafe { destroy(host) });
}

unsafe fn destroy(host: *mut Host) {
    if !host.is_null() {
        let host_ref = unsafe { &*host };
        if host_ref.running.load(Ordering::Acquire) {
            return;
        }
        drop(unsafe { Box::from_raw(host) });
        HOST_ACTIVE.store(false, Ordering::Release);
    }
}

/// `bytes` and `len` must be the exact pair delivered by the event callback.
/// Each allocation must be freed exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_free_event(bytes: *mut u8, len: usize) {
    boundary::call((), || unsafe { free_event(bytes, len) });
}

unsafe fn free_event(bytes: *mut u8, len: usize) {
    if !bytes.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(bytes, len)) });
    }
}

#[cfg(test)]
mod ffi_tests;
#[cfg(all(test, windows))]
mod startup_probe_tests;
