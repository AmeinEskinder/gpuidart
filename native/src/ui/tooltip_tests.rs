use super::DartView;
use crate::{Events, datasets::Initial, protocol::Snapshot};
use gpui_kit::test::TestWindowExt;
use gpui_kit::{AppContext, TestAppContext, WindowOptions, gpui};
use serde_json::json;
use std::{sync::Arc, time::Duration};

fn snapshot(help: &str) -> Result<Snapshot, String> {
    Snapshot::parse(
        &serde_json::to_vec(&json!({"revision":1,"root":{
        "kind":"column","id":"root","children":[
            {"kind":"button","id":"refresh","label":"Refresh","tooltip":help},
            {"kind":"button","id":"away","label":"Away"}
        ]}}))
        .unwrap(),
    )
}

#[test]
fn tooltip_bounds_count_utf8_bytes() {
    assert!(snapshot("").is_err());
    assert!(snapshot(&"é".repeat(512)).is_ok());
    assert!(snapshot(&"é".repeat(513)).is_err());
}

#[gpui::test]
fn tooltip_hover_preserves_button_name(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let (handle, _) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: snapshot("Update sample prices").unwrap(),
                        datasets: vec![],
                    },
                    Events(Arc::new(|_| {})),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert_eq!(window.find("refresh").label(), Some("Refresh"));
        window.hover("refresh", cx);
    })
    .unwrap();
    cx.run_until_parked();
    cx.executor().advance_clock(Duration::from_millis(700));
    cx.run_until_parked();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert_eq!(window.find("refresh").label(), Some("Refresh"));
        window.hover("away", cx);
        window.click("refresh", cx);
        assert_eq!(window.find("refresh").label(), Some("Refresh"));
    })
    .unwrap();
}
