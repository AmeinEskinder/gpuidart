use super::{ExperimentView, validate_geometry};
use crate::{
    datasets::Initial,
    experiment::{Setup, model::Strategy},
};
use gpui_kit::test::TestWindowExt;
use gpui_kit::{
    AppContext, Bounds, Point, TestAppContext, WindowBounds, WindowOptions, gpui, px, size,
};
use serde_json::json;

#[gpui::test]
fn strategies_lay_out_the_same_controls_and_text(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let mut reference = None;
    for strategy in [Strategy::Snapshot, Strategy::Subviews, Strategy::Patches] {
        let initial: Initial = serde_json::from_value(json!({
            "snapshot":{"revision":1,"root":{"kind":"column","id":"root","style":{"gap":4},"children":[
                {"kind":"input","id":"retained-input","placeholder":"Input","style":{"height":{"px":32}}},
                {"kind":"table","id":"retained-table","dataset":"records","style":{"height":{"px":240}}},
                {"kind":"column","id":"section-0","style":{"height":{"px":768},"gap":2},"children":[
                    {"kind":"text","id":"heading-0","text":"Device 0"},
                    {"kind":"text","id":"field-0","text":"Property 0","style":{"font_size":12,"foreground":"token:foreground"}}
                ]}
            ]}},
            "datasets":[{"id":"records","revision":1,"data":{"columns":["ID","Value"],"rows":[["0","Row 0"]]}}]
        })).unwrap();
        initial.validate().unwrap();
        validate_geometry(&initial.snapshot).unwrap();
        let (handle, view) = cx.update(|cx| {
            gpui_kit::open_window(
                WindowOptions {
                    window_bounds: Some(WindowBounds::Windowed(Bounds {
                        origin: Point::default(),
                        size: size(px(960.), px(640.)),
                    })),
                    ..Default::default()
                },
                cx,
                |window, cx| {
                    cx.new(|cx| ExperimentView::new(Setup { strategy, initial }, window, cx))
                },
            )
            .unwrap()
        });
        cx.update_window(handle, |_, window, cx| {
            window.render_frame(cx);
            let rendered: std::collections::HashMap<_, _> = view
                .read(cx)
                .whole
                .iter()
                .chain(view.read(cx).parts.values())
                .flat_map(|view| {
                    view.read(cx)
                        .experiment_bounds
                        .as_ref()
                        .unwrap()
                        .borrow()
                        .clone()
                })
                .collect();
            let bounds: Vec<_> = [
                "retained-input",
                "retained-table",
                "section-0",
                "heading-0",
                "field-0",
            ]
            .map(|id| *rendered.get(id).expect("observed node bounds"))
            .to_vec();
            if let Some(reference) = &reference {
                assert_eq!(&bounds, reference, "{strategy:?} geometry differs");
            } else {
                reference = Some(bounds);
            }
            window.remove_window();
        })
        .unwrap();
    }
}
