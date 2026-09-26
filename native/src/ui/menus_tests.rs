use super::{DartView, menus::MenuInvoke};
use crate::{
    Events,
    datasets::Initial,
    protocol::{Event, Snapshot},
};
#[cfg(not(target_os = "macos"))]
use gpui_kit::Role;
use gpui_kit::test::TestWindowExt;
use gpui_kit::{
    AppContext, KeyUpEvent, Keystroke, PlatformInput, TestAppContext, WindowOptions, gpui,
};
use serde_json::json;
use std::sync::{Arc, Mutex};

fn snapshot(revision: u64, disabled: bool) -> Snapshot {
    Snapshot::parse(&serde_json::to_vec(&json!({"revision":revision,
        "root":{"kind":"input","id":"draft","placeholder":"Draft"},
        "actions":[{"name":"app.settings","keys":"ctrl+,","context":"global"},
            {"name":"draft.settings","keys":"ctrl+,","context":"draft"}],
        "menus":[{"id":"app","label":"Terminal","items":[
            {"kind":"action","id":"settings","label":"Settings","action":"app.settings","disabled":disabled,"checked":true}]}]
    })).unwrap()).unwrap()
}

#[gpui::test]
fn menus_dispatch_current_commands_preserve_keymap_and_scope_precedence(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let base_bindings = cx.update(|cx| cx.key_bindings().borrow().bindings().len());
    let events = Arc::new(Mutex::new(Vec::new()));
    let out = events.clone();
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: snapshot(1, false),
                        datasets: vec![],
                    },
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
        assert_eq!(
            cx.key_bindings().borrow().bindings().len(),
            base_bindings + 1
        );
        for revision in 2..12 {
            view.update(cx, |view, cx| {
                view.publish(snapshot(revision, false), window, cx)
            });
            assert_eq!(
                cx.key_bindings().borrow().bindings().len(),
                base_bindings + 1
            );
        }
        window.click("draft", cx);
        window.press("ctrl-,", cx);
        window.dispatch_event(
            PlatformInput::KeyUp(KeyUpEvent {
                keystroke: Keystroke::parse("ctrl-,").unwrap(),
            }),
            cx,
        );
        assert!(
            events
                .lock()
                .unwrap()
                .iter()
                .any(|e| matches!(e,Event::Action{name,..} if name=="draft.settings"))
        );
        window.dispatch_action(
            Box::new(MenuInvoke {
                menu: "app".into(),
                entry: "settings".into(),
                action: "app.settings".into(),
            }),
            cx,
        );
    })
    .unwrap();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert!(
            events
                .lock()
                .unwrap()
                .iter()
                .any(|e| matches!(e,Event::Action{name,revision:11,..} if name=="app.settings"))
        );
        view.update(cx, |view, cx| view.publish(snapshot(12, true), window, cx));
        assert_eq!(cx.key_bindings().borrow().bindings().len(), base_bindings);
        window.dispatch_action(
            Box::new(MenuInvoke {
                menu: "app".into(),
                entry: "settings".into(),
                action: "app.settings".into(),
            }),
            cx,
        );
    })
    .unwrap();
    cx.update_window(handle, |_, window, cx| {
        assert!(
            !events
                .lock()
                .unwrap()
                .iter()
                .any(|e| matches!(e, Event::Action { revision: 12, .. }))
        );
        let mut removed = snapshot(13, false);
        removed.menus.clear();
        view.update(cx, |view, cx| view.publish(removed, window, cx));
        assert_eq!(cx.key_bindings().borrow().bindings().len(), base_bindings);
        window.dispatch_action(
            Box::new(MenuInvoke {
                menu: "app".into(),
                entry: "settings".into(),
                action: "app.settings".into(),
            }),
            cx,
        );
    })
    .unwrap();
    assert!(
        !events
            .lock()
            .unwrap()
            .iter()
            .any(|e| matches!(e, Event::Action { revision: 13, .. }))
    );
    #[cfg(not(target_os = "macos"))]
    {
        cx.update_window(handle, |_, window, cx| {
            view.update(cx, |view, cx| view.publish(snapshot(14, false), window, cx));
            window.render_frame(cx);
            window.click("draft", cx);
            window.click("menu", cx);
            window.render_frame(cx);
            let snapshots = gpui_kit::base::test_support::snapshots(window);
            assert!(snapshots.iter().any(|s| s.role() == Some(Role::Menu)));
            assert!(
                snapshots.iter().any(|s| matches!(
                    s.role(),
                    Some(Role::MenuItem | Role::MenuItemCheckBox)
                ) && s.label() == Some("Settings")),
                "{snapshots:?}"
            );
            window.press("escape", cx);
            window.render_frame(cx);
        })
        .unwrap();
        cx.update_window(handle, |_, window, cx| {
            window.render_frame(cx);
            assert_eq!(window.find("draft").focused(), Some(true));
            window.click("menu", cx);
            window.render_frame(cx);
            view.update(cx, |view, cx| view.publish(snapshot(15, false), window, cx));
            window.render_frame(cx);
            assert!(
                gpui_kit::base::test_support::snapshots(window)
                    .iter()
                    .any(|s| s.role() == Some(Role::Menu))
            );
            window.press("down", cx);
            window.press("enter", cx);
        })
        .unwrap();
        cx.update_window(handle, |_, window, cx| {
            window.render_frame(cx);
        })
        .unwrap();
        assert!(
            events
                .lock()
                .unwrap()
                .iter()
                .any(|e| matches!(e,Event::Action{name,revision:15,..} if name=="app.settings"))
        );
    }
}
