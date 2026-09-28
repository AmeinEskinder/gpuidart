use super::DartView;
use crate::{
    Events,
    datasets::{Change, Initial, Update, Upload},
    protocol::{
        CellIcon, Color, ColumnFormat, DatasetFormat, Event, FilterOp, FilterTerm, FormatCondition,
        FormatRule, Node, NumberFormat, Snapshot, SortDirection, SortKey, TableData, TableView,
        ThemeToken, ViewEntry,
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
        theme: None,
        menus: Vec::new(),
        actions: Vec::new(),
        root: Node::Column {
            id: "root".into(),
            semantics: None,
            style: None,
            children: vec![
                Node::Text {
                    id: "label".into(),
                    semantics: None,
                    style: None,
                    text: format!("Revision {revision}"),
                },
                Node::Button {
                    tooltip: None,
                    id: "increment".into(),
                    semantics: None,
                    style: None,
                    label: "Increment".into(),
                },
                Node::Input {
                    id: "name".into(),
                    semantics: None,
                    style: None,
                    placeholder: "Name".into(),
                    controlled: false,
                },
                Node::Table {
                    id: "table".into(),
                    context_menu: Vec::new(),
                    semantics: None,
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
        format: None,
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
fn checkbox_pointer_keyboard_disabled_and_focus_retention(cx: &mut TestAppContext) {
    let press = |window: &mut gpui_kit::Window, key: &str, cx: &mut gpui_kit::App| {
        window.press(key, cx);
        window.dispatch_event(
            gpui_kit::PlatformInput::KeyUp(gpui_kit::KeyUpEvent {
                keystroke: gpui_kit::Keystroke::parse(key).unwrap(),
            }),
            cx,
        );
        window.render_frame(cx);
    };
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let snapshot = |revision, checked, disabled| {
        Snapshot::parse(
            &serde_json::to_vec(&serde_json::json!({
                "revision": revision,
                "root": {"kind":"column", "id":"root", "children":[
                    {"kind":"checkbox", "id":"notifications", "label":"Notifications",
                     "checked":checked, "disabled":disabled,
                     "style":{"width":{"px":240},"foreground":"token:primary"}},
                    {"kind":"checkbox", "id":"other", "label":"Other", "checked":false}
                ]}
            }))
            .unwrap(),
        )
        .unwrap()
    };
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: snapshot(1, false, false),
                        datasets: vec![],
                    },
                    Events(Arc::new(move |event| collected.lock().unwrap().push(event))),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    let changes = || {
        events
            .lock()
            .unwrap()
            .iter()
            .filter_map(|event| match event {
                Event::CheckboxChange {
                    revision,
                    id,
                    checked,
                } => Some((*revision, id.clone(), *checked)),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert_eq!(window.find("notifications").bounds().size.width, px(240.));
        window.click("notifications", cx);
        assert_eq!(changes(), [(1, "notifications".into(), true)]);
        let shown = view.read(cx).inspect(window, cx)["controls"]["notifications"].clone();
        assert_eq!(
            (shown["checked"].clone(), shown["published"].clone()),
            (serde_json::json!(true), serde_json::json!(false)),
            "the toggle shows before the application publishes"
        );
        window.focus_next(cx);
        let focus = window.focused(cx).expect("checkbox is a tab stop");
        press(window, "space", cx);
        assert_eq!(changes().len(), 2, "one event per activation");
        assert_eq!(
            changes()[1],
            (1, "notifications".into(), false),
            "a second activation toggles the shown value back"
        );
        view.update(cx, |view, cx| {
            view.publish(snapshot(2, true, false), window, cx)
        });
        window.render_frame(cx);
        assert_eq!(window.focused(cx), Some(focus));
        press(window, "space", cx);
        assert_eq!(changes()[2], (2, "notifications".into(), false));
        view.update(cx, |view, cx| {
            view.publish(snapshot(3, true, true), window, cx)
        });
        window.render_frame(cx);
        window.click("notifications", cx);
        press(window, "space", cx);
        assert_eq!(
            changes().len(),
            3,
            "disabled pointer and keyboard are inert"
        );
        window.focus_next(cx);
        press(window, "space", cx);
        assert_eq!(changes()[3], (3, "other".into(), true));
    })
    .unwrap();
}

#[gpui::test]
fn updates_apply_operations_atomically_and_retain_native_entities(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    initial(10),
                    Events(Arc::new(move |event| collected.lock().unwrap().push(event))),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    let update = |json: serde_json::Value| {
        crate::protocol::Update::parse(&serde_json::to_vec(&json).unwrap()).unwrap()
    };
    let outcomes = || {
        events
            .lock()
            .unwrap()
            .iter()
            .filter_map(|event| match event {
                Event::Applied { revision, .. } => Some((*revision, None)),
                Event::Rejected { revision, message } => Some((*revision, Some(message.clone()))),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let before = view.read(cx).inspect(window, cx);
        let input_entity = before["inputs"]["name"]["entity"].clone();
        let table_entity = before["tables"]["table"]["entity"].clone();
        view.update(cx, |view, cx| {
            view.apply_update(
                update(serde_json::json!({
                    "revision": 2, "base_revision": 1,
                    "ops": [
                        {"op":"set","id":"label","node":{"kind":"text","id":"label","text":"Updated"}},
                        {"op":"insert","parent":"root","node":{"kind":"text","id":"extra","text":"Extra"}},
                        {"op":"children","id":"root","children":["extra","label","increment","name","table"]}
                    ]
                })),
                window,
                cx,
            )
        });
        window.render_frame(cx);
        let after = view.read(cx).inspect(window, cx);
        assert_eq!(after["revision"], 2);
        assert_eq!(after["labels"]["label"], "Updated");
        assert_eq!(after["labels"]["extra"], "Extra");
        assert_eq!(after["inputs"]["name"]["entity"], input_entity);
        assert_eq!(after["tables"]["table"]["entity"], table_entity);
        assert_eq!(outcomes(), [(2, None)]);

        view.update(cx, |view, cx| {
            view.apply_update(
                update(serde_json::json!({"revision":3,"base_revision":1,"ops":[]})),
                window,
                cx,
            )
        });
        view.update(cx, |view, cx| {
            view.apply_update(
                update(serde_json::json!({"revision":3,"base_revision":2,"ops":[
                    {"op":"set","id":"label","node":{"kind":"text","id":"label","text":"Never"}},
                    {"op":"remove","id":"missing"}
                ]})),
                window,
                cx,
            )
        });
        view.update(cx, |view, cx| {
            view.apply_update(
                update(serde_json::json!({"revision":3,"base_revision":2,"ops":[
                    {"op":"insert","parent":"root","node":{"kind":"table","id":"orphan","dataset":"missing"}}
                ]})),
                window,
                cx,
            )
        });
        window.render_frame(cx);
        let unchanged = view.read(cx).inspect(window, cx);
        assert_eq!(unchanged["revision"], 2);
        assert_eq!(unchanged["labels"]["label"], "Updated");
        let rejected = outcomes();
        assert_eq!(rejected.len(), 4);
        assert!(rejected[1].1.as_deref().unwrap().contains("Stale base revision"));
        assert!(rejected[2].1.as_deref().unwrap().contains("Remove target"));
        assert!(rejected[3].1.as_deref().unwrap().contains("Unknown dataset"));

        view.update(cx, |view, cx| {
            view.apply_update(
                update(serde_json::json!({"revision":3,"base_revision":2,"ops":[
                    {"op":"insert","parent":"root","node":{"kind":"row","id":"row","children":[]}},
                    {"op":"reparent","id":"name","parent":"row"},
                    {"op":"remove","id":"extra"}
                ]})),
                window,
                cx,
            )
        });
        window.render_frame(cx);
        let moved = view.read(cx).inspect(window, cx);
        assert_eq!(moved["revision"], 3);
        assert_eq!(moved["inputs"]["name"]["entity"], input_entity);
        assert!(moved["labels"].get("extra").is_none());
        assert_eq!(outcomes().len(), 5);
        assert_eq!(outcomes()[4], (3, None));
    })
    .unwrap();
}

#[gpui::test]
fn layout_primitives_size_position_and_retain_scroll_offsets(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let snapshot = |revision: u64, label: &str| {
        Snapshot::parse(
            format!(
                r#"{{"revision":{revision},"root":{{"kind":"column","id":"root","style":{{"gap":0}},"children":[
                {{"kind":"row","id":"bar","style":{{"gap":0,"width":{{"px":600}}}},"children":[
                    {{"kind":"text","id":"fixed","text":"Fixed","style":{{"width":{{"px":100}}}}}},
                    {{"kind":"text","id":"grow","text":"Grow","style":{{"flex":1}}}},
                    {{"kind":"text","id":"grow2","text":"Grow2","style":{{"flex":2}}}}
                ]}},
                {{"kind":"stack","id":"stack","style":{{"width":{{"px":300}},"height":{{"px":200}}}},"children":[
                    {{"kind":"text","id":"under","text":"{label}"}},
                    {{"kind":"text","id":"badge","text":"Badge","style":{{"inset":{{"top":10,"left":20}},"width":{{"px":40}},"height":{{"px":16}}}}}}
                ]}},
                {{"kind":"scroll","id":"list","style":{{"height":{{"px":120}}}},"children":[
                    {{"kind":"text","id":"l0","text":"0","style":{{"height":{{"px":100}}}}}},
                    {{"kind":"text","id":"l1","text":"1","style":{{"height":{{"px":100}}}}}},
                    {{"kind":"text","id":"l2","text":"2","style":{{"height":{{"px":100}}}}}}
                ]}}
            ]}}}}"#
            )
            .as_bytes(),
        )
        .unwrap()
    };
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(Bounds {
                    origin: Point::default(),
                    size: size(px(900.), px(700.)),
                })),
                ..Default::default()
            },
            cx,
            |window, cx| {
                cx.new(|cx| {
                    DartView::new(
                        Initial {
                            window: Default::default(),
                            snapshot: snapshot(1, "Under"),
                            datasets: vec![],
                        },
                        Events(Arc::new(|_| {})),
                        window,
                        cx,
                    )
                })
            },
        )
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let fixed = window.find("fixed").bounds();
        let grow = window.find("grow").bounds();
        let grow2 = window.find("grow2").bounds();
        assert_eq!(fixed.size.width, px(100.));
        let remaining = px(500.);
        assert!(
            (grow.size.width - remaining / 3.).abs() < px(1.),
            "{grow:?}"
        );
        assert!(
            (grow2.size.width - remaining * 2. / 3.).abs() < px(1.),
            "{grow2:?}"
        );
        let stack = window.find("stack").bounds();
        let under = window.find("under").bounds();
        let badge = window.find("badge").bounds();
        assert_eq!(stack.size, size(px(300.), px(200.)));
        assert_eq!(
            under.origin, stack.origin,
            "a child without inset sits at the stack's top left"
        );
        assert_eq!(under.size.width, px(300.));
        assert!(under.size.height < px(200.), "and keeps its own height");
        assert_eq!(badge.origin, stack.origin + point(px(20.), px(10.)));
        assert_eq!(badge.size, size(px(40.), px(16.)));

        window.scroll("list", ScrollDelta::Pixels(point(px(0.), px(-150.))), cx);
        window.render_frame(cx);
        let before = view.read(cx).inspect(window, cx);
        let offset = before["scrolls"]["list"]["y"].as_f64().unwrap();
        assert!(offset < 0., "the scroll container moved: {before}");
        view.update(cx, |view, cx| {
            view.publish(snapshot(2, "Changed"), window, cx)
        });
        window.render_frame(cx);
        let after = view.read(cx).inspect(window, cx);
        assert_eq!(after["labels"]["under"], "Changed");
        assert_eq!(after["scrolls"]["list"]["y"].as_f64().unwrap(), offset);
        view.update(cx, |view, cx| {
            view.publish(
                Snapshot::parse(
                    br#"{"revision":3,"root":{"kind":"text","id":"root","text":"Gone"}}"#,
                )
                .unwrap(),
                window,
                cx,
            )
        });
        window.render_frame(cx);
        assert!(
            view.read(cx).scrolls.is_empty(),
            "removed scroll containers drop their handle"
        );
    })
    .unwrap();
}

