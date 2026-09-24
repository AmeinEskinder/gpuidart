use super::DartView;
use crate::{
    Events,
    protocol::{Event, Node, Snapshot, TableData},
};
use gpui_kit::gpui;
use gpui_kit::test::TestWindowExt;
use gpui_kit::{
    AppContext, Bounds, Point, ScrollDelta, TestAppContext, WindowBounds, WindowOptions, point, px,
    size,
};
use std::sync::{Arc, Mutex};

fn description(revision: u64) -> Snapshot {
    description_with_rows(revision, 10_000)
}

fn description_with_rows(revision: u64, count: usize) -> Snapshot {
    Snapshot {
        revision,
        root: Node::Column {
            id: "root".into(),
            children: vec![
                Node::Text {
                    id: "label".into(),
                    text: format!("Revision {revision}"),
                },
                Node::Button {
                    id: "increment".into(),
                    label: "Increment".into(),
                },
                Node::Input {
                    id: "name".into(),
                    placeholder: "Name".into(),
                },
                Node::Table {
                    id: "table".into(),
                    data: Arc::new(TableData {
                        columns: vec!["ID".into(), "Value".into()],
                        rows: (0..count)
                            .map(|i| vec![i.to_string(), format!("Row {i}")])
                            .collect(),
                    }),
                },
            ],
        },
    }
}

#[gpui::test]
fn construction_and_allocations_scale_with_viewport(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(Bounds {
                    origin: Point::default(),
                    size: size(px(860.), px(650.)),
                })),
                ..Default::default()
            },
            cx,
            |window, cx| {
                cx.new(|cx| {
                    DartView::new(
                        description_with_rows(1, 100),
                        Events(Arc::new(|_| {})),
                        window,
                        cx,
                    )
                })
            },
        )
        .unwrap()
    });
    let mut samples = Vec::new();
    for (i, row_count) in [100, 10_000, 100_000].into_iter().enumerate() {
        cx.update_window(handle, |_, window, cx| {
            view.update(cx, |view, cx| view.publish(description_with_rows(i as u64 + 2, row_count), window, cx));
            for _ in 0..5 { window.render_frame(cx); }
            let counters = view.read(cx).counters.clone();
            let rows_before = counters.rows.get();
            let cells_before = counters.cells.get();
            let materializations_before = counters.materializations.get();
            let (allocations, bytes) = crate::allocations::measure(|| {
                for _ in 0..10 { window.render_frame(cx); }
            });
            let rows = counters.rows.get() - rows_before;
            let cells = counters.cells.get() - cells_before;
            let materializations = counters.materializations.get() - materializations_before;
            assert_eq!(materializations, 10);
            assert!(rows > 0 && rows < 1000, "constructed {rows} rows for {row_count} records");
            assert!(cells > 0 && cells < 3000);
            samples.push(serde_json::json!({"data_rows":row_count, "frames":10, "rows_constructed":rows, "cells_constructed":cells, "allocation_calls":allocations, "allocated_bytes":bytes}));
        }).unwrap();
    }
    for sample in &samples[1..] {
        assert_eq!(sample["rows_constructed"], samples[0]["rows_constructed"]);
        assert_eq!(sample["cells_constructed"], samples[0]["cells_constructed"]);
        assert!(
            sample["allocation_calls"].as_u64().unwrap()
                < samples[0]["allocation_calls"].as_u64().unwrap() * 2
        );
        assert!(
            sample["allocated_bytes"].as_u64().unwrap()
                < samples[0]["allocated_bytes"].as_u64().unwrap() * 2
        );
    }
    let report = serde_json::json!({"scope":"headless GPUI UI thread, ten warmed redraws; excludes data construction, snapshot publication and GPU allocations", "window":{"width":860,"height":650}, "samples": samples});
    println!("VIRTUALIZATION {report}");
    if let Ok(path) = std::env::var("GPUIDART_VIRTUALIZATION_REPORT") {
        std::fs::write(path, serde_json::to_string_pretty(&report).unwrap()).unwrap();
    }
}

