use gpui_kit::InteractiveElement;
use serde_json::{Value, json};
use std::cell::RefCell;

#[link(name = "user32")]
unsafe extern "system" {
    fn GetMessageExtraInfo() -> isize;
}
#[link(name = "kernel32")]
unsafe extern "system" {
    fn QueryPerformanceCounter(value: *mut i64) -> i32;
}

thread_local! {
    static EVENTS: RefCell<Vec<Value>> = const { RefCell::new(Vec::new()) };
}

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
    EVENTS.with_borrow_mut(|events| {
        events.push(json!({"stage": stage, "sequence": sequence, "qpc": qpc, "raw_message_extra": unsafe { GetMessageExtraInfo() }.to_string(), "data": data}));
    });
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
    // Bubble phase: the scrolled element's listener has applied the delta
    // by now, so a table offset recorded at the next paint is this event's.
    .on_scroll_wheel(|event, window, _| {
        let (kind, x, y) = match event.delta {
            gpui_kit::ScrollDelta::Lines(delta) => ("lines", delta.x, delta.y),
            gpui_kit::ScrollDelta::Pixels(delta) => ("pixels", f32::from(delta.x), f32::from(delta.y)),
        };
        record(
            "gpui_scroll_wheel",
            json!({"kind": kind, "x": x, "y": y, "line_height": f32::from(window.line_height()), "position_y": f32::from(event.position.y)}),
        );
    })
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
        EVENTS.with_borrow(|events| {
            std::fs::write(path, serde_json::to_vec_pretty(events).unwrap()).unwrap();
        });
    }
}
