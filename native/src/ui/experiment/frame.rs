use gpui_kit::*;
use serde::Serialize;
use std::{cell::Cell, rc::Rc, time::Instant};

#[cfg(test)]
pub(crate) struct BoundsProbe {
    pub child: AnyElement,
    pub id: String,
    pub bounds: Rc<std::cell::RefCell<std::collections::HashMap<String, Bounds<Pixels>>>>,
}
#[cfg(test)]
impl IntoElement for BoundsProbe {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}
#[cfg(test)]
impl Element for BoundsProbe {
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
        bounds: Bounds<Pixels>,
        _: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) {
        self.bounds.borrow_mut().insert(self.id.clone(), bounds);
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
    }
}

#[derive(Clone, Copy, Default, Serialize)]
pub(super) struct Frame {
    pub serial: u64,
    revision: u64,
    request_layout_us: u64,
    layout_gap_us: u64,
    prepaint_us: u64,
    paint_us: u64,
}
pub(super) struct FrameProbe {
    child: AnyElement,
    output: Rc<Cell<Frame>>,
    measured: Frame,
    layout_end: Option<Instant>,
}
impl FrameProbe {
    pub fn new(child: AnyElement, revision: u64, output: Rc<Cell<Frame>>) -> Self {
        Self {
            child,
            output,
            measured: Frame {
                revision,
                ..Default::default()
            },
            layout_end: None,
        }
    }
}
impl IntoElement for FrameProbe {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}
impl Element for FrameProbe {
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
        let start = Instant::now();
        let layout = self.child.request_layout(window, cx);
        self.measured.request_layout_us = start.elapsed().as_micros() as u64;
        self.layout_end = Some(Instant::now());
        (layout, ())
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
        self.measured.layout_gap_us = self
            .layout_end
            .map(|t| t.elapsed().as_micros() as u64)
            .unwrap_or(0);
        let start = Instant::now();
        self.child.prepaint(window, cx);
        self.measured.prepaint_us = start.elapsed().as_micros() as u64;
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
        let start = Instant::now();
        self.child.paint(window, cx);
        self.measured.paint_us = start.elapsed().as_micros() as u64;
        self.measured.serial = self.output.get().serial + 1;
        self.output.set(self.measured);
    }
}