#[gpui::test]
fn switches_show_the_toggle_before_publication(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let snapshot = |revision: u64, wifi: bool| {
        Snapshot::parse(
            format!(
                r#"{{"revision":{revision},"root":{{"kind":"column","id":"root","children":[
                {{"kind":"switch","id":"wifi","label":"Wi-Fi","checked":{wifi}}},
                {{"kind":"progress","id":"upload","value":40}},
                {{"kind":"separator","id":"rule","label":"Advanced"}},
                {{"kind":"button","id":"save","label":"Save","tooltip":"Saves the draft"}}
            ]}}}}"#
            )
            .as_bytes(),
        )
        .unwrap()
    };
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: snapshot(1, false),
                        datasets: vec![],
                    },
                    Events(Arc::new(move |event| collected.lock().unwrap().push(event))),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    let changes = || {
        events
            .lock()
            .unwrap()
            .iter()
            .filter_map(|event| match event {
                Event::SwitchChange { id, checked, .. } => Some((id.clone(), checked.to_string())),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert!(window.find("upload").bounds().size.width > px(0.));
        assert!(window.find("rule").bounds().size.width > px(0.));
        window.click("wifi", cx);
        window.render_frame(cx);
        assert_eq!(changes(), [("wifi".to_string(), "true".to_string())]);
        let controls = view.read(cx).inspect(window, cx)["controls"].clone();
        assert_eq!(controls["wifi"]["checked"], true);
        assert_eq!(controls["wifi"]["published"], false);
        assert_eq!(controls["upload"]["value"], 40.0);
        view.update(cx, |view, cx| view.publish(snapshot(2, true), window, cx));
        window.render_frame(cx);
        let controls = view.read(cx).inspect(window, cx)["controls"].clone();
        assert_eq!(controls["wifi"]["published"], true);
        view.update(cx, |view, cx| view.publish(snapshot(3, false), window, cx));
        window.render_frame(cx);
        let controls = view.read(cx).inspect(window, cx)["controls"].clone();
        assert_eq!(
            controls["wifi"]["checked"], false,
            "a publication is authoritative"
        );
    })
    .unwrap();
}

