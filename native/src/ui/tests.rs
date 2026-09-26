use super::DartView;
use crate::{
    Events,
    datasets::{Change, Initial, Update, Upload},
    protocol::{
        Event, FilterOp, FilterTerm, Node, Snapshot, SortDirection, SortKey, TableData, TableView,
    },
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
        actions: Vec::new(),
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
                    view: None,
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
        ids: None,
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
                        view: None,
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
        let table_before = view.read(cx).tables["table"].state.entity_id();
        let range = view.read(cx).tables["table"]
            .state
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
        assert_eq!(
            view.read(cx).tables["table"].state.entity_id(),
            table_before
        );
        assert_eq!(window.find("name").value(), Some("Dart 🦀"));
        assert_eq!(window.find("name").focused(), Some(true));
        assert_eq!(
            view.read(cx).inputs["name"].state.read(cx).selected_range(),
            5..9
        );

        window.scroll("table", ScrollDelta::Pixels(point(px(0.), px(-640.))), cx);
        let scrolled = view.read(cx).tables["table"]
            .state
            .read(cx)
            .visible_range()
            .rows()
            .clone();
        assert!(
            scrolled.start > range.start,
            "Wheel input must move the visible rows"
        );
        window.click("table", cx);
        let selected = view.read(cx).tables["table"].state.read(cx).selected_row();
        window.press("down", cx);
        let next = view.read(cx).tables["table"].state.read(cx).selected_row();
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
                .state
                .read(cx)
                .visible_range()
                .rows()
                .is_empty()
        );
        view.update(cx, |view, cx| {
            view.publish(
                Snapshot {
                    revision: 3,
                    actions: Vec::new(),
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

#[gpui::test]
fn scoped_actions_dispatch_by_focus_and_unmatched_keys_type(cx: &mut TestAppContext) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let sink = Events(Arc::new(move |event| collected.lock().unwrap().push(event)));
    cx.update(gpui_kit::init);
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| DartView::new(initial(1), sink, window, cx))
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let snapshot = Snapshot::parse(
            br#"{"revision":2,"actions":[
                {"name":"app.search","keys":"ctrl+f","context":"global"},
                {"name":"input.search","keys":"ctrl+f","context":"form"},
                {"name":"watchlist.add","keys":"ctrl+enter","context":"name"}
            ],"root":{"kind":"column","id":"root","children":[
                {"kind":"column","id":"form","children":[
                    {"kind":"input","id":"name","placeholder":"Name"}
                ]}
            ]}}"#,
        )
        .unwrap();
        view.update(cx, |view, cx| view.publish(snapshot, window, cx));
        window.render_frame(cx);

        // Nothing focused: node-context bindings do not fire, global ones do.
        window.press("ctrl-enter", cx);
        window.press("ctrl-f", cx);
        {
            let events = events.lock().unwrap();
            let actions: Vec<_> = events
                .iter()
                .filter_map(|event| match event {
                    Event::Action { name, context, .. } => Some((name.as_str(), context.as_str())),
                    _ => None,
                })
                .collect();
            assert_eq!(actions, [("app.search", "global")]);
        }

        // Focus the input: the innermost matching context wins over global.
        window.click("name", cx);
        window.press("ctrl-f", cx);
        window.press("ctrl-enter", cx);
        {
            let events = events.lock().unwrap();
            let actions: Vec<_> = events
                .iter()
                .filter_map(|event| match event {
                    Event::Action {
                        name,
                        context,
                        revision,
                    } => Some((name.as_str(), context.as_str(), *revision)),
                    _ => None,
                })
                .collect();
            assert_eq!(
                actions,
                [
                    ("app.search", "global", 2),
                    ("input.search", "form", 2),
                    ("watchlist.add", "name", 2),
                ]
            );
        }

        // An unmatched printable key still reaches the input as text.
        window.press("a", cx);
        assert_eq!(window.find("name").value(), Some("a"));
        let count = events.lock().unwrap().len();
        window.press("ctrl-x", cx);
        assert_eq!(
            events.lock().unwrap().len(),
            count,
            "unbound keys do not emit action events"
        );
        assert_eq!(window.find("name").value(), Some("a"));
    })
    .unwrap();
}

fn initial_with_ids() -> Initial {
    let table = |view: Option<TableView>| Snapshot {
        revision: 1,
        actions: Vec::new(),
        root: Node::Table {
            id: "table".into(),
            style: None,
            dataset: "records".into(),
            view,
        },
    };
    Initial {
        window: Default::default(),
        snapshot: table(Some(TableView {
            sort: vec![SortKey {
                column: 1,
                direction: SortDirection::Desc,
            }],
            filter: vec![],
        })),
        datasets: vec![Upload {
            id: "records".into(),
            revision: 1,
            data: TableData {
                columns: vec!["sym".into(), "price".into()],
                // R000 has price 100, R099 has price 1: descending sort is the
                // identity order, ascending reverses it.
                rows: (0..100)
                    .map(|i| vec![format!("R{i:03}"), format!("{}", 100 - i)])
                    .collect(),
                ids: Some((0..100).map(|i| format!("R{i:03}")).collect()),
            },
        }],
    }
}

