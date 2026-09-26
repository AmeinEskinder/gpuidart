use super::DartView;
use crate::{
    Events,
    datasets::Initial,
    protocol::{Event, Snapshot},
};
use gpui_kit::component::WindowExt;
use gpui_kit::test::TestWindowExt;
use gpui_kit::{AppContext, Focusable, TestAppContext, WindowOptions, gpui, point, px};
use serde_json::json;
use std::sync::{Arc, Mutex};

#[gpui::test]
fn confirmation_dialog_cancel_confirm_retention_disabled_and_removal(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let snapshot = |revision, disabled| {
        Snapshot::parse(&serde_json::to_vec(&json!({
        "revision":revision,"root":{"kind":"confirm_dialog","id":"reset","label":"Reset",
        "title":"Reset preferences?","message":"Discard the draft?","confirm_label":"Reset","cancel_label":"Keep",
        "disabled":disabled,"style":{"width":{"px":160},"background":"token:secondary"}}
    })).unwrap()).unwrap()
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
                    Events(Arc::new(move |e| collected.lock().unwrap().push(e))),
                    window,
                    cx,
                )
            })
        })
        .unwrap()
    });
    let results = || {
        events
            .lock()
            .unwrap()
            .iter()
            .filter_map(|e| match e {
                Event::DialogResult {
                    revision,
                    id,
                    confirmed,
                } => Some((*revision, id.clone(), *confirmed)),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    let trigger_focus = cx
        .update_window(handle, |_, window, cx| {
            window.render_frame(cx);
            assert_eq!(window.find("reset").bounds().size.width, px(160.));
            window.focus_next(cx);
            let focus = window.focused(cx).unwrap();
            window.click("reset", cx);
            focus
        })
        .unwrap();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert!(window.has_active_dialog(cx));
        assert_ne!(window.focused(cx), Some(trigger_focus.clone()));
        for _ in 0..8 {
            window.press("tab", cx);
            assert_ne!(
                window.focused(cx),
                Some(trigger_focus.clone()),
                "modal Tab traversal stays inside the dialog"
            );
        }
        view.update(cx, |view, cx| view.publish(snapshot(2, false), window, cx));
        window.render_frame(cx);
        assert!(window.has_active_dialog(cx));
        window.press("escape", cx);
    })
    .unwrap();
    cx.run_until_parked();
    assert_eq!(
        results(),
        [(1, "reset".into(), false)],
        "opening revision and one cancellation"
    );
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert!(!window.has_active_dialog(cx));
        assert_eq!(window.focused(cx), Some(trigger_focus));
        window.click("reset", cx);
    })
    .unwrap();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.press("enter", cx);
    })
    .unwrap();
    cx.run_until_parked();
    assert_eq!(
        results(),
        [(1, "reset".into(), false), (2, "reset".into(), true)]
    );
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert!(!window.has_active_dialog(cx));
        view.update(cx, |view, cx| view.publish(snapshot(3, true), window, cx));
        window.render_frame(cx);
        window.click("reset", cx);
        assert!(!window.has_active_dialog(cx));
        view.update(cx, |view, cx| view.publish(snapshot(4, false), window, cx));
        window.render_frame(cx);
        window.click("reset", cx);
    })
    .unwrap();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert!(window.has_active_dialog(cx));
        let removed =
            Snapshot::parse(br#"{"revision":5,"root":{"kind":"text","id":"reset","text":"Gone"}}"#)
                .unwrap();
        view.update(cx, |view, cx| view.publish(removed, window, cx));
        window.render_frame(cx);
        assert!(!window.has_active_dialog(cx));
        assert!(view.read(cx).active_dialog.borrow().is_none());
    })
    .unwrap();
    assert_eq!(
        results(),
        [
            (1, "reset".into(), false),
            (2, "reset".into(), true),
            (4, "reset".into(), false)
        ]
    );
}

