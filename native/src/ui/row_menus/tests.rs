use super::DartView;
use crate::{
    Events,
    datasets::{Change, Edit, Initial, Update},
    protocol::{Event, Snapshot, TableData},
};
use gpui_kit::test::TestWindowExt;
use gpui_kit::{AppContext, Focusable, Role, SharedString, TestAppContext, WindowOptions, gpui};
use serde_json::json;
use std::sync::{Arc, Mutex};

fn snapshot(revision: u64, descending: bool, disabled: bool) -> Snapshot {
    Snapshot::parse(&serde_json::to_vec(&json!({"revision":revision,"root":{
        "kind":"table","id":"table","dataset":"records",
        "view":{"sort":[{"column":1,"direction":if descending {"desc"} else {"asc"}}]},
        "context_menu":[{"kind":"action","id":"open","label":"Open instrument","action":"instrument.open","disabled":disabled}]
    }})).unwrap()).unwrap()
}
fn data() -> TableData {
    serde_json::from_value(json!({"columns":["Symbol","Price"],
        "rows":[["ONE","10"],["TWO","20"],["THREE","30"]],"ids":["r0","r1","r2"]}))
    .unwrap()
}
fn row(id: &str) -> SharedString {
    json!(["table", "records", "record", id]).to_string().into()
}

#[gpui::test]
fn row_menus_keep_record_identity_across_sort_edits_and_cancel_replacement(
    cx: &mut TestAppContext,
) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let out = events.clone();
    let initial = Initial::parse(
        &serde_json::to_vec(&json!({"snapshot":snapshot(1,false,false),
        "datasets":[{"id":"records","revision":1,"data":data()}]}))
        .unwrap(),
    )
    .unwrap();
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    initial,
                    Events(Arc::new(move |e| out.lock().unwrap().push(e))),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.right_click(row("r0"), cx);
        window.render_frame(cx);
        assert!(view.read(cx).row_menu.is_some());
        let popup_count = || {
            gpui_kit::base::test_support::snapshots(window)
                .iter()
                .filter(|s| s.role() == Some(Role::Menu))
                .count()
        };
        assert_eq!(
            popup_count(),
            1,
            "The Kit table's empty popup must not also open"
        );
        assert_eq!(view.read(cx).row_menu.as_ref().unwrap().target.record, "r0");
        view.update(cx, |view, cx| {
            view.publish(snapshot(2, true, false), window, cx)
        });
        view.update(cx, |view, cx| {
            view.update_dataset(
                Update {
                    request: 1,
                    id: "records".into(),
                    base_revision: 1,
                    revision: 2,
                    change: Change::Edit {
                        edits: vec![Edit::Cell {
                            row: 0,
                            column: 1,
                            value: "11".into(),
                        }],
                    },
                },
                0,
                cx,
            )
        });
        window.render_frame(cx);
        assert!(view.read(cx).row_menu.is_some());
        window.press("down", cx);
        window.press("enter", cx);
        window.render_frame(cx);
    })
    .unwrap();
    let actions: Vec<_> = events
        .lock()
        .unwrap()
        .iter()
        .filter_map(|e| match e {
            Event::RowAction {
                record,
                dataset_revision,
                revision,
                action,
                ..
            } => Some((record.clone(), *dataset_revision, *revision, action.clone())),
            _ => None,
        })
        .collect();
    assert_eq!(actions, vec![("r0".into(), 2, 2, "instrument.open".into())]);
    cx.update_window(handle, |_, window, cx| {
        assert!(view.read(cx).row_menu.is_none());
        window.click(row("r2"), cx);
        window.press("shift-f10", cx);
        window.render_frame(cx);
        assert_eq!(view.read(cx).row_menu.as_ref().unwrap().target.record, "r2");
        window.press("escape", cx);
        window.render_frame(cx);
    })
    .unwrap();
    // DismissEvent subscribers run when the current app update flushes.
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert!(view.read(cx).row_menu.is_none());
        assert!(
            view.read(cx).tables["table"]
                .state
                .read(cx)
                .focus_handle(cx)
                .is_focused(window)
        );
        window.right_click(row("r1"), cx);
        window.render_frame(cx);
        let old_serial = view.read(cx).row_menu.as_ref().unwrap().serial;
        view.update(cx, |view, cx| {
            view.update_dataset(
                Update {
                    request: 2,
                    id: "records".into(),
                    base_revision: 2,
                    revision: 3,
                    change: Change::Replace { data: data() },
                },
                0,
                cx,
            )
        });
        // Reject a stale callback even before a new frame can dismiss its popup.
        view.update(cx, |view, cx| {
            view.invoke_row_menu(old_serial, "open", "instrument.open", window, cx)
        });
        window.render_frame(cx);
        assert!(view.read(cx).row_menu.is_none());
        view.update(cx, |view, cx| {
            view.publish(snapshot(3, false, true), window, cx)
        });
        window.render_frame(cx);
        window.right_click(row("r0"), cx);
        window.render_frame(cx);
        window.press("down", cx);
        window.press("enter", cx);
        window.render_frame(cx);
        window.press("escape", cx);
        window.render_frame(cx);
        let mut no_ids = data();
        no_ids.ids = None;
        view.update(cx, |view, cx| {
            view.update_dataset(
                Update {
                    request: 3,
                    id: "records".into(),
                    base_revision: 3,
                    revision: 4,
                    change: Change::Replace { data: no_ids },
                },
                0,
                cx,
            )
        });
        let narrow = TableData {
            columns: vec!["Only".into()],
            rows: vec![vec!["one".into()]],
            ids: Some(vec!["r0".into()]),
            format: None,
        };
        view.update(cx, |view, cx| {
            view.update_dataset(
                Update {
                    request: 4,
                    id: "records".into(),
                    base_revision: 3,
                    revision: 4,
                    change: Change::Replace { data: narrow },
                },
                0,
                cx,
            )
        });
        assert_eq!(
            view.read(cx).datasets.entries["records"].borrow().revision,
            3
        );
        assert_eq!(
            view.read(cx).datasets.entries["records"]
                .borrow()
                .data
                .columns
                .len(),
            2
        );
    })
    .unwrap();
    assert_eq!(
        events
            .lock()
            .unwrap()
            .iter()
            .filter(|e| matches!(e, Event::RowAction { .. }))
            .count(),
        1
    );
    for request in [3, 4] {
        assert!(
            events
                .lock()
                .unwrap()
                .iter()
                .any(|e| matches!(e,Event::DatasetRejected{request:r,..} if *r==request))
        );
    }
}

#[test]
fn context_menu_initial_requires_record_identity() {
    let mut data = data();
    data.ids = None;
    assert!(
        Initial::parse(
            &serde_json::to_vec(&json!({"snapshot":snapshot(1,false,false),
        "datasets":[{"id":"records","revision":1,"data":data}]}))
            .unwrap()
        )
        .err()
        .unwrap()
        .contains("stable record IDs")
    );
}
