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
        SelectRoot {
            inner: *root,
            id: self.id,
            disabled: self.disabled,
        }
    }
}

struct SelectRoot<E> {
    inner: E,
    id: String,
    disabled: bool,
}

impl<E: Element<RequestLayoutState = Option<AnyElement>>> IntoElement for SelectRoot<E> {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

impl<E: Element<RequestLayoutState = Option<AnyElement>>> Element for SelectRoot<E> {
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
            .expect("Pinned Base Select element changed; update the accessibility adapter");
        let disabled = self.disabled;
        super::semantics::control_properties(root.interactivity(), self.id.clone(), disabled);
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
