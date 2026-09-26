use serde::{Deserialize, Serialize};
use std::borrow::Cow;
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

#[derive(Clone, Serialize, Deserialize)]
struct Record {
    name: Cow<'static, str>,
    operation: Cow<'static, str>,
    request: u64,
    start: i64,
    end: i64,
    thread: u64,
    process: u32,
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
    remote: AtomicBool,
    remote_complete: AtomicBool,
    first_paint: AtomicBool,
    buffer: Mutex<Buffer>,
}

impl Trace {
    pub fn enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    pub fn measure<T, E>(
        &self,
        name: &'static str,
        key: Key,
        bytes: Option<usize>,
        action: impl FnOnce() -> Result<T, E>,
    ) -> Result<T, E> {
        let start = self.start();
        let result = action();
        self.complete(
            name,
            key,
            start,
            bytes,
            Some(if result.is_ok() { 0 } else { -1 }),
        );
        result
    }

    pub fn first_content_paint(&self) {
        if !self.first_paint.swap(true, Ordering::Relaxed) {
            self.point(
                "native.first_content_paint",
                Key {
                    operation: "initial",
                    request: 1,
                },
                None,
                None,
            );
        }
    }
    pub fn is_remote(&self) -> bool {
        self.remote.load(Ordering::Relaxed)
    }

    #[cfg(unix)]
    pub fn begin_remote(&self) -> usize {
        self.remote.store(true, Ordering::Release);
        self.buffer.lock().unwrap_or_else(|e| e.into_inner()).limit
    }

    #[cfg(unix)]
    pub fn import_remote(&self, bytes: &[u8]) -> Result<(), String> {
        #[derive(Deserialize)]
        struct Snapshot {
            schema: u32,
            limit: usize,
            dropped: u64,
            records: Vec<Record>,
            clock_failed: bool,
        }
        let snapshot: Snapshot = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        let mut buffer = self.buffer.lock().unwrap_or_else(|e| e.into_inner());
        if snapshot.schema != 1
            || snapshot.limit != buffer.limit
            || snapshot.records.len() > buffer.limit
        {
            return Err("Invalid companion trace bounds".into());
        }
        buffer.records.extend(snapshot.records);
        buffer.records.sort_by_key(|r| r.start);
        buffer.dropped +=
            snapshot.dropped + buffer.records.len().saturating_sub(buffer.limit) as u64;
        let limit = buffer.limit;
        buffer.records.truncate(limit);
        self.clock_failed
            .fetch_or(snapshot.clock_failed, Ordering::Relaxed);
        self.remote_complete.store(true, Ordering::Release);
        Ok(())
    }
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

    /// A companion learns whether tracing is enabled after decoding its start frame.
    #[cfg(unix)]
    pub fn interval(
        &self,
        name: &'static str,
        key: Key,
        start: Option<Stamp>,
        end: Option<Stamp>,
        bytes: usize,
    ) {
        if !self.enabled() {
            return;
        }
        match (start, end) {
            (Some(start), Some(end)) => {
                self.push(name, key, start, end.ticks, Some(bytes), Some(0))
            }
            _ => self.clock_failed.store(true, Ordering::Relaxed),
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
            name: name.into(),
            operation: key.operation.into(),
            request: key.request,
            start: start.ticks,
            end,
            thread: start.thread,
            process: std::process::id(),
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
            &serde_json::json!({"schema": 1, "limit": limit, "dropped": dropped, "records": records, "clock_failed": self.clock_failed.load(Ordering::Relaxed), "remote_complete": !self.is_remote() || self.remote_complete.load(Ordering::Acquire)}),
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
    2
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

    #[cfg(unix)]
    #[test]
    fn remote_trace_merge_is_bounded_and_pending_capture_is_explicit() {
        let parent = Trace::default();
        parent.enable(2).unwrap();
        assert_eq!(parent.begin_remote(), 2);
        let pending: serde_json::Value =
            serde_json::from_slice(&parent.snapshot().unwrap()).unwrap();
        assert_eq!(pending["remote_complete"], false);
        let child = Trace::default();
        child.enable(2).unwrap();
        let key = Key {
            operation: "snapshot",
            request: 2,
        };
        parent.point("native.parse", key, None, None);
        child.point("native.dequeue", key, None, None);
        child.point("native.emit", key, None, None);
        parent.import_remote(&child.snapshot().unwrap()).unwrap();
        let merged: serde_json::Value =
            serde_json::from_slice(&parent.snapshot().unwrap()).unwrap();
        assert_eq!(merged["remote_complete"], true);
        assert_eq!(merged["dropped"], 1);
        assert_eq!(merged["records"].as_array().unwrap().len(), 2);
        assert_eq!(merged["records"][0]["process"], std::process::id());
    }

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