#[gpui::test]
fn select_keyboard_popup_retention_identity_cancel_and_disabled(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let snapshot = |revision, selected: Option<&str>, disabled, reversed| {
        let mut options = vec![
            json!({"id":"light","label":"Light"}),
            json!({"id":"dark","label":"Dark"}),
            json!({"id":"system","label":"System"}),
        ];
        if reversed {
            options.reverse();
            options[1]["label"] = json!("Dark revised");
        }
        Snapshot::parse(
            &serde_json::to_vec(&json!({"revision":revision,"root":{
                "kind":"select","id":"appearance", "options":options,"selected":selected,
                "disabled":disabled,"placeholder":"Choose appearance",
                "style":{"width":{"px":240},"foreground":"token:primary"}
            }}))
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
                        snapshot: snapshot(1, Some("light"), false, false),
                        datasets: vec![],
                    },
                    Events(Arc::new(move |e| collected.lock().unwrap().push(e))),
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
            .filter_map(|e| match e {
                Event::SelectChange {
                    revision,
                    id,
                    selected,
                } => Some((*revision, id.clone(), selected.clone())),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    let (entity, trigger_focus) = cx
        .update_window(handle, |_, window, cx| {
            window.render_frame(cx);
            assert_eq!(window.find("appearance").bounds().size.width, px(240.));
            assert_eq!(
                window
                    .within("appearance")
                    .find("input")
                    .bounds()
                    .size
                    .width,
                px(240.)
            );
            let state = &view.read(cx).selects["appearance"].state;
            let identity = (state.entity_id(), state.read(cx).focus_handle(cx));
            window.click("appearance", cx);
            identity
        })
        .unwrap();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        let menu_focus = view.read(cx).selects["appearance"]
            .state
            .read(cx)
            .focus_handle(cx);
        assert!(menu_focus.is_focused(window));
        assert_ne!(
            menu_focus, trigger_focus,
            "pointer opened the menu, not just focused the trigger"
        );
        view.update(cx, |view, cx| {
            view.publish(snapshot(2, Some("light"), false, false), window, cx)
        });
        window.render_frame(cx);
        assert_eq!(window.focused(cx), Some(menu_focus));
        window.press("down", cx);
        window.press("enter", cx);
    })
    .unwrap();
    cx.run_until_parked();
    assert_eq!(changes(), [(2, "appearance".into(), Some("dark".into()))]);
    cx.update_window(handle, |_, window, cx| {
        view.update(cx, |view, cx| {
            view.publish(snapshot(3, Some("dark"), false, true), window, cx)
        });
        window.render_frame(cx);
        assert_eq!(
            view.read(cx).selects["appearance"].state.entity_id(),
            entity
        );
        assert_eq!(
            view.read(cx).selects["appearance"]
                .state
                .read(cx)
                .selected_value()
                .map(String::as_str),
            Some("dark")
        );
        window.click("appearance", cx);
    })
    .unwrap();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.press("down", cx);
        window.press("escape", cx);
    })
    .unwrap();
    cx.run_until_parked();
    assert_eq!(changes().len(), 1, "cancel does not commit a selection");
    cx.update_window(handle, |_, window, cx| {
        assert_eq!(
            window.focused(cx),
            Some(trigger_focus.clone()),
            "cancel restores trigger focus"
        );
        assert_eq!(
            view.read(cx).selects["appearance"]
                .state
                .read(cx)
                .selected_value()
                .map(String::as_str),
            Some("dark")
        );
        view.update(cx, |view, cx| {
            view.publish(snapshot(4, None, true, true), window, cx)
        });
        window.render_frame(cx);
        window.click("appearance", cx);
        window.press("down", cx);
        window.press("enter", cx);
    })
    .unwrap();
    cx.run_until_parked();
    assert_eq!(changes().len(), 1, "disabled select cannot commit");
    cx.update_window(handle, |_, window, cx| {
        assert!(
            view.read(cx).selects["appearance"]
                .state
                .read(cx)
                .selected_value()
                .is_none()
        );
        view.update(cx, |view, cx| {
            view.publish(snapshot(5, Some("dark"), false, false), window, cx)
        });
        window.render_frame(cx);
        window.click("appearance", cx);
    })
    .unwrap();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert_ne!(
            view.read(cx).selects["appearance"]
                .state
                .read(cx)
                .focus_handle(cx),
            trigger_focus
        );
        view.update(cx, |view, cx| {
            view.publish(snapshot(6, Some("dark"), true, false), window, cx)
        });
        window.render_frame(cx);
    })
    .unwrap();
    cx.run_until_parked();
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert_eq!(
            view.read(cx).selects["appearance"]
                .state
                .read(cx)
                .focus_handle(cx),
            trigger_focus,
            "disabling an open menu dismisses it"
        );
        window.press("enter", cx);
    })
    .unwrap();
    assert_eq!(changes().len(), 1);
}

