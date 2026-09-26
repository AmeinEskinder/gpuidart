use super::*;
use gpui_kit::base::TestSupportExt;
use gpui_kit::component::slider::{Slider, SliderEvent, SliderState};
use gpui_kit::prelude::FluentBuilder;

pub(super) struct RetainedSlider {
    pub state: Entity<SliderState>,
    pub focus: FocusHandle,
    _subscription: Subscription,
}

impl DartView {
    pub(super) fn reconcile_controls(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let mut sliders = HashSet::new();
        self.snapshot.root.visit(&mut |node| {
            if let Node::Slider {
                id,
                min,
                max,
                step,
                number,
                ..
            } = node
            {
                sliders.insert(id.clone());
                if let Some(retained) = self.sliders.get(id) {
                    retained.state.update(cx, |state, cx| {
                        if (state.min_value(), state.max_value(), state.step_value())
                            != (*min, *max, *step)
                        {
                            *state = slider_state(*min, *max, *step, *number);
                            cx.notify();
                        } else if state.value().start() != *number {
                            state.set_value(*number, window, cx);
                        }
                    });
                } else {
                    let state = cx.new(|_| slider_state(*min, *max, *step, *number));
                    let event_id = id.clone();
                    let subscription =
                        cx.subscribe_in(&state, window, move |this, state, event, window, cx| {
                            if let SliderEvent::Change(value) = event {
                                // Kit rounds pointer values to multiples of step. A range endpoint
                                // need not be on that grid; keep the host's bounds authoritative.
                                let slider = state.read(cx);
                                let number =
                                    value.start().clamp(slider.min_value(), slider.max_value());
                                if number != value.start() {
                                    state.update(cx, |state, cx| {
                                        state.set_value(number, window, cx)
                                    });
                                }
                                this.events.emit(Event::SliderChange {
                                    revision: this.snapshot.revision,
                                    id: event_id.clone(),
                                    number,
                                });
                            }
                        });
                    self.sliders.insert(
                        id.clone(),
                        RetainedSlider {
                            state,
                            focus: cx.focus_handle().tab_stop(true),
                            _subscription: subscription,
                        },
                    );
                }
            }
        });
        self.sliders.retain(|id, _| sliders.contains(id));
    }

    pub(super) fn inspect_controls(&self, window: &Window, cx: &App) -> Value {
        self.sliders.iter().map(|(id, retained)| (id.clone(), json!({
            "kind":"slider", "number":retained.state.read(cx).value().start(),
            "entity":retained.state.entity_id().as_u64(), "focused":retained.focus.is_focused(window),
        }))).collect::<serde_json::Map<_, _>>().into()
    }

    pub(super) fn slider_element(
        &self,
        node: &Node,
        colors: &ThemeColor,
    ) -> Result<AnyElement, String> {
        let Node::Slider { id, disabled, .. } = node else {
            return Err("Slider materializer received a different node kind".into());
        };
        let retained = self
            .sliders
            .get(id)
            .ok_or_else(|| format!("Missing retained slider: {id}"))?;
        let state = retained.state.clone();
        let focus = retained.focus.clone();
        let events = self.events.clone();
        let id = id.clone();
        let revision = self.snapshot.revision;
        let element = div()
            .id(SharedString::from(id.clone()))
            .test_support()
            .w_full()
            .py_2()
            .border_1()
            .border_color(rgba(0x00000000))
            .when(!*disabled, |this| {
                this.track_focus(&focus)
                    .focus_visible(|style| style.border_color(colors.primary))
                    .on_mouse_down(MouseButton::Left, {
                        let focus = focus.clone();
                        move |_, window, cx| focus.focus(window, cx)
                    })
                    .on_key_down(move |event, window, cx| {
                        if event.keystroke.modifiers != Modifiers::default() {
                            return;
                        }
                        let slider = state.read(cx);
                        let old = slider.value().start();
                        let next = match event.keystroke.key.as_str() {
                            "left" | "down" => old - slider.step_value(),
                            "right" | "up" => old + slider.step_value(),
                            "home" => slider.min_value(),
                            "end" => slider.max_value(),
                            _ => return,
                        }
                        .clamp(slider.min_value(), slider.max_value());
                        if next != old {
                            state.update(cx, |state, cx| state.set_value(next, window, cx));
                            events.emit(Event::SliderChange {
                                revision,
                                id: id.clone(),
                                number: next,
                            });
                        }
                        window.prevent_default();
                        cx.stop_propagation();
                    })
            })
            .child(
                Slider::new(&retained.state)
                    .disabled(*disabled)
                    .w_full()
                    .when_some(
                        node.style().and_then(|style| style.background),
                        |slider, color| slider.bg(resolve_color(color, colors)),
                    )
                    .when_some(
                        node.style().and_then(|style| style.foreground),
                        |slider, color| slider.text_color(resolve_color(color, colors)),
                    ),
            );
        Ok(apply_node_style(element, node, colors).into_any_element())
    }
}

fn slider_state(min: f32, max: f32, step: f32, number: f32) -> SliderState {
    SliderState::new()
        .min(min)
        .max(max)
        .step(step)
        .default_value(number)
}