#[gpui::test]
fn native_events_retained_input_and_virtualized_table(cx: &mut TestAppContext) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let sink = Events(Arc::new(move |event| collected.lock().unwrap().push(event)));
    cx.update(gpui_kit::init);
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(Bounds {
                    origin: Point::default(),
                    size: size(px(860.), px(650.)),
                })),
                ..Default::default()
            },
            cx,
            |window, cx| cx.new(|cx| DartView::new(description(1), sink, window, cx)),
        )
        .unwrap()
    });

    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.click("increment", cx);
        window.click("name", cx);
        window.input("Dart 🦀", cx);
        assert_eq!(window.find("name").value(), Some("Dart 🦀"));
        window.press("shift-left", cx);
        assert_eq!(
            view.read(cx).inputs["name"].state.read(cx).selected_range(),
            5..9
        );
    })
    .unwrap();

    cx.update_window(handle, |_, window, cx| {
        let input_before = view.read(cx).inputs["name"].state.entity_id();
        let table_before = view.read(cx).tables["table"].entity_id();
        let range = view.read(cx).tables["table"]
            .read(cx)
            .visible_range()
            .rows()
            .clone();
        assert!(
            !range.is_empty() && range.len() < 100,
            "virtualized range: {range:?}"
        );

        view.update(cx, |view, cx| view.publish(description(2), window, cx));
        window.render_frame(cx);
        assert_eq!(view.read(cx).inputs["name"].state.entity_id(), input_before);
        assert_eq!(view.read(cx).tables["table"].entity_id(), table_before);
        assert_eq!(window.find("name").value(), Some("Dart 🦀"));
        assert_eq!(window.find("name").focused(), Some(true));
        assert_eq!(
            view.read(cx).inputs["name"].state.read(cx).selected_range(),
            5..9
        );

        window.scroll("table", ScrollDelta::Pixels(point(px(0.), px(-640.))), cx);
        let scrolled = view.read(cx).tables["table"]
            .read(cx)
            .visible_range()
            .rows()
            .clone();
        assert!(
            scrolled.start > range.start,
            "Wheel input must move the visible rows"
        );
        window.click("table", cx);
        let selected = view.read(cx).tables["table"].read(cx).selected_row();
        window.press("down", cx);
        let next = view.read(cx).tables["table"].read(cx).selected_row();
        assert!(
            next.is_some() && next != selected,
            "Keyboard navigation must change row selection"
        );

        let before = events.lock().unwrap().len();
        for _ in 0..10 {
            window.render_frame(cx);
        }
        assert_eq!(
            events.lock().unwrap().len(),
            before,
            "native repaints must not call Dart"
        );

        view.update(cx, |view, cx| view.publish(description(1), window, cx));
        assert_eq!(
            view.read(cx).snapshot.revision,
            2,
            "stale publication must preserve the live view"
        );
    })
    .unwrap();
    cx.simulate_window_resize(handle.into(), size(px(620.), px(720.)));
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert_eq!(window.viewport_size(), size(px(620.), px(720.)));
        assert!(window.find("name").bounds().right() <= px(620.));
        assert!(
            !view.read(cx).tables["table"]
                .read(cx)
                .visible_range()
                .rows()
                .is_empty()
        );
        view.update(cx, |view, cx| {
            view.publish(
                Snapshot {
                    revision: 3,
                    root: Node::Text {
                        id: "empty".into(),
                        text: "Closed".into(),
                    },
                },
                window,
                cx,
            )
        });
        assert!(view.read(cx).inputs.is_empty());
        assert!(view.read(cx).tables.is_empty());
    })
    .unwrap();
    let events = events.lock().unwrap();
    assert!(
        events
            .iter()
            .any(|event| matches!(event, Event::Click { revision: 1, id } if id == "increment"))
    );
    assert!(
        events
            .iter()
            .any(|event| matches!(event, Event::Input { value, .. } if value == "Dart 🦀"))
    );
}