fn publish_table_view(
    view: &gpui_kit::Entity<DartView>,
    revision: u64,
    table_view: TableView,
    window: &mut gpui_kit::Window,
    cx: &mut gpui_kit::App,
) {
    view.update(cx, |view, cx| {
        view.publish(
            Snapshot {
                revision,
                actions: Vec::new(),
                root: Node::Table {
                    id: "table".into(),
                    style: None,
                    dataset: "records".into(),
                    view: Some(table_view),
                },
            },
            window,
            cx,
        )
    });
}

fn edit_cell(
    view: &gpui_kit::Entity<DartView>,
    base_revision: u64,
    row: usize,
    column: usize,
    value: &str,
    cx: &mut gpui_kit::App,
) {
    view.update(cx, |view, cx| {
        view.update_dataset(
            Update {
                request: 1,
                id: "records".into(),
                base_revision,
                revision: base_revision + 1,
                change: Change::Edit {
                    edits: vec![crate::datasets::Edit::Cell {
                        row,
                        column,
                        value: value.into(),
                    }],
                },
            },
            0,
            cx,
        )
    });
}

#[gpui::test]
fn views_sort_select_anchor_and_recompute(cx: &mut TestAppContext) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let sink = Events(Arc::new(move |event| collected.lock().unwrap().push(event)));
    cx.update(gpui_kit::init);
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| DartView::new(initial_with_ids(), sink, window, cx))
        })
        .unwrap()
    });

    // (a) Sort order drives the delegate index. Descending price is identity.
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let index = view.read(cx).tables["table"]
            .state
            .read(cx)
            .delegate()
            .index
            .borrow()
            .clone();
        assert_eq!(index.len(), 100);
        assert_eq!(index[0], 0, "descending price keeps source order");
        let inspect = view.read(cx).inspect(window, cx);
        assert_eq!(inspect["tables"]["table"]["view"]["view_rows"], 100);
        assert_eq!(inspect["tables"]["table"]["view"]["source_rows"], 100);
        assert!(inspect["tables"]["table"]["view"]["spec_hash"].is_u64());
    })
    .unwrap();

    // Select a row (descending price is identity order, so view row i is
    // record R00i). Effects flush between blocks.
    let mut selected = String::new();
    let mut selected_row = usize::MAX;
    cx.update_window(handle, |_, window, cx| {
        window.click("table", cx);
        window.press("down", cx);
    })
    .unwrap();
    cx.update_window(handle, |_, window, cx| {
        let inspect = view.read(cx).inspect(window, cx);
        selected = inspect["tables"]["table"]["selection"]["record"]
            .as_str()
            .expect("a record must be selected")
            .to_owned();
        selected_row = inspect["tables"]["table"]["selection"]["row"]
            .as_u64()
            .unwrap() as usize;
        assert!(selected_row < 10, "test setup selects a row in R000..R009");
    })
    .unwrap();

    // (b) Reversing the sort keeps the same record selected at its new row.
    cx.update_window(handle, |_, window, cx| {
        publish_table_view(
            &view,
            2,
            TableView {
                sort: vec![SortKey {
                    column: 1,
                    direction: SortDirection::Asc,
                }],
                filter: vec![],
            },
            window,
            cx,
        );
        window.render_frame(cx);
        let inspect = view.read(cx).inspect(window, cx);
        assert_eq!(
            inspect["tables"]["table"]["selection"]["record"],
            selected.as_str()
        );
        assert_eq!(
            inspect["tables"]["table"]["selection"]["row"],
            99 - selected_row
        );
        let index = view.read(cx).tables["table"]
            .state
            .read(cx)
            .delegate()
            .index
            .borrow()
            .clone();
        assert_eq!(index[0], 99, "ascending price reverses the order");
    })
    .unwrap();

    // Filtering to R000..R009 keeps the selection; the record moves rows.
    cx.update_window(handle, |_, window, cx| {
        publish_table_view(
            &view,
            3,
            TableView {
                sort: vec![SortKey {
                    column: 1,
                    direction: SortDirection::Asc,
                }],
                filter: vec![FilterTerm {
                    column: 0,
                    op: FilterOp::Contains,
                    value: "R00".into(),
                }],
            },
            window,
            cx,
        );
        window.render_frame(cx);
        let inspect = view.read(cx).inspect(window, cx);
        assert_eq!(inspect["tables"]["table"]["view"]["view_rows"], 10);
        assert_eq!(
            inspect["tables"]["table"]["selection"]["record"],
            selected.as_str()
        );
        assert_eq!(
            inspect["tables"]["table"]["selection"]["row"],
            9 - selected_row
        );
    })
    .unwrap();

    // (c) Filtering out the selected record clears it with a null event.
    cx.update_window(handle, |_, window, cx| {
        publish_table_view(
            &view,
            4,
            TableView {
                sort: vec![],
                filter: vec![FilterTerm {
                    column: 0,
                    op: FilterOp::Contains,
                    value: "R01".into(),
                }],
            },
            window,
            cx,
        );
        window.render_frame(cx);
    })
    .unwrap();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let inspect = view.read(cx).inspect(window, cx);
        assert_eq!(
            inspect["tables"]["table"]["selection"]["record"],
            serde_json::Value::Null
        );
        assert_eq!(
            inspect["tables"]["table"]["selection"]["row"],
            serde_json::Value::Null
        );
        let events = events.lock().unwrap();
        assert!(
            events.iter().any(|event| matches!(
                event,
                Event::TableSelection {
                    row: None,
                    record: None,
                    ..
                }
            )),
            "the disappearance rule must emit a null selection event"
        );
        assert!(
            events.iter().any(|event| matches!(
                event,
                Event::TableSelection { record: Some(record), .. } if record == &selected
            )),
            "selection events carry the record ID"
        );
    })
    .unwrap();

    // (d) Scroll anchor: restore the full descending view and scroll to row 25.
    cx.update_window(handle, |_, window, cx| {
        publish_table_view(
            &view,
            5,
            TableView {
                sort: vec![SortKey {
                    column: 1,
                    direction: SortDirection::Desc,
                }],
                filter: vec![],
            },
            window,
            cx,
        );
        let table = view.read(cx).tables["table"].state.clone();
        table.update(cx, |table, cx| table.scroll_to_row(25, cx));
        window.render_frame(cx);
        let inspect = view.read(cx).inspect(window, cx);
        assert_eq!(inspect["tables"]["table"]["visible_rows"]["start"], 25);
    })
    .unwrap();

    // Anchor R025 survives a view change that keeps it: the scroll follows
    // the record (ascending order moves R025 to view row 74), instead of
    // keeping the raw pixel offset.
    cx.update_window(handle, |_, window, cx| {
        publish_table_view(
            &view,
            6,
            TableView {
                sort: vec![SortKey {
                    column: 1,
                    direction: SortDirection::Asc,
                }],
                filter: vec![FilterTerm {
                    column: 0,
                    op: FilterOp::Contains,
                    value: "R0".into(),
                }],
            },
            window,
            cx,
        );
        window.render_frame(cx);
        let inspect = view.read(cx).inspect(window, cx);
        assert_eq!(inspect["tables"]["table"]["view"]["view_rows"], 100);
        assert_eq!(
            inspect["tables"]["table"]["visible_rows"]["start"], 74,
            "anchor record R025 stays at the top of the viewport"
        );
    })
    .unwrap();

    // A filter that removes the anchor resets the scroll to the top.
    cx.update_window(handle, |_, window, cx| {
        publish_table_view(
            &view,
            7,
            TableView {
                sort: vec![],
                filter: vec![FilterTerm {
                    column: 0,
                    op: FilterOp::Contains,
                    value: "R03".into(),
                }],
            },
            window,
            cx,
        );
        window.render_frame(cx);
        let inspect = view.read(cx).inspect(window, cx);
        assert_eq!(inspect["tables"]["table"]["visible_rows"]["start"], 0);
        assert_eq!(inspect["tables"]["table"]["scroll_y"], 0.0);
    })
    .unwrap();

    // (e) Only edits to view-referenced columns recompute the index.
    cx.update_window(handle, |_, window, cx| {
        publish_table_view(
            &view,
            8,
            TableView {
                sort: vec![SortKey {
                    column: 1,
                    direction: SortDirection::Desc,
                }],
                filter: vec![],
            },
            window,
            cx,
        );
        window.render_frame(cx);
        let baseline = view.read(cx).counters.view_recomputes.get();
        edit_cell(&view, 1, 0, 0, "RENAMED", cx);
        window.render_frame(cx);
        assert_eq!(
            view.read(cx).counters.view_recomputes.get(),
            baseline,
            "an edit to an unreferenced column must not recompute the view"
        );
        edit_cell(&view, 2, 0, 1, "0", cx);
        window.render_frame(cx);
        assert_eq!(
            view.read(cx).counters.view_recomputes.get(),
            baseline + 1,
            "an edit to the sort column recomputes the view"
        );
        let index = view.read(cx).tables["table"]
            .state
            .read(cx)
            .delegate()
            .index
            .borrow()
            .clone();
        assert_eq!(index[0], 1, "R000 sank to the bottom after its price edit");
        assert_eq!(index[99], 0);
    })
    .unwrap();
}