#[gpui::test]
fn canvases_and_animations_render(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let snapshot = |revision: u64| {
        Snapshot::parse(
            format!(
                r##"{{"revision":{revision},"root":{{"kind":"column","id":"root","children":[
                {{"kind":"canvas","id":"chart","style":{{"width":{{"px":200}},"height":{{"px":100}}}},"commands":[
                    {{"op":"rect","x":0,"y":0,"width":50,"height":20,"fill":"token:primary"}},
                    {{"op":"circle","cx":80,"cy":50,"radius":10,"stroke":"#ff0000"}},
                    {{"op":"polyline","points":[[0,100],[50,20],[100,80]],"stroke":"token:danger","fill":"token:muted","close":true}}
                ]}},
                {{"kind":"text","id":"slide","text":"Sliding","style":{{"animation":{{"duration_ms":150,"easing":"linear","offset":[[0,0],[100,0]],"opacity":[1,0.5]}}}}}}
            ]}}}}"##
            )
            .as_bytes(),
        )
        .unwrap()
    };
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: snapshot(1),
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
        assert_eq!(window.find("chart").bounds().size, size(px(200.), px(100.)));
        let start = window.find("slide").bounds().origin.x;
        std::thread::sleep(std::time::Duration::from_millis(80));
        window.render_frame(cx);
        let moved = window.find("slide").bounds().origin.x;
        assert!(
            moved > start,
            "the offset animation advanced: {start:?} -> {moved:?}"
        );
        view.update(cx, |view, cx| view.publish(snapshot(2), window, cx));
        window.render_frame(cx);
        assert_eq!(window.find("chart").bounds().size, size(px(200.), px(100.)));
    })
    .unwrap();
}

