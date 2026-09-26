use super::*;
use gpui_kit::base::{SliderIndicator, SliderThumb, SliderTrack};
use gpui_kit::component::slider::SliderState;

/// Kit's track/thumb behavior with a host-owned semantic root. The pinned
/// Component Slider owns an inaccessible unnamed root and cannot forward the
/// host's focus, disabled state or SetValue action to it.
#[derive(IntoElement)]
pub(super) struct SliderPresentation {
    state: Entity<SliderState>,
    style: StyleRefinement,
    disabled: bool,
}

impl SliderPresentation {
    pub(super) fn new(state: &Entity<SliderState>) -> Self {
        Self {
            state: state.clone(),
            style: StyleRefinement::default(),
            disabled: false,
        }
    }
    pub(super) fn disabled(mut self, disabled: bool) -> Self {
        self.disabled = disabled;
        self
    }
}

impl Styled for SliderPresentation {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for SliderPresentation {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let position = self.state.read(cx).percentage().end;
        let color = self
            .style
            .background
            .as_ref()
            .and_then(|bg| bg.color())
            .unwrap_or(cx.theme().tokens.slider_bar.into());
        let thumb_color = self
            .style
            .text
            .color
            .unwrap_or(cx.theme().tokens.slider_thumb.into());
        SliderTrack::new(&self.state)
            .disabled(self.disabled)
            .flex()
            .items_center()
            .h_6()
            .w_full()
            .child(
                SliderIndicator::new(&self.state)
                    .relative()
                    .w_full()
                    .h_1p5()
                    .rounded_full()
                    .bg(color.opacity(0.2))
                    .child(
                        div()
                            .absolute()
                            .h_full()
                            .left_0()
                            .right(relative(1. - position))
                            .rounded_full()
                            .bg(color),
                    )
                    .child(
                        SliderThumb::new(&self.state)
                            .disabled(self.disabled)
                            .absolute()
                            .top(px(-5.))
                            .left(relative(position))
                            .ml(-px(8.))
                            .size_4()
                            .rounded_full()
                            .border_1()
                            .border_color(cx.theme().border)
                            .bg(thumb_color),
                    ),
            )
    }
}
