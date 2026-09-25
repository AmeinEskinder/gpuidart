use serde::Serialize;
use std::sync::{
    Mutex,
    atomic::{AtomicBool, Ordering},
};

use crate::clock::Stamp;

#[derive(Clone, Copy)]
pub(crate) struct Key {
    pub operation: &'static str,
    pub request: u64,
}

#[derive(Clone, Serialize)]
struct Record {
    name: &'static str,
    operation: &'static str,
    request: u64,
    start: i64,
    end: i64,
    thread: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    bytes: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    status: Option<i32>,
}

#[derive(Default, Serialize)]
struct Buffer {
    limit: usize,
    dropped: u64,
    records: Vec<Record>,
}

#[derive(Default)]
pub(crate) struct Trace {
    enabled: AtomicBool,
    clock_failed: AtomicBool,
    buffer: Mutex<Buffer>,
}

impl Trace {
    /// Called once before starting the native loop. Normal hosts never enable it.
    pub fn enable(&self, limit: usize) -> Result<(), ()> {
        if !(1..=8192).contains(&limit) {
            return Err(());
        }
        let mut buffer = self.buffer.lock().unwrap_or_else(|e| e.into_inner());
        if self.enabled.load(Ordering::Acquire) {
            return Err(());
        }
        buffer.limit = limit;
        buffer.records = Vec::with_capacity(limit);
        self.enabled.store(true, Ordering::Release);
        Ok(())
    }

    pub fn start(&self) -> Option<Stamp> {
        if !self.enabled.load(Ordering::Relaxed) {
            return None;
        }
        let stamp = crate::clock::now();
        if stamp.is_none() {
            self.clock_failed.store(true, Ordering::Relaxed);
        }
        stamp
    }

    pub fn complete(
        &self,
        name: &'static str,
        key: Key,
        start: Option<Stamp>,
        bytes: Option<usize>,
        status: Option<i32>,
    ) {
        if let Some(start) = start
            && let Some(end) = self.start()
        {
            self.push(name, key, start, end.ticks, bytes, status);
        }
    }

    pub fn point(&self, name: &'static str, key: Key, bytes: Option<usize>, status: Option<i32>) {
        if let Some(stamp) = self.start() {
            self.push(name, key, stamp, stamp.ticks, bytes, status);
        }
    }

    fn push(
        &self,
        name: &'static str,
        key: Key,
        start: Stamp,
        end: i64,
        bytes: Option<usize>,
        status: Option<i32>,
    ) {
        let mut buffer = self.buffer.lock().unwrap_or_else(|e| e.into_inner());
        if buffer.records.len() == buffer.limit {
            buffer.dropped += 1;
            return;
        }
        buffer.records.push(Record {
            name,
            operation: key.operation,
            request: key.request,
            start: start.ticks,
            end,
            thread: start.thread,
            bytes,
            status,
        });
    }

    pub fn dispatch(&self, key: Key) -> Dispatch<'_> {
        Dispatch {
            trace: self,
            key,
            start: self.start(),
        }
    }

    pub fn snapshot(&self) -> Result<Vec<u8>, serde_json::Error> {
        let (limit, dropped, records) = {
            let buffer = self.buffer.lock().unwrap_or_else(|e| e.into_inner());
            (buffer.limit, buffer.dropped, buffer.records.clone())
        };
        serde_json::to_vec(
            &serde_json::json!({"schema": 1, "limit": limit, "dropped": dropped, "records": records, "clock_failed": self.clock_failed.load(Ordering::Relaxed)}),
        )
    }
}

pub(crate) struct Dispatch<'a> {
    trace: &'a Trace,
    key: Key,
    start: Option<Stamp>,
}

impl Drop for Dispatch<'_> {
    fn drop(&mut self) {
        self.trace
            .complete("native.dispatch", self.key, self.start, None, None);
    }
}

impl crate::protocol::Event {
    pub(crate) fn trace_key(&self) -> Option<Key> {
        use crate::protocol::Event::*;
        Some(match self {
            Applied { revision, .. } | Rejected { revision, .. } => Key {
                operation: "snapshot",
                request: *revision,
            },
            DatasetApplied { request, .. } | DatasetRejected { request, .. } => Key {
                operation: "dataset",
                request: *request,
            },
            Diagnostic { request, .. } => Key {
                operation: "diagnostic",
                request: *request,
            },
            Ready => Key {
                operation: "initial",
                request: 1,
            },
            Closed => Key {
                operation: "close",
                request: 0,
            },
            Error { .. } => Key {
                operation: "failure",
                request: 0,
            },
            _ => return None,
        })
    }
}

/// Optional trace extension version. The ordinary host ABI is unchanged.
#[unsafe(no_mangle)]
pub extern "C" fn gd_trace_version() -> u32 {
    1
}

/// `host` must be live. Enable once before gd_run; limit must be 1..=8192.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_trace_enable(host: *const crate::Host, limit: usize) -> i32 {
    crate::boundary::call(-4, || {
        let Some(host) = (unsafe { host.as_ref() }) else {
            return -1;
        };
        let Ok(initial) = host.initial.lock() else {
            return -4;
        };
        if initial.is_none() {
            return -2;
        }
        if host.trace.enable(limit).is_ok() {
            0
        } else {
            -2
        }
    })
}

/// `host` must be live and `length` writable. Free returned bytes with gd_free_event.
/// A null return has length zero. This call does not drain or reset the buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_trace_read(host: *const crate::Host, length: *mut usize) -> *mut u8 {
    if length.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *length = 0;
    }
    crate::boundary::call(std::ptr::null_mut(), || {
        let Some(host) = (unsafe { host.as_ref() }) else {
            return std::ptr::null_mut();
        };
        let Ok(bytes) = host.trace.snapshot() else {
            return std::ptr::null_mut();
        };
        let bytes = bytes.into_boxed_slice();
        unsafe {
            *length = bytes.len();
        }
        Box::into_raw(bytes).cast()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tracing_is_opt_in_bounded_and_preserves_complete_records() {
        let trace = Trace::default();
        let key = Key {
            operation: "dataset",
            request: 7,
        };
        assert!(trace.start().is_none());
        trace.point("native.enqueue", key, None, None);
        assert_eq!(trace.buffer.lock().unwrap().records.len(), 0);
        assert!(trace.enable(8193).is_err());
        trace.enable(2).unwrap();
        assert!(trace.enable(2).is_err());
        trace.point("native.enqueue", key, Some(150), None);
        {
            let _dispatch = trace.dispatch(key);
        }
        trace.point("native.emit", key, None, None);
        let value: serde_json::Value = serde_json::from_slice(&trace.snapshot().unwrap()).unwrap();
        assert_eq!(value["records"].as_array().unwrap().len(), 2);
        assert_eq!(value["dropped"], 1);
        assert_eq!(value["records"][0]["request"], 7);
        assert_eq!(value["records"][0]["bytes"], 150);
        assert_eq!(value["records"][1]["name"], "native.dispatch");
        assert!(
            value["records"][1]["end"].as_i64().unwrap()
                >= value["records"][1]["start"].as_i64().unwrap()
        );
    }
}