#[gpui::test]
fn grouped_tables_show_summary_rows_that_are_not_selectable(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let snapshot = Snapshot::parse(
        br#"{"revision":1,"root":{"kind":"table","id":"table","dataset":"sales","view":{
            "group":{"column":0,"aggregates":[{"column":1,"op":"sum"}]}}}}"#,
    )
    .unwrap();
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot,
                        datasets: vec![Upload {
                            id: "sales".into(),
                            revision: 1,
                            data: TableData {
                                columns: vec!["region".into(), "amount".into()],
                                rows: vec![
                                    vec!["east".into(), "10".into()],
                                    vec!["west".into(), "2".into()],
                                    vec!["east".into(), "5".into()],
                                ],
                                ids: Some(vec!["a".into(), "b".into(), "c".into()]),
                                format: Some(DatasetFormat {
                                    columns: [(
                                        1,
                                        ColumnFormat {
                                            number: Some(NumberFormat { decimals: 2 }),
                                            rules: Vec::new(),
                                        },
                                    )]
                                    .into_iter()
                                    .collect(),
                                }),
                            },
                        }],
                    },
                    Events(Arc::new(move |event| collected.lock().unwrap().push(event))),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    let selections = || {
        events
            .lock()
            .unwrap()
            .iter()
            .filter_map(|event| match event {
                Event::TableSelection { row, record, .. } => Some((*row, record.clone())),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let state = view.read(cx).inspect(window, cx);
        assert_eq!(state["tables"]["table"]["view"]["view_rows"], 5);
        assert_eq!(state["tables"]["table"]["view"]["groups"], 2);
        let header = view.read(cx).formatted_cell("table", 0, 0, cx);
        assert_eq!(
            header["error"], "Invalid row",
            "a header row is not a record"
        );
        let first = view.read(cx).formatted_cell("table", 1, 1, cx);
        assert_eq!(first["text"], "10.00");
        view.update(cx, |view, cx| {
            view.select_table_row("table", 0, cx).unwrap()
        });
        window.render_frame(cx);
    })
    .unwrap();
    // Subscriptions deliver after the update that raised them.
    assert!(selections().is_empty(), "selecting a header emits nothing");
    cx.update_window(handle, |_, window, cx| {
        view.update(cx, |view, cx| {
            view.select_table_row("table", 2, cx).unwrap()
        });
        window.render_frame(cx);
    })
    .unwrap();
    assert_eq!(selections(), [(Some(2), Some("c".to_string()))]);
}

