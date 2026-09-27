use super::DartView;
use crate::{
    Events,
    datasets::{Change, Edit, Initial, Update, Upload},
    protocol::{Event, Snapshot, TableData},
};
use gpui_kit::test::TestWindowExt;
use gpui_kit::{AppContext, Role, SharedString, TestAppContext, WindowOptions, gpui};
use serde_json::{Value, json};
use std::{
    rc::Rc,
    sync::{Arc, Mutex},
};

fn snapshot(revision: u64, view: Value) -> Snapshot {
    Snapshot::parse(&serde_json::to_vec(&json!({"revision":revision,"root":{
        "kind":"column","id":"root","children":(["line","bar"].map(|series|json!({
            "kind":"chart","id":series,"semantics":{"role":"chart","label":format!("{series} prices")},
            "chart":{"series":series,"dataset":"history","label_column":0,
                "value_column":if series=="line" {1} else {2},"max_points":12,"height":120,"view":view}
        })))
    }})).unwrap()).unwrap()
}
fn data(count: usize) -> TableData {
    TableData {
        columns: vec![
            "Day".into(),
            "Price".into(),
            "Volume".into(),
            "Other".into(),
        ],
        rows: (0..count)
            .map(|i| {
                vec![
                    "Same label".into(),
                    format!("{}", (i % 10) as i32 - 5),
                    "20".into(),
                    "yes".into(),
                ]
            })
            .collect(),
        ids: Some((0..count).map(|i| format!("r{i}")).collect()),
        format: None,
    }
}

#[gpui::test]
fn chart_projection_is_bounded_cached_and_shared_with_alternatives(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let out = events.clone();
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: snapshot(1, Value::Null),
                        datasets: vec![Upload {
                            id: "history".into(),
                            revision: 1,
                            data: data(100_000),
                        }],
                    },
                    Events(Arc::new(move |event| out.lock().unwrap().push(event))),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert_eq!(window.find("line").role(), Some(Role::Group));
        assert_eq!(window.find("line").label(), Some("line prices"));
        let summary = SharedString::from(json!(["line", "summary"]).to_string());
        assert!(
            window
                .find(summary)
                .value()
                .unwrap()
                .contains("12 points from 100000 view rows")
        );
        let points = view.read(cx).charts["line"].points.clone();
        assert_eq!(points.len(), 12);
        assert_eq!(points[0].record.as_deref(), Some("r99988"));
        for revision in 2..5 {
            view.update(cx, |v, cx| {
                v.publish(snapshot(revision, Value::Null), window, cx)
            });
            window.render_frame(cx);
            assert!(Rc::ptr_eq(&points, &view.read(cx).charts["line"].points));
        }
        for (revision, column, value) in [
            (2, 3, "untouched"),
            (3, 1, "NaN"),
            (4, 1, "1000000000001"),
            (5, 1, "-7"),
        ] {
            view.update(cx, |v, cx| {
                v.update_dataset(
                    Update {
                        request: revision,
                        id: "history".into(),
                        base_revision: revision - 1,
                        revision,
                        change: Change::Edit {
                            edits: vec![Edit::Cell {
                                row: 99_999,
                                column,
                                value: value.into(),
                            }],
                        },
                    },
                    0,
                    cx,
                )
            });
            window.render_frame(cx);
            let chart = &view.read(cx).charts["line"];
            assert_eq!(chart.revision, revision);
            assert_eq!(
                chart.omitted,
                if revision == 3 || revision == 4 { 1 } else { 0 }
            );
            assert_eq!(view.read(cx).charts["bar"].projections, 1);
        }
        let r = &view.read(cx).charts["line"];
        assert_eq!(r.projections, 4);
        assert_eq!(r.points.last().unwrap().value, -7.);
        assert_eq!(r.excluded, 99_988);
        // A filter column edit changes the projection; source data stays intact.
        view.update(cx, |v, cx| {
            v.publish(
                snapshot(
                    5,
                    json!({"filter":[{"column":3,"op":"eq","value":"untouched"}]}),
                ),
                window,
                cx,
            )
        });
        window.render_frame(cx);
        assert_eq!(view.read(cx).charts["line"].points.len(), 1);
        view.update(cx, |v, cx| {
            v.update_dataset(
                Update {
                    request: 6,
                    id: "history".into(),
                    base_revision: 5,
                    revision: 6,
                    change: Change::Edit {
                        edits: vec![Edit::Cell {
                            row: 99_999,
                            column: 3,
                            value: "yes".into(),
                        }],
                    },
                },
                0,
                cx,
            )
        });
        window.render_frame(cx);
        assert!(view.read(cx).charts["line"].points.is_empty());
        assert!(
            view.read(cx).inspect_charts()["line"]["summary"]
                .as_str()
                .unwrap()
                .contains("No valid points")
        );
        // Replacing with a narrower shape and releasing a mounted consumer reject atomically.
        let mut narrow = data(1);
        narrow.columns.truncate(1);
        narrow.rows[0].truncate(1);
        for change in [Change::Replace { data: narrow }, Change::Release] {
            view.update(cx, |v, cx| {
                v.update_dataset(
                    Update {
                        request: 7,
                        id: "history".into(),
                        base_revision: 6,
                        revision: 7,
                        change,
                    },
                    0,
                    cx,
                )
            });
            assert_eq!(
                view.read(cx).datasets.entries["history"].borrow().revision,
                6
            );
        }
    })
    .unwrap();
    assert_eq!(
        events
            .lock()
            .unwrap()
            .iter()
            .filter(|e| matches!(e, Event::DatasetRejected { .. }))
            .count(),
        2
    );
}

#[test]
fn chart_wire_bounds_unknown_fields_and_dataset_references() {
    let valid = serde_json::to_value(snapshot(1, Value::Null)).unwrap();
    for (key, value) in [
        ("series", json!("pie")),
        ("max_points", json!(0)),
        ("max_points", json!(513)),
        ("height", json!(79)),
        ("height", json!(1025)),
        ("label_column", json!(64)),
        ("value_column", json!(64)),
        ("dataset", json!("")),
        ("callback", json!("no")),
    ] {
        let mut invalid = valid.clone();
        invalid["root"]["children"][0]["chart"][key] = value;
        assert!(
            Snapshot::parse(&serde_json::to_vec(&invalid).unwrap()).is_err(),
            "{key}"
        );
    }
    for datasets in [
        vec![],
        vec![Upload {
            id: "wrong".into(),
            revision: 1,
            data: data(1),
        }],
    ] {
        assert!(
            Initial {
                window: Default::default(),
                snapshot: snapshot(1, Value::Null),
                datasets
            }
            .validate()
            .is_err()
        );
    }
}
