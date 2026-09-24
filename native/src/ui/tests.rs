use super::DartView;
use crate::{
    Events,
    protocol::{Event, Node, Snapshot, TableData},
};
use gpui_kit::gpui;
use gpui_kit::test::TestWindowExt;
use gpui_kit::{AppContext, Bounds, Point, TestAppContext, WindowBounds, WindowOptions, px, size};
use std::sync::{Arc, Mutex};

fn description(revision: u64) -> Snapshot {
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
                        rows: (0..10_000)
                            .map(|i| vec![i.to_string(), format!("Row {i}")])
                            .collect(),
                    }),
                },
            ],
        },
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
