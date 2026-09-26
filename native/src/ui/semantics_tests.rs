use super::DartView;
use crate::{
    Events,
    datasets::Initial,
    protocol::{Event, Snapshot},
};
use gpui_kit::test::TestWindowExt;
use gpui_kit::{AppContext, Role, TestAppContext, WindowOptions, gpui};
use serde_json::json;
use std::sync::Arc;

#[gpui::test]
fn real_controls_expose_roles_labels_and_retained_values(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let snapshot = Snapshot::parse(&serde_json::to_vec(&json!({"revision":1,"root":{
        "kind":"column","id":"form","semantics":{"role":"group","label":"Settings"},"children":[
            {"kind":"text","id":"title","text":"Visible title","semantics":{"role":"heading","heading_level":1,"label":"Heading name"}},
            {"kind":"text","id":"label","text":"Visible label"},
            {"kind":"button","id":"go","label":"Go","semantics":{"label":"Save changes"}},
            {"kind":"checkbox","id":"check","label":"Check","checked":true,"semantics":{"label":"Notifications"}},
            {"kind":"input","id":"name","placeholder":"Name","semantics":{"label":"Display name"}},
            {"kind":"slider","id":"spacing","min":8,"max":24,"step":2,"number":16,"semantics":{"label":"Spacing"}},
            {"kind":"select","id":"accent","options":[{"id":"a","label":"Ocean"}],"selected":"a","semantics":{"label":"Accent"}},
            {"kind":"confirm_dialog","id":"reset","label":"Reset","title":"Reset?","message":"Sure?","confirm_label":"Yes","cancel_label":"No","semantics":{"label":"Reset defaults"}}
        ]}})).unwrap()).unwrap();
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
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        for (id, role, name) in [
            ("form", Role::Group, "Settings"),
            ("title", Role::Heading, "Heading name"),
            ("label", Role::Label, "Visible label"),
            ("go", Role::Button, "Save changes"),
            ("check", Role::CheckBox, "Notifications"),
            ("name", Role::TextInput, "Display name"),
            ("spacing", Role::Slider, "Spacing"),
            ("reset", Role::Button, "Reset defaults"),
        ] {
            let node = window.find(id);
            assert_eq!(node.role(), Some(role), "{id}");
            assert_eq!(node.label(), Some(name), "{id}");
        }
        assert_eq!(window.find("label").value(), Some("Visible label"));
        assert_eq!(window.find("check").checked(), Some(true));
        let select = gpui_kit::base::test_support::snapshots(window)
            .into_iter()
            .find(|s| s.role() == Some(Role::ComboBox))
            .unwrap();
        assert_eq!(select.label(), Some("Accent"));
        assert_eq!(select.value(), Some("Ocean"));
        let input = view.read(cx).inputs["name"].state.clone();
        input.update(cx, |state, cx| state.set_value("Native edit", window, cx));
        window.render_frame(cx);
        assert_eq!(window.find("name").value(), Some("Native edit"));
    })
    .unwrap();
}

#[gpui::test]
fn confirmation_has_real_named_content_and_clickable_decisions(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(std::sync::Mutex::new(Vec::new()));
    let out = events.clone();
    let snapshot = Snapshot::parse(br#"{"revision":1,"root":{"kind":"confirm_dialog","id":"reset","label":"Reset","title":"Reset preferences?","message":"Sure?","confirm_label":"Yes","cancel_label":"No"}}"#).unwrap();
    let (handle, _) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot,
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
    for (button, label) in [("cancel", "No"), ("ok", "Yes")] {
        cx.update_window(handle, |_, window, cx| {
            window.render_frame(cx);
            window.click("reset", cx);
        })
        .unwrap();
        // The modal moves during Kit's wall-clock animation. Resolve the click
        // against stable bounds instead of the preceding animation frame.
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        let mut previous = None;
        let mut stable = 0;
        while stable < 3 {
            let bounds = cx
                .update_window(handle, |_, window, cx| {
                    window.render_frame(cx);
                    window.find(button).bounds()
                })
                .unwrap();
            stable = if previous == Some(bounds) {
                stable + 1
            } else {
                0
            };
            previous = Some(bounds);
            assert!(
                std::time::Instant::now() < deadline,
                "Dialog geometry did not settle"
            );
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        cx.update_window(handle, |_, window, cx| {
            window.render_frame(cx);
            assert_eq!(
                window.find("confirmation-content").role(),
                Some(Role::Dialog)
            );
            assert_eq!(
                window.find("confirmation-content").label(),
                Some("Reset preferences?")
            );
            assert_eq!(window.find(button).label(), Some(label));
            window.click(button, cx);
        })
        .unwrap();
        cx.run_until_parked();
    }
    let results = events
        .lock()
        .unwrap()
        .iter()
        .filter_map(|event| match event {
            Event::DialogResult { confirmed, .. } => Some(*confirmed),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(results, [false, true]);
}
