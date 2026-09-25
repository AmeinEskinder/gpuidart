use super::DartView;
use crate::{
    Events,
    datasets::{Change, Initial, Update, Upload},
    protocol::{Event, Node, Snapshot, TableData},
};
use gpui_kit::component::ActiveTheme;
use gpui_kit::gpui;
use gpui_kit::test::TestWindowExt;
use gpui_kit::{
    AppContext, Bounds, Point, ScrollDelta, TestAppContext, WindowBounds, WindowOptions, point, px,
    size,
};
use std::sync::{Arc, Mutex};

fn description(revision: u64) -> Snapshot {
    Snapshot {
        revision,
        root: Node::Column {
            id: "root".into(),
            style: None,
            children: vec![
                Node::Text {
                    id: "label".into(),
                    style: None,
                    text: format!("Revision {revision}"),
                },
                Node::Button {
                    id: "increment".into(),
                    style: None,
                    label: "Increment".into(),
                },
                Node::Input {
                    id: "name".into(),
                    style: None,
                    placeholder: "Name".into(),
                },
                Node::Table {
                    id: "table".into(),
                    style: None,
                    dataset: "records".into(),
                },
            ],
        },
    }
}

fn table_data(count: usize) -> TableData {
    TableData {
        columns: vec!["ID".into(), "Value".into()],
        rows: (0..count)
            .map(|i| vec![i.to_string(), format!("Row {i}")])
            .collect(),
    }
}

fn initial(count: usize) -> Initial {
    Initial {
        window: Default::default(),
        snapshot: description(1),
        datasets: vec![Upload {
            id: "records".into(),
            revision: 1,
            data: table_data(count),
        }],
    }
}

#[gpui::test]
fn narrow_windows_wrap_actions_and_scroll_to_footer(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(Bounds {
                    origin: Point::default(),
                    size: size(px(360.), px(320.)),
                })),
                ..Default::default()
            },
            cx,
            |window, cx| {
                let mut data = initial(100);
                let Node::Column { children, .. } = &mut data.snapshot.root else {
                    unreachable!()
                };
                children.insert(
                    1,
                    Node::Row {
                        id: "actions".into(),
                        style: None,
                        children: (0..3)
                            .map(|i| Node::Button {
                                id: format!("action-{i}"),
                                style: None,
                                label: format!("A long action label {i}"),
                            })
                            .collect(),
                    },
                );
                children.push(Node::Button {
                    id: "footer".into(),
                    style: None,
                    label: "End of screen".into(),
                });
                cx.new(|cx| DartView::new(data, Events(Arc::new(|_| {})), window, cx))
            },
        )
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        for id in ["action-0", "action-1", "action-2"] {
            assert!(
                window.find(id).bounds().right() <= px(360.),
                "Action must fit in the narrow window"
            );
        }
        window.scroll(
            "action-0",
            ScrollDelta::Pixels(point(px(0.), px(-1600.))),
            cx,
        );
        assert!(
            window.find("footer").bounds().bottom() <= px(320.),
            "Footer must be reachable by scrolling the screen"
        );
    })
    .unwrap();
    cx.simulate_window_resize(handle.into(), size(px(960.), px(720.)));
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert_eq!(
            view.read(cx).scroll.offset().y,
            px(0.),
            "Growing the viewport must remove obsolete scroll offset"
        );
    })
    .unwrap();
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
                cx.new(|cx| DartView::new(initial(100), Events(Arc::new(|_| {})), window, cx))
            },
        )
        .unwrap()
    });
    let mut samples = Vec::new();
    for (i, row_count) in [100, 10_000, 100_000].into_iter().enumerate() {
        cx.update_window(handle, |_, window, cx| {
            view.update(cx, |view, cx| {
                view.update_dataset(Update {request:1, id:"records".into(), base_revision: i as u64 + 1, revision: i as u64 + 2, change: Change::Replace { data: table_data(row_count) }}, 0, cx);
                view.publish(description(i as u64 + 2), window, cx);
            });
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
fn preparation_ack_waits_for_rendered_scroll(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let captured = Arc::new(Mutex::new(Vec::new()));
    let events = Events(Arc::new({
        let captured = captured.clone();
        move |event| {
            if let Event::Diagnostic { request, data } = event {
                captured.lock().unwrap().push((request, data));
            }
        }
    }));
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| DartView::new(initial(125), events.clone(), window, cx))
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let before = view.read(cx).inspect(window, cx);
        crate::diagnostics::handle(
            crate::diagnostics::Request::Prepare {
                request: 7,
                input: "name".into(),
                text: "ALP".into(),
                start: 0,
                end: 3,
                table: "table".into(),
                row: 25,
            },
            &view,
            &events,
            window,
            cx,
        );
        assert!(captured.lock().unwrap().is_empty());
        window.simulate_next_frame(cx);
        assert!(
            captured.lock().unwrap().is_empty(),
            "A frame callback before drawing must not acknowledge an unapplied scroll"
        );
        // A replacement can be applied while the deferred scroll is still pending.
        view.update(cx, |view, cx| view.publish(description(2), window, cx));
        window.render_frame(cx);
        window.simulate_next_frame(cx);
        let replies = captured.lock().unwrap();
        assert_eq!(replies.len(), 1);
        assert_eq!(replies[0].0, 7);
        let after = &replies[0].1;
        assert_eq!(after["revision"], 2);
        assert_eq!(
            after["tables"]["table"]["entity"],
            before["tables"]["table"]["entity"]
        );
        assert_eq!(after["tables"]["table"]["visible_rows"]["start"], 25);
        assert!(after["tables"]["table"]["scroll_y"].as_f64().unwrap() < 0.);
        assert_eq!(after["inputs"]["name"]["text"], "ALP");
        assert_eq!(
            after["inputs"]["name"]["selection"],
            serde_json::json!({"start":0,"end":3})
        );
        assert_eq!(after["inputs"]["name"]["focused"], true);
    })
    .unwrap();
}

