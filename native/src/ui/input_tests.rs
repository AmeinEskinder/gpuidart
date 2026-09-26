use super::DartView;
use crate::{
    Events,
    datasets::Initial,
    input_control::{Operation, Request, Selection, State, Status},
    protocol::{Event, Snapshot},
};
use gpui_kit::test::TestWindowExt;
use gpui_kit::{AppContext, EntityInputHandler, TestAppContext, WindowOptions, gpui};
use serde_json::json;
use std::sync::{Arc, Mutex};

fn snapshot(revision: u64, controlled: bool) -> Snapshot {
    Snapshot::parse(
        &serde_json::to_vec(&json!({"revision":revision,"root":{
            "kind":"input","id":"name","placeholder":"Name","controlled":controlled
        }}))
        .unwrap(),
    )
    .unwrap()
}

fn write(
    request: u64,
    base: &State,
    text: Option<&str>,
    selection: Option<(usize, usize)>,
) -> Request {
    Request {
        request,
        id: "name".into(),
        operation: Operation::Write {
            generation: base.generation,
            base_revision: base.edit_revision,
            text: text.map(str::to_owned),
            selection: selection.map(|(start, end)| Selection { start, end }),
        },
    }
}

#[gpui::test]
fn controlled_input_writes_guard_native_edits_composition_and_generations(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let (handle, view) = cx.update(|cx| {
        gpui_kit::open_window(WindowOptions::default(), cx, |window, cx| {
            cx.new(|cx| {
                DartView::new(
                    Initial {
                        window: Default::default(),
                        snapshot: snapshot(1, true),
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
    let reply = || {
        events
            .lock()
            .unwrap()
            .iter()
            .rev()
            .find_map(|e| match e {
                Event::InputResult { status, state, .. } => Some((*status, state.clone())),
                _ => None,
            })
            .unwrap()
    };
    let written = cx
        .update_window(handle, |_, window, cx| {
            window.render_frame(cx);
            window.click("name", cx);
            let initial = view
                .update(cx, |v, cx| v.refresh_input("name", true, window, cx))
                .unwrap();
            view.update(cx, |v, cx| {
                v.input_command(write(1, &initial, Some("A😀日"), Some((1, 3))), window, cx)
            });
            assert_eq!(reply().0, Status::Applied);
            let state = reply().1.unwrap();
            assert_eq!(state.value, "A😀日");
            assert_eq!(state.selection, Selection { start: 1, end: 3 });
            assert_eq!(
                view.read(cx).inputs["name"].state.read(cx).selected_range(),
                1..5
            );
            view.update(cx, |v, cx| {
                v.input_command(write(2, &state, None, Some((2, 2))), window, cx)
            });
            assert_eq!(reply(), (Status::InvalidSelection, Some(state.clone())));
            state
        })
        .unwrap();
    assert!(
        !events
            .lock()
            .unwrap()
            .iter()
            .any(|e| matches!(e, Event::Input { .. })),
        "writes do not echo user edits"
    );
    cx.update_window(handle, |_, window, cx| {
        window.input("X", cx);
    })
    .unwrap();
    let edited = cx
        .update_window(handle, |_, window, cx| {
            let current = view
                .update(cx, |v, cx| v.refresh_input("name", true, window, cx))
                .unwrap();
            assert_eq!(current.value, "AX日");
            assert!(current.edit_revision > written.edit_revision);
            view.update(cx, |v, cx| {
                v.input_command(write(3, &written, Some("stale"), None), window, cx)
            });
            assert_eq!(reply(), (Status::Stale, Some(current.clone())));
            current
        })
        .unwrap();
    assert!(events.lock().unwrap().iter().any(|e| matches!(e,Event::Input{value,input_state:Some(state),..} if value=="AX日" && state.edit_revision==edited.edit_revision)));
    cx.update_window(handle, |_, window, cx| {
        // Even before observer callbacks run, a selection change invalidates a write.
        window.press("left", cx);
        view.update(cx, |v, cx| {
            v.input_command(write(4, &edited, Some("stale selection"), None), window, cx)
        });
        assert_eq!(reply().0, Status::Stale);
        let input = view.read(cx).inputs["name"].state.clone();
        input.update(cx, |input, cx| {
            input.replace_and_mark_text_in_range(None, "に", Some(1..1), window, cx)
        });
        let composing = view
            .update(cx, |v, cx| v.refresh_input("name", true, window, cx))
            .unwrap();
        assert!(composing.composing);
        let focus = window.focused(cx);
        view.update(cx, |v, cx| {
            v.input_command(
                write(5, &composing, Some("clobber"), Some((0, 0))),
                window,
                cx,
            )
        });
        assert_eq!(reply(), (Status::Composing, Some(composing.clone())));
        assert_eq!(window.focused(cx), focus);
        assert!(
            input
                .update(cx, |i, cx| i.marked_text_range(window, cx))
                .is_some()
        );
        input.update(cx, |i, cx| {
            i.replace_text_in_range(None, "日本", window, cx)
        });
        let committed = view
            .update(cx, |v, cx| v.refresh_input("name", true, window, cx))
            .unwrap();
        assert!(!committed.composing);
        assert!(committed.value.contains("日本"));
        assert!(committed.edit_revision > composing.edit_revision);
        input.update(cx, |i, cx| {
            i.replace_and_mark_text_in_range(None, "x", Some(1..1), window, cx)
        });
        let marked = view
            .update(cx, |v, cx| v.refresh_input("name", true, window, cx))
            .unwrap();
        input.update(cx, |i, cx| i.unmark_text(window, cx));
        // unmark_text does not notify. The command still resamples native composition.
        view.update(cx, |v, cx| {
            v.input_command(write(6, &marked, Some("after cancel"), None), window, cx)
        });
        assert_eq!(reply().0, Status::Stale);
        let unmarked = reply().1.unwrap();
        assert!(!unmarked.composing);
        view.update(cx, |v, cx| {
            v.input_command(write(7, &unmarked, Some("After"), Some((5, 5))), window, cx)
        });
        assert_eq!(reply().0, Status::Applied);
    })
    .unwrap();
    let after = reply().1.unwrap();
    cx.update_window(handle, |_, window, cx| {
        let entity = view.read(cx).inputs["name"].state.entity_id();
        view.update(cx, |v, cx| v.publish(snapshot(2, false), window, cx));
        view.update(cx, |v, cx| {
            v.input_command(write(8, &after, Some("blocked"), None), window, cx)
        });
        assert_eq!(reply().0, Status::NotControlled);
        view.update(cx, |v, cx| v.publish(snapshot(3, true), window, cx));
        assert_eq!(view.read(cx).inputs["name"].state.entity_id(), entity);
        view.update(cx, |v, cx| {
            v.input_command(write(9, &after, Some("old mode"), None), window, cx)
        });
        assert_eq!(reply().0, Status::Stale);
        assert_eq!(reply().1.unwrap().value, "After");
        let removed = Snapshot::parse(
            br#"{"revision":4,"root":{"kind":"text","id":"gone","text":"Removed"}}"#,
        )
        .unwrap();
        view.update(cx, |v, cx| v.publish(removed, window, cx));
        view.update(cx, |v, cx| {
            v.input_command(write(10, &after, Some("ghost"), None), window, cx)
        });
        assert_eq!(reply(), (Status::Missing, None));
        view.update(cx, |v, cx| v.publish(snapshot(5, true), window, cx));
        view.update(cx, |v, cx| {
            v.input_command(write(11, &after, Some("ghost"), None), window, cx)
        });
        assert_eq!(reply().0, Status::Stale);
        assert!(reply().1.unwrap().value.is_empty());
    })
    .unwrap();
}
