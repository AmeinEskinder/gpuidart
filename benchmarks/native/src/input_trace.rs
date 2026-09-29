use gpui_kit::InteractiveElement;
use serde_json::{Value, json};
use std::sync::Mutex;

#[link(name = "user32")]
unsafe extern "system" {
    fn GetMessageExtraInfo() -> isize;
}
#[link(name = "kernel32")]
unsafe extern "system" {
    fn QueryPerformanceCounter(value: *mut i64) -> i32;
}

/// Process-wide, not thread-local: the events are recorded on the thread
/// that runs the GPUI loop and saved when `gd_run` returns, and a
/// thread-local list left the saved trace empty once those differed.
static EVENTS: Mutex<Vec<Value>> = Mutex::new(Vec::new());

pub fn sequence() -> Option<u64> {
    let tag = unsafe { GetMessageExtraInfo() } as u64;
    (tag & 0xffff_0000 == 0x4750_0000).then_some(tag & 0xffff)
}

pub fn record(stage: &str, data: Value) {
    record_sequence(stage, sequence(), data);
}

pub fn record_sequence(stage: &str, sequence: Option<u64>, data: Value) {
    let mut qpc = 0;
    unsafe { QueryPerformanceCounter(&mut qpc) };
    EVENTS.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).push(json!({"stage": stage, "sequence": sequence, "qpc": qpc, "raw_message_extra": unsafe { GetMessageExtraInfo() }.to_string(), "data": data}));
}

pub fn observe<E: InteractiveElement>(root: E) -> E {
    root.capture_any_mouse_down(|event, _, _| {
        record(
            "gpui_mouse_down",
            json!({"x": f32::from(event.position.x), "y": f32::from(event.position.y)}),
        );
    })
    .capture_any_mouse_up(|event, _, _| {
        record(
            "gpui_mouse_up",
            json!({"x": f32::from(event.position.x), "y": f32::from(event.position.y)}),
        );
    })
}

/// A wheel event GPUI dispatched, with the delta it carried and the line
/// height the scrolled element turns line deltas into pixels with.
pub fn record_wheel(event: &gpui_kit::ScrollWheelEvent, line_height: f32) {
    let (kind, x, y) = match event.delta {
        gpui_kit::ScrollDelta::Lines(delta) => ("lines", delta.x, delta.y),
        gpui_kit::ScrollDelta::Pixels(delta) => ("pixels", f32::from(delta.x), f32::from(delta.y)),
    };
    record(
        "gpui_scroll_wheel",
        json!({"kind": kind, "x": x, "y": y, "line_height": line_height, "position_y": f32::from(event.position.y)}),
    );
}

/// A table's vertical offset at a paint, so the offset trajectory can be
/// read against the wheel deltas that produced it.
pub fn record_table_scroll(id: &str, frame: u64, y: f32) {
    record_sequence(
        "table_scroll_painted",
        None,
        json!({"id": id, "frame": frame, "y": y}),
    );
}

pub fn save() {
    if let Some(path) = std::env::var_os("GPUIDART_NATIVE_TRACE") {
        let events = EVENTS
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        std::fs::write(path, serde_json::to_vec_pretty(&*events).unwrap()).unwrap();
    }
}
