use super::*;
use crate::protocol::SelectOption;
use gpui_kit::component::select::Select;

/// The pinned Component Select does not forward an author ID or disabled flag.
/// Decorate its real Base root, keeping its native state, focus and actions.
#[derive(IntoElement)]
pub(super) struct AccessibleSelect {
    pub select: Select<Vec<SelectOption>>,
    pub id: String,
    pub disabled: bool,
}

impl Styled for AccessibleSelect {
    fn style(&mut self) -> &mut StyleRefinement {
        self.select.style()
    }
}

impl RenderOnce for AccessibleSelect {
    fn render(self, window: &mut Window, cx: &mut App) -> impl IntoElement {
        // RenderOnce hides the concrete root behind `impl IntoElement`. The
        // source pin and the live/headless tests guard this checked conversion.
        // No memory reinterpretation or copied control implementation is used.
        let root: Box<dyn std::any::Any> =
            Box::new(RenderOnce::render(self.select, window, cx).into_element());
        let root = root
            .downcast::<ViewElement<gpui_kit::base::Select>>()
            .unwrap_or_else(|_| {
                panic!("Pinned GPUI Select root changed; update the accessibility adapter")
            });
        ControlRoot {
            inner: *root,
            decorate: Some(Box::new(move |root| {
                super::semantics::control_properties(root, self.id, self.disabled);
            })),
        }
    }
}

/// Adds structured text to the actual input root. AT-SPI requires TextRun
/// descendants for its Text interface; a scalar aria_value alone is insufficient.
#[derive(IntoElement)]
pub(super) struct AccessibleInput(pub Input, pub FocusHandle);
impl Styled for AccessibleInput {
    fn style(&mut self) -> &mut StyleRefinement {
        self.0.style()
    }
}
impl RenderOnce for AccessibleInput {
    fn render(self, window: &mut Window, cx: &mut App) -> impl IntoElement {
        let root: Box<dyn std::any::Any> =
            Box::new(RenderOnce::render(self.0, window, cx).into_element());
        let mut root = root
            .downcast::<gpui_kit::base::ObservedElement<Stateful<Div>>>()
            .unwrap_or_else(|_| {
                panic!("Pinned Input root changed; update the accessibility adapter")
            });
        super::semantics::input_text(root.interactivity());
        InputFocus {
            inner: *root,
            focus: self.1,
        }
    }
}

type DecorateRoot = Box<dyn FnOnce(&mut Interactivity)>;
struct ControlRoot<E> {
    inner: E,
    decorate: Option<DecorateRoot>,
}

impl<E: Element<RequestLayoutState = Option<AnyElement>>> IntoElement for ControlRoot<E> {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

impl<E: Element<RequestLayoutState = Option<AnyElement>>> Element for ControlRoot<E> {
    type RequestLayoutState = E::RequestLayoutState;
    type PrepaintState = E::PrepaintState;
    fn id(&self) -> Option<ElementId> {
        self.inner.id()
    }
    fn source_location(&self) -> Option<&'static std::panic::Location<'static>> {
        self.inner.source_location()
    }
    fn request_layout(
        &mut self,
        id: Option<&GlobalElementId>,
        inspector: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, Self::RequestLayoutState) {
        let (layout, mut state) = self.inner.request_layout(id, inspector, window, cx);
        let root = state
            .as_mut()
            .and_then(|element| {
                element.downcast_mut::<gpui_kit::base::ObservedElement<Stateful<Div>>>()
            })
            .expect("Pinned Base control element changed; update the accessibility adapter");
        if let Some(decorate) = self.decorate.take() {
            decorate(root.interactivity());
        }
        (layout, state)
    }
    fn prepaint(
        &mut self,
        id: Option<&GlobalElementId>,
        inspector: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        layout: &mut Self::RequestLayoutState,
        window: &mut Window,
        cx: &mut App,
    ) -> Self::PrepaintState {
        self.inner
            .prepaint(id, inspector, bounds, layout, window, cx)
    }
    fn paint(
        &mut self,
        id: Option<&GlobalElementId>,
        inspector: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        layout: &mut Self::RequestLayoutState,
        paint: &mut Self::PrepaintState,
        window: &mut Window,
        cx: &mut App,
    ) {
        self.inner
            .paint(id, inspector, bounds, layout, paint, window, cx);
    }
    fn a11y_role(&self) -> Option<Role> {
        self.inner.a11y_role()
    }
    fn write_a11y_info(&self, node: &mut gpui::accesskit::Node) {
        self.inner.write_a11y_info(node);
    }
    fn a11y_synthetic_children(
        &mut self,
        paint: &mut Self::PrepaintState,
        builder: &mut A11ySubtreeBuilder,
    ) {
        self.inner.a11y_synthetic_children(paint, builder);
    }
}

/// Retain Kit's keyboard tree and tab stops. The semantic node delegates Focus
/// actions and reported focus to the real editing entity through the GPUI seam.
struct InputFocus<E> {
    inner: E,
    focus: FocusHandle,
}
impl<E: Element> IntoElement for InputFocus<E> {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}
impl<E: Element> Element for InputFocus<E> {
    type RequestLayoutState = E::RequestLayoutState;
    type PrepaintState = E::PrepaintState;
    fn id(&self) -> Option<ElementId> {
        self.inner.id()
    }
    fn source_location(&self) -> Option<&'static std::panic::Location<'static>> {
        self.inner.source_location()
    }
    fn request_layout(
        &mut self,
        id: Option<&GlobalElementId>,
        inspector: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, Self::RequestLayoutState) {
        self.inner.request_layout(id, inspector, window, cx)
    }
    fn prepaint(
        &mut self,
        id: Option<&GlobalElementId>,
        inspector: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        layout: &mut Self::RequestLayoutState,
        window: &mut Window,
        cx: &mut App,
    ) -> Self::PrepaintState {
        let state = self
            .inner
            .prepaint(id, inspector, bounds, layout, window, cx);
        if let Some(id) = id {
            window.track_a11y_focus(id, &self.focus);
        }
        state
    }
    fn paint(
        &mut self,
        id: Option<&GlobalElementId>,
        inspector: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        layout: &mut Self::RequestLayoutState,
        paint: &mut Self::PrepaintState,
        window: &mut Window,
        cx: &mut App,
    ) {
        self.inner
            .paint(id, inspector, bounds, layout, paint, window, cx);
    }
    fn a11y_role(&self) -> Option<Role> {
        self.inner.a11y_role()
    }
    fn write_a11y_info(&self, node: &mut gpui::accesskit::Node) {
        self.inner.write_a11y_info(node);
    }
    fn a11y_synthetic_children(
        &mut self,
        paint: &mut Self::PrepaintState,
        builder: &mut A11ySubtreeBuilder,
    ) {
        self.inner.a11y_synthetic_children(paint, builder);
    }
}
