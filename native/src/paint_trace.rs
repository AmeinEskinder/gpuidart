use crate::trace::{Key, Trace};
use gpui_kit::*;
use std::sync::Arc;

/// Delegates layout/painting unchanged and records completion of content painting.
/// Paint appends scene commands; this is not GPU submission or presentation.
pub(crate) struct ContentPaint {
    pub child: AnyElement,
    pub trace: Arc<Trace>,
    pub revision: u64,
}

impl IntoElement for ContentPaint {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

impl Element for ContentPaint {
    type RequestLayoutState = ();
    type PrepaintState = ();
    fn id(&self) -> Option<ElementId> {
        None
    }
    fn source_location(&self) -> Option<&'static std::panic::Location<'static>> {
        None
    }
    fn request_layout(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, ()) {
        (self.child.request_layout(window, cx), ())
    }
    fn prepaint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        _: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) {
        self.child.prepaint(window, cx);
    }
    fn paint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        _: &mut (),
        _: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) {
        let started = self.trace.start();
        self.child.paint(window, cx);
        self.trace.complete(
            "native.content_paint",
            Key {
                operation: "snapshot",
                request: self.revision,
            },
            started,
            None,
            None,
        );
        self.trace.first_content_paint();
    }
}

/// In benchmark-trace builds, records the first content paint of each
/// revision in the input trace, so a PresentMon record can be matched to
/// the update it shows: the first present whose CPU start follows the paint.
#[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
pub(crate) struct PaintMarker {
    pub child: AnyElement,
    pub revision: u64,
    pub painted: std::rc::Rc<std::cell::Cell<u64>>,
}

#[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
impl IntoElement for PaintMarker {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

#[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
impl Element for PaintMarker {
    type RequestLayoutState = ();
    type PrepaintState = ();
    fn id(&self) -> Option<ElementId> {
        None
    }
    fn source_location(&self) -> Option<&'static std::panic::Location<'static>> {
        None
    }
    fn request_layout(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, ()) {
        (self.child.request_layout(window, cx), ())
    }
    fn prepaint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        _: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) {
        self.child.prepaint(window, cx);
    }
    fn paint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        _: &mut (),
        _: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) {
        self.child.paint(window, cx);
        if self.painted.get() != self.revision {
            self.painted.set(self.revision);
            crate::input_trace::record_sequence(
                "content_painted",
                None,
                serde_json::json!({"revision": self.revision}),
            );
        }
    }
}