#[gpui::test]
fn menu_buttons_render_and_host_requests_reply(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let snapshot = Snapshot::parse(
        br#"{"revision":1,"actions":[{"name":"file.open","keys":"ctrl+o","context":"global"},{"name":"file.save","keys":"ctrl+s","context":"global"}],"root":{"kind":"column","id":"root","children":[
            {"kind":"menu_button","id":"file","label":"File","items":[{"kind":"action","id":"open","label":"Open","action":"file.open"},{"kind":"separator"},{"kind":"action","id":"save","label":"Save","action":"file.save"}]}
        ]}}"#,
    )
    .unwrap();
    let emitter = Events(Arc::new(move |event| collected.lock().unwrap().push(event)));
    let (handle, view) = cx.update(|cx| {
        let emitter = emitter.clone();
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot,
                        datasets: vec![],
                    },
                    emitter,
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    let replies = || {
        events
            .lock()
            .unwrap()
            .iter()
            .filter_map(|event| match event {
                Event::Diagnostic { request, data } => Some((*request, data.clone())),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    let request = |json: serde_json::Value| {
        serde_json::from_value::<crate::diagnostics::Request>(json).unwrap()
    };
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert!(window.find("file").bounds().size.width > px(0.));
        window.click("file-trigger", cx);
        window.render_frame(cx);
        crate::diagnostics::handle(
            request(serde_json::json!({"op":"open_url","request":7,"url":"https://example.com"})),
            &view,
            &emitter,
            window,
            cx,
        );
        crate::diagnostics::handle(
            request(serde_json::json!({"op":"open_url","request":8,"url":"file:///etc/passwd"})),
            &view,
            &emitter,
            window,
            cx,
        );
    })
    .unwrap();
    let replies = replies();
    assert_eq!(replies[0], (7, serde_json::json!({"opened": true})));
    assert_eq!(
        replies[1].1["error"],
        "Only http, https and mailto URLs open"
    );
    // The headless platform leaves reveal_path unimplemented; only its wire
    // shape is checked here.
    assert!(
        serde_json::from_value::<crate::diagnostics::Request>(serde_json::json!({
            "op":"reveal_path","request":9,"path":"."
        }))
        .is_ok()
    );
    assert!(
        serde_json::from_value::<crate::diagnostics::Request>(serde_json::json!({
            "op":"prompt_paths","request":10,"files":true,"multiple":true,"prompt":"Pick"
        }))
        .is_ok()
    );
    assert!(
        serde_json::from_value::<crate::diagnostics::Request>(serde_json::json!({
            "op":"prompt_save_path","request":11,"directory":"C:/","suggested_name":"a.txt"
        }))
        .is_ok()
    );
}

#[gpui::test]
fn startup_paint_marker_requires_content_paint_and_is_emitted_once(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let trace = Arc::new(crate::trace::Trace::default());
    trace.enable(128).unwrap();
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                let mut view = DartView::new(initial(1000), Events(Arc::new(|_| {})), window, cx);
                view.trace = Some(trace.clone());
                let before: serde_json::Value =
                    serde_json::from_slice(&trace.snapshot().unwrap()).unwrap();
                assert!(before["records"].as_array().unwrap().is_empty());
                view
            })
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let state = view.read(cx).inspect(window, cx);
        assert_eq!(state["labels"]["label"], "Revision 1");
        assert!(state["native"]["rows_constructed"].as_u64().unwrap() > 0);
        for _ in 0..3 {
            window.render_frame(cx);
        }
    })
    .unwrap();
    let after: serde_json::Value = serde_json::from_slice(&trace.snapshot().unwrap()).unwrap();
    let records = after["records"].as_array().unwrap();
    let first = records
        .iter()
        .filter(|r| r["name"] == "native.first_content_paint")
        .collect::<Vec<_>>();
    assert_eq!(first.len(), 1);
    let paint = records
        .iter()
        .find(|r| r["name"] == "native.content_paint")
        .unwrap();
    assert!(first[0]["start"].as_i64().unwrap() >= paint["end"].as_i64().unwrap());
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
                        semantics: None,
                        style: None,
                        children: (0..3)
                            .map(|i| Node::Button {
                                tooltip: None,
                                id: format!("action-{i}"),
                                semantics: None,
                                style: None,
                                label: format!("A long action label {i}"),
                            })
                            .collect(),
                    },
                );
                children.push(Node::Button {
                    tooltip: None,
                    id: "footer".into(),
                    semantics: None,
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
                        semantics: None,
                        style: None,
                        placeholder: String::new(),
                        controlled: false,
                    },
                    &cx.theme().colors.clone(),
                    cx,
                )
                .err()
                .unwrap()
                .contains("missing-input")
            );
            assert!(
                view.materialize(
                    &Node::Table {
                        id: "missing-table".into(),
                        context_menu: Vec::new(),
                        semantics: None,
                        style: None,
                        dataset: "records".into(),
                        view: None,
                    },
                    &cx.theme().colors.clone(),
                    cx,
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
                    theme: None,
                    menus: Vec::new(),
                    actions: Vec::new(),
                    root: Node::Text {
                        id: "empty".into(),
                        semantics: None,
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
        theme: None,
        menus: Vec::new(),
        actions: Vec::new(),
        root: Node::Table {
            id: "table".into(),
            context_menu: Vec::new(),
            semantics: None,
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
            group: None,
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
                format: None,
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
                theme: None,
                menus: Vec::new(),
                actions: Vec::new(),
                root: Node::Table {
                    id: "table".into(),
                    context_menu: Vec::new(),
                    semantics: None,
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
        assert_eq!(index.entries.len(), 100);
        assert_eq!(
            index.entries[0],
            ViewEntry::Record(0),
            "descending price keeps source order"
        );
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
                group: None,
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
        assert_eq!(
            index.entries[0],
            ViewEntry::Record(99),
            "ascending price reverses the order"
        );
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
                group: None,
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
                group: None,
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
                group: None,
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
                group: None,
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
                group: None,
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
                group: None,
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
        assert_eq!(
            index.entries[0],
            ViewEntry::Record(1),
            "R000 sank to the bottom after its price edit"
        );
        assert_eq!(index.entries[99], ViewEntry::Record(0));
    })
    .unwrap();
}

fn formatted_table_data(count: usize) -> TableData {
    let mut columns = std::collections::HashMap::new();
    // All three columns carry formats so the cost probe exercises formatting
    // on every constructed cell.
    columns.insert(
        0,
        ColumnFormat {
            number: None,
            rules: vec![FormatRule {
                when: FormatCondition {
                    op: FilterOp::Contains,
                    value: "R0".into(),
                },
                color: None,
                icon: Some(CellIcon::Dot),
            }],
        },
    );
    columns.insert(
        1,
        ColumnFormat {
            number: Some(NumberFormat { decimals: 2 }),
            rules: vec![],
        },
    );
    columns.insert(
        2,
        ColumnFormat {
            number: None,
            rules: vec![
                FormatRule {
                    when: FormatCondition {
                        op: FilterOp::Lt,
                        value: "0".into(),
                    },
                    color: Some(Color::Token(ThemeToken::Danger)),
                    icon: Some(CellIcon::ArrowDown),
                },
                FormatRule {
                    when: FormatCondition {
                        op: FilterOp::Gt,
                        value: "0".into(),
                    },
                    color: Some(Color::Token(ThemeToken::Success)),
                    icon: Some(CellIcon::ArrowUp),
                },
            ],
        },
    );
    TableData {
        columns: vec!["sym".into(), "price".into(), "change".into()],
        rows: (0..count)
            .map(|i| {
                vec![
                    format!("R{i:05}"),
                    format!("{}.{}", i % 50, i % 10),
                    format!("{}", if i % 2 == 0 { i as i64 } else { -(i as i64) }),
                ]
            })
            .collect(),
        ids: None,
        format: Some(DatasetFormat { columns }),
    }
}

#[gpui::test]
fn formatted_cells_render_and_report(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let initial = Initial {
        window: Default::default(),
        snapshot: Snapshot {
            revision: 1,
            theme: None,
            menus: Vec::new(),
            actions: Vec::new(),
            root: Node::Table {
                id: "table".into(),
                context_menu: Vec::new(),
                semantics: None,
                style: None,
                dataset: "records".into(),
                view: None,
            },
        },
        datasets: vec![Upload {
            id: "records".into(),
            revision: 1,
            data: formatted_table_data(20),
        }],
    };
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| DartView::new(initial, Events(Arc::new(|_| {})), window, cx))
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        // Real cell semantics announce formatted text, not raw data. Without
        // record IDs, row identity uses the source index.
        let row_key = serde_json::json!(["table", "records", "source", 1]).to_string();
        let cell_key = serde_json::json!([row_key, "cell", 1]).to_string();
        let cell = window.find(gpui_kit::SharedString::from(cell_key));
        assert_eq!(cell.role(), Some(gpui_kit::Role::Cell));
        assert_eq!(cell.label(), Some("1.10"));
        assert_eq!(
            window.find(gpui_kit::SharedString::from(row_key)).role(),
            Some(gpui_kit::Role::Row)
        );
        // Number column: fixed decimals.
        let cell = view.read(cx).formatted_cell("table", 0, 1, cx);
        assert_eq!(cell["text"], "0.00");
        let cell = view.read(cx).formatted_cell("table", 1, 1, cx);
        assert_eq!(cell["text"], "1.10");
        // Rule column: negative row is danger + arrow_down.
        let cell = view.read(cx).formatted_cell("table", 1, 2, cx);
        assert_eq!(cell["text"], "-1");
        assert_eq!(cell["color"], "token:danger");
        assert_eq!(cell["icon"], "arrow_down");
        let cell = view.read(cx).formatted_cell("table", 2, 2, cx);
        assert_eq!(cell["color"], "token:success");
        assert_eq!(cell["icon"], "arrow_up");
        // Zero matches neither rule.
        let cell = view.read(cx).formatted_cell("table", 0, 2, cx);
        assert_eq!(cell["text"], "0");
        assert!(cell["color"].is_null());
        // The icon-only rule column carries a dot and no color.
        let cell = view.read(cx).formatted_cell("table", 3, 0, cx);
        assert_eq!(cell["text"], "R00003");
        assert_eq!(cell["icon"], "dot");
        assert!(cell["color"].is_null());
        // Rendering a formatted table must not fail the view.
        assert!(view.read(cx).failure.is_none());
    })
    .unwrap();
}

