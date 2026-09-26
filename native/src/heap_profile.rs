//! Separate diagnostic build: successful Rust global allocator requests only.
//! This does not count Dart, system malloc users, driver memory or GPU allocations.
use std::{
    alloc::{GlobalAlloc, Layout, System},
    sync::atomic::{AtomicU64, Ordering::Relaxed},
};

static LIVE: AtomicU64 = AtomicU64::new(0);
static PEAK: AtomicU64 = AtomicU64::new(0);
static ALLOCATED: AtomicU64 = AtomicU64::new(0);
static REQUESTS: AtomicU64 = AtomicU64::new(0);

struct Profiled;
#[global_allocator]
static ALLOCATOR: Profiled = Profiled;

fn acquired(size: usize) {
    REQUESTS.fetch_add(1, Relaxed);
    ALLOCATED.fetch_add(size as u64, Relaxed);
    let live = LIVE.fetch_add(size as u64, Relaxed) + size as u64;
    PEAK.fetch_max(live, Relaxed);
}

unsafe impl GlobalAlloc for Profiled {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let result = unsafe { System.alloc(layout) };
        if !result.is_null() {
            acquired(layout.size());
        }
        result
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let result = unsafe { System.alloc_zeroed(layout) };
        if !result.is_null() {
            acquired(layout.size());
        }
        result
    }
    unsafe fn realloc(&self, ptr: *mut u8, old: Layout, size: usize) -> *mut u8 {
        let result = unsafe { System.realloc(ptr, old, size) };
        if !result.is_null() {
            LIVE.fetch_sub(old.size() as u64, Relaxed);
            acquired(size);
        }
        result
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) };
        LIVE.fetch_sub(layout.size() as u64, Relaxed);
    }
}

pub(crate) fn snapshot() -> serde_json::Value {
    let live = LIVE.load(Relaxed);
    let peak = PEAK.load(Relaxed);
    let allocated = ALLOCATED.load(Relaxed);
    let requests = REQUESTS.load(Relaxed);
    serde_json::json!({
        "live_requested_bytes": live, "peak_requested_bytes": peak,
        "cumulative_requested_bytes": allocated, "successful_requests": requests,
        "scope": "Process-wide Rust global allocator requested sizes; realloc counts new size as one request. Independent concurrent counter reads, not a stop-the-world heap census. Excludes Dart, external malloc, allocator overhead and GPU. Instrumented build timings are not release baseline timings."
    })
}
