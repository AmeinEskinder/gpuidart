use super::DartView;
use crate::{
    Events,
    datasets::Initial,
    protocol::{Event, Snapshot},
};
use gpui_kit::test::TestWindowExt;
use gpui_kit::{AppContext, TestAppContext, WindowOptions, gpui, point, px};
use serde_json::json;
use std::sync::{Arc, Mutex};

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