#[gpui::test]
fn formatted_cells_keep_viewport_constant_construction(cx: &mut TestAppContext) {
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
                let mut data = initial(100);
                data.datasets[0].data = formatted_table_data(100);
                cx.new(|cx| DartView::new(data, Events(Arc::new(|_| {})), window, cx))
            },
        )
        .unwrap()
    });
    let mut samples = Vec::new();
    for (i, row_count) in [100, 10_000, 100_000].into_iter().enumerate() {
        cx.update_window(handle, |_, window, cx| {
            view.update(cx, |view, cx| {
                view.update_dataset(Update {request:1, id:"records".into(), base_revision: i as u64 + 1, revision: i as u64 + 2, change: Change::Replace { data: formatted_table_data(row_count) }}, 0, cx);
                view.publish(description(i as u64 + 2), window, cx);
            });
            for _ in 0..5 { window.render_frame(cx); }
            let counters = view.read(cx).counters.clone();
            let rows_before = counters.rows.get();
            let cells_before = counters.cells.get();
            let materializations_before = counters.materializations.get();
            let timer = std::time::Instant::now();
            let (allocations, bytes) = crate::allocations::measure(|| {
                for _ in 0..10 { window.render_frame(cx); }
            });
            let elapsed = timer.elapsed();
            let rows = counters.rows.get() - rows_before;
            let cells = counters.cells.get() - cells_before;
            let materializations = counters.materializations.get() - materializations_before;
            assert_eq!(materializations, 10);
            assert!(rows > 0 && rows < 1000, "constructed {rows} rows for {row_count} records");
            assert!(cells > 0 && cells < 3000);
            samples.push(serde_json::json!({"data_rows":row_count, "frames":10, "rows_constructed":rows, "cells_constructed":cells, "allocation_calls":allocations, "allocated_bytes":bytes, "frame_us": elapsed.as_micros() as u64 / 10, "frame_ns_per_constructed_cell": elapsed.as_nanos() as u64 / cells}));
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
    let report = serde_json::json!({"scope":"headless GPUI UI thread, ten warmed redraws with formats on all columns; excludes data construction, snapshot publication and GPU allocations", "window":{"width":860,"height":650}, "samples": samples});
    println!("FORMATTING {report}");
    if let Ok(path) = std::env::var("GPUIDART_FORMATTING_REPORT") {
        std::fs::write(path, serde_json::to_string_pretty(&report).unwrap()).unwrap();
    }
}

#[gpui::test]
fn theme_switch_resolves_component_tokens_and_preserves_controls(cx: &mut TestAppContext) {
    use crate::protocol::{ThemeMode, ThemeSpec};
    cx.update(gpui_kit::init);
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| DartView::new(initial(1000), Events(Arc::new(|_| {})), window, cx))
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.click("name", cx);
        window.input("Theme draft", cx);
        window.press("shift-left", cx);
        window.scroll("table", ScrollDelta::Pixels(point(px(0.), px(-400.))), cx);
        window.render_frame(cx);
        let before = view.read(cx).inspect(window, cx);
        let light = cx.theme().colors;
        let mut snapshot = description(2);
        snapshot.theme = Some(ThemeSpec {
            mode: ThemeMode::Dark,
            overrides: [("primary".into(), "#2D6AC8".into())].into(),
        });
        view.update(cx, |view, cx| view.publish(snapshot, window, cx));
        window.render_frame(cx);
        let after = view.read(cx).inspect(window, cx);
        assert_eq!(after["inputs"], before["inputs"]);
        for field in ["entity", "scroll_y", "dataset_revision"] {
            assert_eq!(
                after["tables"]["table"][field],
                before["tables"]["table"][field]
            );
        }
        assert_eq!(after["theme"]["resolved"]["primary"], "#2D6AC8");
        assert!(cx.theme().is_dark());
        assert_eq!(cx.theme().tokens.button_primary.color, cx.theme().primary);
        assert_eq!(cx.theme().button_primary, cx.theme().primary);
        assert_eq!(
            gpui_kit::base::Theme::global(cx).tokens.colors.primary,
            cx.theme().primary
        );
        let mut invalid = description(3);
        invalid.theme = Some(ThemeSpec {
            overrides: [("unknown".into(), "#FFFFFF".into())].into(),
            ..Default::default()
        });
        view.update(cx, |view, cx| view.publish(invalid, window, cx));
        assert_eq!(view.read(cx).snapshot.revision, 2);
        assert!(cx.theme().is_dark());
        let mut dark = description(4);
        dark.theme = Some(ThemeSpec {
            mode: ThemeMode::Dark,
            ..Default::default()
        });
        view.update(cx, |view, cx| view.publish(dark, window, cx));
        assert_ne!(
            view.read(cx).inspect(window, cx)["theme"]["resolved"]["primary"],
            "#2D6AC8"
        );
        view.update(cx, |view, cx| view.publish(description(5), window, cx));
        assert!(!cx.theme().is_dark());
        assert_eq!(cx.theme().primary, light.primary);
        assert_eq!(cx.theme().background, light.background);
    })
    .unwrap();
}

