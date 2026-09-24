mod protocol;
mod ui;

use async_channel::{Receiver, Sender};
use protocol::{Event, MAX_MESSAGE_BYTES, Snapshot};
use std::{
    slice,
    sync::atomic::{AtomicBool, Ordering},
    sync::{Arc, Mutex},
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
    Close,
}

pub struct Host {
    initial: Mutex<Option<Snapshot>>,
    sender: Sender<Command>,
    receiver: Receiver<Command>,
    events: Events,
    running: AtomicBool,
}

type EventCallback = extern "C" fn(*mut u8, usize);

/// `bytes` must remain readable for `len` bytes until this call returns.
/// The callback receives an owned allocation, released with `gd_free_event`.
/// Keep the callback alive until `gd_run` returns and `closed` is delivered.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_create(
    bytes: *const u8,
    len: usize,
    callback: EventCallback,
) -> *mut Host {
    if bytes.is_null() || len > MAX_MESSAGE_BYTES {
        return std::ptr::null_mut();
    }
    let Ok(initial) = Snapshot::parse(unsafe { slice::from_raw_parts(bytes, len) }) else {
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
    Box::into_raw(Box::new(Host {
        initial: Mutex::new(Some(initial)),
        sender,
        receiver,
        events,
        running: AtomicBool::new(false),
    }))
}

/// Blocking Windows UI loop. Call exactly once, on a dedicated Dart isolate.
/// `host` must remain live until the function returns.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_run(host: *const Host) -> i32 {
    if host.is_null() {
        return -1;
    }
    let host = unsafe { &*host };
    let Some(initial) = host.initial.lock().expect("initial lock").take() else {
        return -2;
    };
    host.running.store(true, Ordering::Release);
    let result = ui::run(initial, host.receiver.clone(), host.events.clone());
    host.sender.close();
    if let Err(message) = &result {
        host.events.emit(Event::Error {
            message: message.clone(),
        });
    }
    host.events.emit(Event::Closed);
    host.running.store(false, Ordering::Release);
    if result.is_ok() { 0 } else { -3 }
}

/// Copies and validates one full description. Zero means queued, not displayed.
/// -1: bad pointer/size, -2: invalid description, -3: closed or full queue.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_publish(host: *const Host, bytes: *const u8, len: usize) -> i32 {
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

/// Close is delivered even when the command queue is full.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_close(host: *const Host) {
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
    if !host.is_null() {
        let host_ref = unsafe { &*host };
        assert!(
            !host_ref.running.load(Ordering::Acquire),
            "destroy while running"
        );
        drop(unsafe { Box::from_raw(host) });
    }
}

/// `bytes` and `len` must be the exact pair delivered by the event callback.
/// Each allocation must be freed exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_free_event(bytes: *mut u8, len: usize) {
    if !bytes.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(bytes, len)) });
    }
}
