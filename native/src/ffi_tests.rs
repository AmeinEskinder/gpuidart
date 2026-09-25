use super::*;
use serde_json::Value;
use std::ptr::null;

static EVENTS: Mutex<Vec<Value>> = Mutex::new(Vec::new());

extern "C" fn event(bytes: *mut u8, len: usize) {
    let value = serde_json::from_slice(unsafe { slice::from_raw_parts(bytes, len) }).unwrap();
    EVENTS.lock().unwrap().push(value);
    unsafe { gd_free_event(bytes, len) };
}

#[test]
fn ffi_rejects_bad_messages_bounds_queues_and_reports_unwind() {
    let initial =
        br#"{"snapshot":{"revision":1,"root":{"kind":"text","id":"a","text":"a"}},"datasets":[]}"#;
    unsafe {
        assert!(gd_create(null(), 1, event).is_null());
        assert!(gd_create(b"{".as_ptr(), 1, event).is_null());
        assert_eq!(gd_run(null()), -1);
        let host = gd_create(initial.as_ptr(), initial.len(), event);
        assert!(!host.is_null());
        assert_eq!(trace::gd_trace_version(), 1);
        assert_eq!(trace::gd_trace_enable(null(), 8), -1);
        assert_eq!(trace::gd_trace_enable(host, 0), -2);
        assert_eq!(trace::gd_trace_enable(host, 256), 0);
        assert_eq!(trace::gd_trace_enable(host, 256), -2);
        assert!(gd_create(initial.as_ptr(), initial.len(), event).is_null());
        assert_eq!(gd_publish(host, null(), 0), -1);
        assert_eq!(
            gd_publish(host, initial.as_ptr(), MAX_MESSAGE_BYTES + 1),
            -1
        );
        assert_eq!(gd_dataset(host, b"{".as_ptr(), 1), -2);
        assert_eq!(gd_diagnostic(host, b"{".as_ptr(), 1), -2);
        let snapshot = br#"{"revision":2,"root":{"kind":"text","id":"a","text":"b"}}"#;
        for _ in 0..64 {
            assert_eq!(gd_publish(host, snapshot.as_ptr(), snapshot.len()), 0);
        }
        assert_eq!(gd_publish(host, snapshot.as_ptr(), snapshot.len()), -3);
        let mut length = 0;
        assert!(trace::gd_trace_read(host, std::ptr::null_mut()).is_null());
        assert!(trace::gd_trace_read(null(), &mut length).is_null());
        assert_eq!(length, 0);
        let bytes = trace::gd_trace_read(host, &mut length);
        assert!(!bytes.is_null());
        let capture: Value = serde_json::from_slice(slice::from_raw_parts(bytes, length)).unwrap();
        gd_free_event(bytes, length);
        let records = capture["records"].as_array().unwrap();
        assert!(records.iter().any(|record| record["status"] == -3));
        assert!(
            records
                .iter()
                .any(|record| record["name"] == "native.parse" && record["request"] == 2)
        );
        assert_eq!(capture["dropped"], 0);
        gd_close(host);
        assert_eq!(gd_publish(host, snapshot.as_ptr(), snapshot.len()), -3);
        gd_destroy(host);

        let host = gd_create(initial.as_ptr(), initial.len(), event);
        assert!(!host.is_null());
        (*host).panic_on_run.store(true, Ordering::Release);
        assert_eq!(gd_run(host), -4);
        assert!(!(*host).running.load(Ordering::Acquire));
        assert!((*host).sender.is_closed());
        let events = EVENTS.lock().unwrap();
        assert_eq!(events[0]["type"], "error");
        assert!(
            events[0]["message"]
                .as_str()
                .unwrap()
                .contains("injected UI failure")
        );
        assert_eq!(events[1]["type"], "closed");
        drop(events);
        gd_destroy(host);
        let host = gd_create(initial.as_ptr(), initial.len(), event);
        assert!(!host.is_null());
        gd_destroy(host);
    }
}