#[gpui::test]
fn lists_show_view_ordered_records_report_picks_and_follow_edits(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let list = |revision: u64, selected: Option<&str>| {
        let selected = selected.map_or(String::new(), |s| format!(r#","selected":"{s}""#));
        Snapshot::parse(
            format!(
                r#"{{"revision":{revision},"root":{{"kind":"column","id":"root","children":[
                    {{"kind":"list","id":"names","dataset":"people","column":1,"view":{{"sort":[{{"column":1,"direction":"asc"}}]}}{selected}}}
                ]}}}}"#
            )
            .as_bytes(),
        )
        .unwrap()
    };
    let people = |ids: bool| Upload {
        id: "people".into(),
        revision: 1,
        data: TableData {
            columns: vec!["id".into(), "name".into()],
            rows: vec![
                vec!["1".into(), "Cleo".into()],
                vec!["2".into(), "Ann".into()],
                vec!["3".into(), "Bo".into()],
            ],
            ids: ids.then(|| vec!["p1".into(), "p2".into(), "p3".into()]),
            format: None,
        },
    };
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: list(1, Some("p1")),
                        datasets: vec![people(true)],
                    },
                    Events(Arc::new(move |event| collected.lock().unwrap().push(event))),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let inspect = view.read(cx).inspect(window, cx);
        assert_eq!(inspect["lists"]["names"]["view_rows"], 3);
        assert_eq!(inspect["lists"]["names"]["selected_shown"], serde_json::Value::Null);
        // Items follow the view: Ann, Bo, Cleo.
        let ann = window.find("names:p2").bounds();
        let cleo = window.find("names:p1").bounds();
        assert!(ann.origin.y < cleo.origin.y, "sorted ascending by name");
        window.click("names:p3", cx);
        window.render_frame(cx);
        assert_eq!(
            view.read(cx).inspect(window, cx)["lists"]["names"]["selected_shown"],
            "p3"
        );
        // An edit on the sort column recomputes the order: Cleo becomes Aaron.
        let edit = serde_json::json!({
            "request": 2, "id": "people", "base_revision": 1, "revision": 2,
            "change": {"op": "edit", "edits": [{"kind": "cell", "row": 0, "column": 1, "value": "Aaron"}]}
        });
        let update = crate::datasets::Update::parse(&serde_json::to_vec(&edit).unwrap()).unwrap();
        view.update(cx, |view, cx| view.update_dataset(update, 0, cx));
        window.render_frame(cx);
        let aaron = window.find("names:p1").bounds();
        let ann = window.find("names:p2").bounds();
        assert!(aaron.origin.y < ann.origin.y, "recomputed after the edit");
        // The next publication owns the selection again.
        view.update(cx, |view, cx| view.publish(list(2, Some("p3")), window, cx));
        window.render_frame(cx);
        assert_eq!(
            view.read(cx).inspect(window, cx)["lists"]["names"]["selected_shown"],
            serde_json::Value::Null
        );
    })
    .unwrap();
    let picks = events
        .lock()
        .unwrap()
        .iter()
        .filter_map(|event| match event {
            Event::ListSelect {
                record,
                row,
                dataset_revision,
                ..
            } => Some((record.clone(), *row, *dataset_revision)),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(picks, vec![("p3".to_string(), 1, 1)]);
    // Lists need record IDs.
    let (_, without_ids) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: list(1, None),
                        datasets: vec![people(false)],
                    },
                    Events(Arc::new(|_| {})),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    assert!(
        cx.update(|cx| without_ids.read(cx).failure.clone())
            .is_some_and(|message| message.contains("record IDs"))
    );
}

