//! Test-only ABI peer. Exercises Dart failure paths without opening a window.
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering::SeqCst};
use std::time::{Duration, Instant};

type Callback = extern "C" fn(*mut u8, usize);
struct Host {
    mode: String,
    callback: Callback,
    closing: AtomicBool,
    running: AtomicBool,
}
static ALLOCATED: AtomicU64 = AtomicU64::new(0);
static FREED: AtomicU64 = AtomicU64::new(0);
static DESTROYED: AtomicU64 = AtomicU64::new(0);
static EARLY_DESTROY: AtomicU64 = AtomicU64::new(0);

fn send(host: &Host, event: &str) {
    let bytes = event.as_bytes().to_vec().into_boxed_slice();
    let length = bytes.len();
    ALLOCATED.fetch_add(1, SeqCst);
    (host.callback)(Box::into_raw(bytes).cast::<u8>(), length);
}
unsafe fn message<'a>(bytes: *const u8, length: usize) -> &'a str {
    std::str::from_utf8(unsafe { std::slice::from_raw_parts(bytes, length) }).unwrap()
}
fn number(message: &str, key: &str) -> u64 {
    message
        .split_once(&format!("\"{key}\":"))
        .unwrap()
        .1
        .chars()
        .take_while(char::is_ascii_digit)
        .collect::<String>()
        .parse()
        .unwrap()
}

#[unsafe(no_mangle)]
pub extern "C" fn gd_abi_version() -> u32 {
    1
}
#[unsafe(no_mangle)]
pub extern "C" fn gd_companion_version() -> u32 {
    1
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_run_companion(host: *mut Host, _: *const u8, _: usize) -> i32 {
    unsafe { gd_run(host) }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_create(
    bytes: *const u8,
    length: usize,
    callback: Callback,
) -> *mut Host {
    Box::into_raw(Box::new(Host {
        mode: unsafe { message(bytes, length) }.into(),
        callback,
        closing: AtomicBool::new(false),
        running: AtomicBool::new(false),
    }))
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_run(host: *mut Host) -> i32 {
    let host = unsafe { &*host };
    host.running.store(true, SeqCst);
    if !host.mode.contains("no_ready") {
        send(host, r#"{"type":"ready"}"#);
    }
    let deadline = Instant::now() + Duration::from_secs(10);
    while !host.closing.load(SeqCst) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    if !host.mode.contains("no_closed") {
        send(host, r#"{"type":"closed"}"#);
    }
    if host.mode.contains("delayed_exit") {
        std::thread::sleep(Duration::from_millis(600));
    }
    host.running.store(false, SeqCst);
    if host.mode.contains("native_error") {
        -4
    } else {
        0
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_publish(host: *mut Host, bytes: *const u8, length: usize) -> i32 {
    let host = unsafe { &*host };
    if host.mode.contains("submit_panic") {
        return -4;
    }
    if host.mode.contains("native_error") {
        send(
            host,
            r#"{"type":"error","message":"injected native failure"}"#,
        );
    } else if host.mode.contains("malformed") {
        send(
            host,
            r#"{"type":"applied","revision":2,"native_apply_us":"wrong"}"#,
        );
    } else if !host.mode.contains("drop_snapshot") {
        let revision = number(unsafe { message(bytes, length) }, "revision");
        send(
            host,
            &format!(r#"{{"type":"applied","revision":{revision},"native_apply_us":0}}"#),
        );
    }
    0
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_dataset(host: *mut Host, bytes: *const u8, length: usize) -> i32 {
    let host = unsafe { &*host };
    if host.mode.contains("submit_panic") {
        return -4;
    }
    if !host.mode.contains("drop_dataset") {
        let message = unsafe { message(bytes, length) };
        let request = number(message, "request");
        let revision = number(message, "revision");
        send(
            host,
            &format!(
                r#"{{"type":"dataset_applied","request":{request},"id":"wrong-dataset","revision":{revision},"parse_us":0,"apply_us":0,"work":{{"records_checked":1,"cells_written":1}}}}"#
            ),
        );
    }
    0
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_diagnostic(host: *mut Host, _: *const u8, _: usize) -> i32 {
    if unsafe { &*host }.mode.contains("submit_panic") {
        -4
    } else {
        0
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_close(host: *mut Host) {
    unsafe { &*host }.closing.store(true, SeqCst);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_destroy(host: *mut Host) {
    if unsafe { &*host }.running.load(SeqCst) {
        EARLY_DESTROY.fetch_add(1, SeqCst);
        return;
    }
    drop(unsafe { Box::from_raw(host) });
    DESTROYED.fetch_add(1, SeqCst);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gd_free_event(bytes: *mut u8, length: usize) {
    drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(bytes, length)) });
    FREED.fetch_add(1, SeqCst);
}
#[unsafe(no_mangle)]
pub extern "C" fn fixture_allocated() -> u64 {
    ALLOCATED.load(SeqCst)
}
#[unsafe(no_mangle)]
pub extern "C" fn fixture_freed() -> u64 {
    FREED.load(SeqCst)
}
#[unsafe(no_mangle)]
pub extern "C" fn fixture_destroyed() -> u64 {
    DESTROYED.load(SeqCst)
}
#[unsafe(no_mangle)]
pub extern "C" fn fixture_early_destroy() -> u64 {
    EARLY_DESTROY.load(SeqCst)
}
