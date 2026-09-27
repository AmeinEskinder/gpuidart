use super::DartView;
use crate::{
    Events,
    datasets::Initial,
    protocol::{Event, Node, Snapshot},
};
use gpui_kit::test::TestWindowExt;
use gpui_kit::{
    App, AppContext, KeyUpEvent, Keystroke, PlatformInput, Role, SharedString, TestAppContext,
    Window, WindowOptions, gpui,
};
use serde_json::json;
use std::sync::Arc;
use std::sync::Mutex;

fn snapshot(revision: u64, selected: &str, reverse: bool, disabled: bool) -> Snapshot {
    let mut options = vec![
        json!({"id":"watchlist","label":"Watchlist"}),
        json!({"id":"blocked","label":"Unavailable","disabled":true}),
        json!({"id":"detail","label":"Instrument"}),
        json!({"id":"settings","label":"Settings"}),
    ];
    if reverse {
        options.reverse();
    }
    Snapshot::parse(
        &serde_json::to_vec(&json!({"revision":revision,"root":{
        "kind":"column","id":"root","children":[
            {"kind":"input","id":"before","placeholder":"Before"},
            {"kind":"radio_group","id":"pages","options":options,"selected":selected,"disabled":disabled,
             "semantics":{"label":"Terminal pages"}},
            {"kind":"input","id":"after","placeholder":"After"}
        ]}}))
        .unwrap(),
    )
    .unwrap()
}
fn tab(id: &str) -> SharedString {
    json!(["pages", "radio", id]).to_string().into()
}
fn press(window: &mut Window, key: &str, cx: &mut App) {
    window.press(key, cx);
    window.dispatch_event(
        PlatformInput::KeyUp(KeyUpEvent {
            keystroke: Keystroke::parse(key).unwrap(),
        }),
        cx,
    );
    window.render_frame(cx);
}

#[gpui::test]
fn radio_keyboard_semantics_reorder_disabled_and_stale_callbacks(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let out = events.clone();
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: snapshot(1, "watchlist", false, false),
                        datasets: vec![],
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
        assert_eq!(window.find("pages").role(), Some(Role::RadioGroup));
        assert_eq!(window.find("pages").label(), Some("Terminal pages"));
        assert_eq!(
            window.find(tab("watchlist")).role(),
            Some(Role::RadioButton)
        );
        assert_eq!(window.find(tab("watchlist")).selected(), Some(true));
        window.click("before", cx);
        press(window, "tab", cx);
        assert!(view.read(cx).choices["pages"].focus["watchlist"].is_focused(window));
        press(window, "right", cx);
        assert!(view.read(cx).choices["pages"].focus["detail"].is_focused(window));
        assert_eq!(window.find(tab("watchlist")).selected(), Some(true));
        assert_eq!(
            events
                .lock()
                .unwrap()
                .iter()
                .filter(|e| matches!(e, Event::RadioChange { .. }))
                .count(),
            1
        );
        assert!(events.lock().unwrap().iter().any(
            |e| matches!(e,Event::RadioChange{selected,revision:1,..} if selected == "detail")
        ));
        let retained = view.read(cx).choices["pages"].focus["detail"].clone();
        view.update(cx, |view, cx| {
            view.publish(snapshot(2, "detail", true, false), window, cx)
        });
        window.render_frame(cx);
        assert_eq!(view.read(cx).choices["pages"].focus["detail"], retained);
        assert!(view.read(cx).choices["pages"].focus["detail"].is_focused(window));
        assert_eq!(window.find(tab("detail")).selected(), Some(true));
        let accepted_count = events.lock().unwrap().len();
        press(window, "space", cx);
        assert_eq!(events.lock().unwrap().len(), accepted_count);
        press(window, "home", cx);
        assert!(view.read(cx).choices["pages"].focus["settings"].is_focused(window));
        press(window, "end", cx);
        assert!(view.read(cx).choices["pages"].focus["watchlist"].is_focused(window));
        press(window, "tab", cx);
        assert_eq!(window.find("after").focused(), Some(true));
        window.click(tab("settings"), cx);
        window.render_frame(cx);
        assert!(view.read(cx).choices["pages"].focus["settings"].is_focused(window));
        assert!(events.lock().unwrap().iter().any(
            |e| matches!(e,Event::RadioChange{selected,revision:2,..} if selected == "settings")
        ));
        view.update(cx, |view, cx| {
            view.publish(snapshot(3, "detail", false, true), window, cx)
        });
        window.render_frame(cx);
        let count = events.lock().unwrap().len();
        window.click(tab("settings"), cx);
        window.click(tab("blocked"), cx);
        assert_eq!(events.lock().unwrap().len(), count);
        assert!(
            !view.read(cx).choices["pages"]
                .focus
                .values()
                .any(|f| f.is_focused(window))
        );
        let mut removed = snapshot(4, "detail", false, false);
        removed.root = Node::Text {
            id: "root".into(),
            text: "Removed".into(),
            style: None,
            semantics: None,
        };
        view.update(cx, |view, cx| view.publish(removed, window, cx));
        view.update(cx, |view, cx| {
            view.publish(snapshot(5, "detail", false, false), window, cx)
        });
        view.update(cx, |view, cx| {
            assert!(!view.choice_input("pages", "detail", &retained, None, window, cx))
        });
    })
    .unwrap();
}