#[gpui::test]
fn cached_subtrees_render_again_only_when_their_content_changes(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let tree = |revision: u64, a: &str, order: &str| {
        Snapshot::parse(
            format!(
                r#"{{"revision":{revision},"root":{{"kind":"column","id":"root","children":[{order}]}}}}"#,
                order = order
                    .replace("A", &format!(r#"{{"kind":"column","id":"a","style":{{"height":{{"px":120}},"cached":true}},"children":[{{"kind":"text","id":"a-text","text":"{a}"}}]}}"#))
                    .replace("B", r#"{"kind":"column","id":"b","style":{"height":{"px":120},"cached":true},"children":[{"kind":"text","id":"b-text","text":"b"}]}"#)
                    .replace("S", r#"{"kind":"text","id":"status","text":"idle"}"#)
            )
            .as_bytes(),
        )
        .unwrap()
    };
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: tree(1, "one", "A,B,S"),
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
    let renders =
        |view: &gpui_kit::Entity<DartView>, window: &gpui_kit::Window, cx: &gpui_kit::App| {
            let subtrees = view.read(cx).inspect(window, cx)["subtrees"].clone();
            (
                subtrees["a"]["renders"].as_u64().unwrap(),
                subtrees["b"]["renders"].as_u64().unwrap(),
            )
        };
    let update = |json: serde_json::Value| {
        crate::protocol::Update::parse(&serde_json::to_vec(&json).unwrap()).unwrap()
    };
    // The harness's render_frame refreshes the window, which bypasses caching
    // by design; a plain draw is what a real frame does.
    let frame = |window: &mut gpui_kit::Window, cx: &mut gpui_kit::App| {
        window.draw(cx).clear(cx);
    };
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let (a0, b0) = renders(&view, window, cx);
        frame(window, cx);
        frame(window, cx);
        assert_eq!(renders(&view, window, cx), (a0, b0), "plain frames reuse both");
        assert!(window.find("a-text").bounds().origin.y < window.find("b-text").bounds().origin.y);
        view.update(cx, |view, cx| {
            view.apply_update(
                update(serde_json::json!({"revision": 2, "base_revision": 1, "ops": [
                    {"op": "set", "id": "a-text", "node": {"kind": "text", "id": "a-text", "text": "two"}}
                ]})),
                window,
                cx,
            )
        });
        frame(window, cx);
        assert_eq!(renders(&view, window, cx), (a0 + 1, b0), "a change inside a renders a only");
        assert_eq!(view.read(cx).inspect(window, cx)["labels"]["a-text"], "two");
        view.update(cx, |view, cx| {
            view.apply_update(
                update(serde_json::json!({"revision": 3, "base_revision": 2, "ops": [
                    {"op": "set", "id": "status", "node": {"kind": "text", "id": "status", "text": "busy"}}
                ]})),
                window,
                cx,
            )
        });
        frame(window, cx);
        assert_eq!(renders(&view, window, cx), (a0 + 1, b0), "a change outside renders neither");
        view.update(cx, |view, cx| {
            view.apply_update(
                update(serde_json::json!({"revision": 4, "base_revision": 3, "ops": [
                    {"op": "children", "id": "root", "children": ["b", "a", "status"]}
                ]})),
                window,
                cx,
            )
        });
        frame(window, cx);
        assert!(window.find("b-text").bounds().origin.y < window.find("a-text").bounds().origin.y);
        // A cached element keeps its bounds; moving it re-renders it, which is
        // the reorder cost the strategies experiment measured.
        assert_eq!(renders(&view, window, cx), (a0 + 2, b0 + 1), "moved cached subtrees render again");
        view.update(cx, |view, cx| view.publish(tree(5, "three", "B,A,S"), window, cx));
        frame(window, cx);
        assert_eq!(renders(&view, window, cx), (a0 + 3, b0 + 2), "a whole publication renders every cached subtree");
        assert_eq!(view.read(cx).inspect(window, cx)["labels"]["a-text"], "three");
    })
    .unwrap();
}

#[gpui::test]
fn typing_into_an_input_inside_a_cached_subtree_renders_it(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let snapshot = Snapshot::parse(
        br#"{"revision":1,"root":{"kind":"column","id":"root","children":[
            {"kind":"column","id":"part","style":{"height":{"px":160},"cached":true},"children":[
                {"kind":"input","id":"name","placeholder":"Name"}
            ]},
            {"kind":"text","id":"status","text":"idle"}
        ]}}"#,
    )
    .unwrap();
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot,
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
    let frame = |window: &mut gpui_kit::Window, cx: &mut gpui_kit::App| {
        window.draw(cx).clear(cx);
    };
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let renders =
            |view: &gpui_kit::Entity<DartView>, window: &gpui_kit::Window, cx: &gpui_kit::App| {
                view.read(cx).inspect(window, cx)["subtrees"]["part"]["renders"]
                    .as_u64()
                    .unwrap()
            };
        let before = renders(&view, window, cx);
        frame(window, cx);
        assert_eq!(
            renders(&view, window, cx),
            before,
            "an idle frame reuses the subtree"
        );
        window.click("name", cx);
        window.press("a", cx);
        window.press("b", cx);
        frame(window, cx);
        assert_eq!(
            window.find("name").value(),
            Some("ab"),
            "typing reaches the retained input"
        );
        assert!(
            renders(&view, window, cx) > before,
            "the input's own change marks its cached container dirty"
        );
    })
    .unwrap();
}