#[gpui::test]
fn missing_retained_state_returns_an_error(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| DartView::new(initial(1), Events(Arc::new(|_| {})), window, cx))
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        view.update(cx, |view, cx| {
            assert!(
                view.materialize(
                    &Node::Input {
                        id: "missing-input".into(),
                        style: None,
                        placeholder: String::new(),
                    },
                    &cx.theme().colors.clone(),
                )
                .err()
                .unwrap()
                .contains("missing-input")
            );
            assert!(
                view.materialize(
                    &Node::Table {
                        id: "missing-table".into(),
                        style: None,
                        dataset: "records".into(),
                    },
                    &cx.theme().colors.clone(),
                )
                .err()
                .unwrap()
                .contains("missing-table")
            );
            view.datasets.entries.remove("records");
            assert!(view.reconcile(window, cx).unwrap_err().contains("records"));
        });
    })
    .unwrap();
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
            |window, cx| cx.new(|cx| DartView::new(initial(10_000), sink, window, cx)),
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
        view.update(cx, |view, cx| {
            view.update_dataset(
                Update {
                    request: 1,
                    id: "records".into(),
                    base_revision: 1,
                    revision: 2,
                    change: Change::Edit {
                        edits: vec![crate::datasets::Edit::Cell {
                            row: 4,
                            column: 1,
                            value: "edited".into(),
                        }],
                    },
                },
                0,
                cx,
            )
        });
        window.render_frame(cx);
        assert_eq!(view.read(cx).cell("records", 4, 1)["value"], "edited");
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
                        style: None,
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
        events.iter().any(|event| matches!(event,
            Event::TableSelection { id, dataset, dataset_revision: 2, row: Some(_), .. }
            if id == "table" && dataset == "records"
        )),
        "Pointer/keyboard row selection must reach Dart with its dataset revision"
    );
    assert!(
        events.iter().any(
            |event| matches!(event, Event::Click { revision: 1, id, .. } if id == "increment")
        )
    );
    assert!(
        events
            .iter()
            .any(|event| matches!(event, Event::Input { value, .. } if value == "Dart 🦀"))
    );
}

#[gpui::test]
fn styled_nodes_render_without_error(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| DartView::new(initial(1), Events(Arc::new(|_| {})), window, cx))
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let snapshot = Snapshot::parse(
            br##"{"revision":2,"root":{"kind":"column","id":"root",
                "style":{"padding":[8,8,8,8],"gap":4,"background":"token:muted","border_color":"#33415580","border_radius":6},
                "children":[
                    {"kind":"text","id":"heading","text":"Styled","style":{"font_size":20,"font_weight":"bold","foreground":"token:primary"}},
                    {"kind":"button","id":"cta","label":"Go","style":{"width":{"px":120}}},
                    {"kind":"row","id":"actions","style":{"justify":"space_between","align":"center"},"children":[]},
                    {"kind":"input","id":"name","placeholder":"Name","style":{"width":"full"}},
                    {"kind":"table","id":"table","dataset":"records","style":{"height":{"px":200}}}
                ]}}"##,
        )
        .unwrap();
        view.update(cx, |view, cx| view.publish(snapshot, window, cx));
        window.render_frame(cx);
        let view = view.read(cx);
        assert!(view.failure.is_none());
        assert_eq!(view.snapshot.revision, 2);
        assert_eq!(window.find("cta").bounds().size.width, px(120.));
        assert_eq!(window.find("table").bounds().size.height, px(200.));
    })
    .unwrap();
}
