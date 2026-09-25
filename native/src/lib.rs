#[cfg(test)]
mod allocations;
mod boundary;
mod datasets;
mod diagnostics;
#[cfg(feature = "benchmark-trace")]
#[path = "../../benchmarks/native/src/input_trace.rs"]
mod input_trace;
mod protocol;
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
}

pub(crate) enum Command {
    Publish(Snapshot),
    Dataset(datasets::Update, u64),
    Diagnostic(diagnostics::Request),
    Close,
}

/// Queues an opt-in diagnostic request. Input is copied before returning.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_diagnostic(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || unsafe { diagnostic(host, bytes, len) })
}

unsafe fn diagnostic(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    if host.is_null() || bytes.is_null() || len > 4096 {
        return -1;
    }
    let host = unsafe { &*host };
    let Ok(request) = serde_json::from_slice(unsafe { slice::from_raw_parts(bytes, len) }) else {
        return -2;
    };
    match host.sender.try_send(Command::Diagnostic(request)) {
        Ok(()) => 0,
        Err(_) => -3,
    }
}

pub struct Host {
    initial: Mutex<Option<datasets::Initial>>,
    sender: Sender<Command>,
    receiver: Receiver<Command>,
    events: Events,
    running: AtomicBool,
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
        create(bytes, len, callback)
    })
}

unsafe fn create(bytes: *const u8, len: usize, callback: EventCallback) -> *mut Host {
    if bytes.is_null() || len > MAX_MESSAGE_BYTES {
        return std::ptr::null_mut();
    }
    let Ok(initial) = datasets::Initial::parse(unsafe { slice::from_raw_parts(bytes, len) }) else {
        return std::ptr::null_mut();
    };
    let events = Events(Arc::new(move |event| {
        let bytes = serde_json::to_vec(&event)
            .expect("event serialization")
            .into_boxed_slice();
        let len = bytes.len();
        callback(Box::into_raw(bytes).cast(), len);
    }));
    let (sender, receiver) = async_channel::bounded(64);
    let host = Box::new(Host {
        initial: Mutex::new(Some(initial)),
        sender,
        receiver,
        events,
        running: AtomicBool::new(false),
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

/// Blocking Windows UI loop. Call exactly once, on a dedicated Dart isolate.
/// `host` must remain live until the function returns.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_run(host: *const Host) -> i32 {
    boundary::call(-4, || unsafe { run(host) })
}

unsafe fn run(host: *const Host) -> i32 {
    if host.is_null() {
        return -1;
    }
    let host = unsafe { &*host };
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
        ui::run(initial, host.receiver.clone(), host.events.clone())
    });
    let (result, status) = match result {
        Ok(result) => {
            let status = if result.is_ok() { 0 } else { -3 };
            (result, status)
        }
        Err(message) => (Err(format!("Native UI panic: {message}")), -4),
    };
    #[cfg(feature = "benchmark-trace")]
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
    boundary::call(-4, || unsafe { publish(host, bytes, len) })
}

unsafe fn publish(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    if host.is_null() || bytes.is_null() || len > MAX_MESSAGE_BYTES {
        return -1;
    }
    let host = unsafe { &*host };
    match Snapshot::parse(unsafe { slice::from_raw_parts(bytes, len) }) {
        Ok(snapshot) => match host.sender.try_send(Command::Publish(snapshot)) {
            Ok(()) => 0,
            Err(_) => -3,
        },
        Err(_) => -2,
    }
}

/// Copies a revisioned dataset transaction. Application/rejection is asynchronous.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_dataset(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    boundary::call(-4, || unsafe { dataset(host, bytes, len) })
}

unsafe fn dataset(host: *const Host, bytes: *const u8, len: usize) -> i32 {
    if host.is_null() || bytes.is_null() || len > MAX_MESSAGE_BYTES {
        return -1;
    }
    let timer = Instant::now();
    let Ok(update) = datasets::Update::parse(unsafe { slice::from_raw_parts(bytes, len) }) else {
        return -2;
    };
    let parse_us = timer.elapsed().as_micros() as u64;
    match unsafe { &*host }
        .sender
        .try_send(Command::Dataset(update, parse_us))
    {
        Ok(()) => 0,
        Err(_) => -3,
    }
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