#[gpui::test]
fn slider_pointer_keyboard_bounds_disabled_and_retained_focus(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let snapshot = |revision, number, disabled, min, max, step| {
        Snapshot::parse(
            &serde_json::to_vec(&json!({"revision":revision,"root":{
                "kind":"slider","id":"density","min":min,"max":max,"step":step,
                "number":number,"disabled":disabled,
                "style":{"width":{"px":240},"foreground":"token:primary"}
            }}))
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
                        snapshot: snapshot(1, 20., false, 0., 100., 5.),
                        datasets: vec![],
                    },
                    Events(Arc::new(move |e| collected.lock().unwrap().push(e))),
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
                Event::SliderChange {
                    revision,
                    id,
                    number,
                } => Some((*revision, id.clone(), *number)),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        assert_eq!(window.find("density").bounds().size.width, px(240.));
        window.focus_next(cx);
        assert!(
            view.read(cx).sliders["density"].focus.is_focused(window),
            "slider participates in Tab traversal"
        );
        window.press("right", cx);
        assert_eq!(changes(), [(1, "density".into(), 25.)]);
        let focus = window.focused(cx).unwrap();
        let entity = view.read(cx).sliders["density"].state.entity_id();
        view.update(cx, |view, cx| {
            view.publish(snapshot(2, 25., false, 0., 100., 5.), window, cx)
        });
        window.render_frame(cx);
        assert_eq!(window.focused(cx), Some(focus.clone()));
        assert_eq!(view.read(cx).sliders["density"].state.entity_id(), entity);
        window.press("end", cx);
        window.press("right", cx);
        assert_eq!(changes().len(), 2, "no event for an unchanged endpoint");
        assert_eq!(changes()[1], (2, "density".into(), 100.));
        window.press("home", cx);
        assert_eq!(changes()[2].2, 0.);
        window.click("density", cx);
        assert_eq!(
            view.read(cx).sliders["density"]
                .state
                .read(cx)
                .value()
                .start(),
            50.,
            "native track click at midpoint"
        );
        assert!(focus.is_focused(window));
    })
    .unwrap();
    // Entity notifications are delivered after the app update completes.
    assert_eq!(changes()[3].2, 50.);
    cx.update_window(handle, |_, window, cx| {
        view.update(cx, |view, cx| {
            view.publish(snapshot(3, 50., true, 0., 100., 5.), window, cx)
        });
        window.render_frame(cx);
        window.click("density", cx);
        window.press("right", cx);
        assert_eq!(changes().len(), 4);
        // The pinned pointer snap rounds relative to zero. Exercise a max that
        // rounds above the allowed range and prove the adapter clamps it.
        view.update(cx, |view, cx| {
            view.publish(snapshot(4, 3., false, 3., 8., 5.), window, cx)
        });
        window.render_frame(cx);
        window.click_at("density", point(px(237.), px(10.)), cx);
    })
    .unwrap();
    cx.update_window(handle, |_, _, cx| {
        assert!(changes().iter().skip(4).all(|e| (3. ..=8.).contains(&e.2)));
        assert_eq!(changes().last().unwrap().2, 8.);
        assert_eq!(
            view.read(cx).sliders["density"]
                .state
                .read(cx)
                .value()
                .start(),
            8.
        );
    })
    .unwrap();
}
