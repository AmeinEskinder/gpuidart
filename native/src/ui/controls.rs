use super::control_root::AccessibleSelect;
use super::slider::SliderPresentation;
use super::*;
use crate::protocol::SelectOption;
use gpui_kit::base::TestSupportExt;
use gpui_kit::component::slider::{SliderEvent, SliderState};
use gpui_kit::component::{
    IndexPath,
    select::{Select, SelectEvent, SelectItem, SelectState},
};
use gpui_kit::prelude::FluentBuilder;

pub(super) struct RetainedSlider {
    pub state: Entity<SliderState>,
    pub focus: FocusHandle,
    _subscription: Subscription,
}

pub(super) struct RetainedSelect {
    pub state: Entity<SelectState<Vec<SelectOption>>>,
    options: Vec<SelectOption>,
    disabled: bool,
    _subscription: Subscription,
}

impl SelectItem for SelectOption {
    type Value = String;
    fn title(&self) -> SharedString {
        self.label.clone().into()
    }
    fn value(&self) -> &String {
        &self.id
    }
}

impl DartView {
    pub(super) fn reconcile_controls(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.reconcile_selects(window, cx);
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
        let mut controls = self.sliders.iter().map(|(id, retained)| (id.clone(), json!({
            "kind":"slider", "number":retained.state.read(cx).value().start(),
            "entity":retained.state.entity_id().as_u64(), "focused":retained.focus.is_focused(window),
        }))).collect::<serde_json::Map<_, _>>();
        for (id, retained) in &self.selects {
            let state = retained.state.read(cx);
            controls.insert(id.clone(), json!({"kind":"select", "selected":state.selected_value(),
                "entity":retained.state.entity_id().as_u64(), "focused":state.focus_handle(cx).is_focused(window)}));
        }
        self.snapshot.root.visit(&mut |node| {
            if let Node::Checkbox { id, checked, disabled, .. } = node {
                let shown = self.checkbox_shown.borrow().get(id).copied().unwrap_or(*checked);
                controls.insert(id.clone(),json!({"kind":"checkbox","checked":shown,"published":checked,"disabled":disabled}));
            }
            if let Node::Switch { id, checked, disabled, .. } = node {
                let shown = self.checkbox_shown.borrow().get(id).copied().unwrap_or(*checked);
                controls.insert(id.clone(),json!({"kind":"switch","checked":shown,"published":checked,"disabled":disabled}));
            }
            if let Node::RadioGroup { id, selected, disabled, .. } = node {
                let shown = self.choice_shown.borrow().get(id).cloned().or_else(|| selected.clone());
                controls.insert(id.clone(),json!({"kind":"radio_group","selected":shown,"published":selected,"disabled":disabled}));
            }
            if let Node::Progress { id, value, .. } = node {
                controls.insert(id.clone(),json!({"kind":"progress","value":value}));
            }
            if let Node::Tabs { id, selected, .. } = node {
                let shown = self.choice_shown.borrow().get(id).cloned().unwrap_or_else(|| selected.clone());
                controls.insert(id.clone(),json!({"kind":"tabs","selected":shown,"published":selected}));
            }
            if let Node::ConfirmDialog { id, disabled, .. } = node {
                controls.insert(id.clone(),json!({"kind":"confirm_dialog","disabled":disabled,
                    "open":self.active_dialog.borrow().as_ref().is_some_and(|session|session.id == *id)}));
            }
        });
        controls.into()
    }

    fn reconcile_selects(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let mut ids = HashSet::new();
        self.snapshot.root.visit(&mut |node| {
            let Node::Select {
                id,
                options,
                selected,
                disabled,
                ..
            } = node
            else {
                return;
            };
            ids.insert(id.clone());
            let selected_index = selected
                .as_ref()
                .and_then(|id| options.iter().position(|o| o.id == *id))
                .map(|row| IndexPath::default().row(row));
            if let Some(retained) = self.selects.get_mut(id) {
                if *disabled
                    && !retained.disabled
                    && retained.state.read(cx).focus_handle(cx).is_focused(window)
                {
                    // Blur alone can be undone by the open popover restoring
                    // its focus during the next render. Use its native cancel
                    // action so selection and menu state close together.
                    retained.state.read(cx).focus_handle(cx).dispatch_action(
                        &gpui_kit::base::actions::Cancel,
                        window,
                        cx,
                    );
                }
                retained.disabled = *disabled;
                let changed = retained.options != *options;
                if changed || retained.state.read(cx).selected_value() != selected.as_ref() {
                    retained.state.update(cx, |state, cx| {
                        if changed {
                            state.set_items(options.clone(), window, cx);
                        }
                        state.set_selected_index(selected_index, window, cx);
                        cx.notify();
                    });
                    retained.options = options.clone();
                }
            } else {
                let state =
                    cx.new(|cx| SelectState::new(options.clone(), selected_index, window, cx));
                let event_id = id.clone();
                let subscription = cx.subscribe(
                    &state,
                    move |this, _, event: &SelectEvent<Vec<SelectOption>>, _| {
                        let SelectEvent::Confirm(selected) = event;
                        this.events.emit(Event::SelectChange {
                            revision: this.snapshot.revision,
                            id: event_id.clone(),
                            selected: selected.clone(),
                        });
                    },
                );
                self.selects.insert(
                    id.clone(),
                    RetainedSelect {
                        state,
                        options: options.clone(),
                        disabled: *disabled,
                        _subscription: subscription,
                    },
                );
            }
        });
        self.selects.retain(|id, _| ids.contains(id));
    }

    pub(super) fn select_element(
        &self,
        node: &Node,
        colors: &ThemeColor,
    ) -> Result<AnyElement, String> {
        let Node::Select {
            id,
            disabled,
            placeholder,
            ..
        } = node
        else {
            return Err("Select materializer received a different node kind".into());
        };
        let retained = self
            .selects
            .get(id)
            .ok_or_else(|| format!("Missing retained select: {id}"))?;
        // Kit sizes the select's outer trigger to its parent, while Styled
        // applies to the inner input. Constrain the parent too, so the node's
        // hit target and declared width describe the same control.
        Ok(div()
            .id(SharedString::from(id.clone()))
            .test_support()
            .w_full()
            .when_some(node.style().and_then(|s| s.width), |this, width| {
                this.w(style_length(width))
            })
            .when_some(node.style().and_then(|s| s.height), |this, height| {
                this.h(style_length(height))
            })
            .child(apply_node_style(
                AccessibleSelect {
                    select: Select::new(&retained.state)
                        .accessibility_label(accessible_name(node))
                        .placeholder(placeholder.clone())
                        .disabled(*disabled),
                    id: id.clone(),
                    disabled: *disabled,
                },
                node,
                colors,
            ))
            .into_any_element())
    }

    pub(super) fn slider_element(
        &self,
        node: &Node,
        colors: &ThemeColor,
        cx: &App,
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
        let slider = retained.state.read(cx);
        let element = annotate(div().id(SharedString::from(id.clone())), node)
            .aria_numeric_value(slider.value().start() as f64)
            .aria_min_numeric_value(slider.min_value() as f64)
            .aria_max_numeric_value(slider.max_value() as f64)
            .aria_numeric_value_step(slider.step_value() as f64)
            .aria_orientation(gpui::accesskit::Orientation::Horizontal)
            .a11y_synthetic_children({
                let disabled = *disabled;
                move |tree| {
                    if disabled {
                        tree.parent_node().set_disabled();
                    }
                }
            })
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
            .when(!*disabled, |this| {
                let mut this = this;
                for action in [
                    AccessibleAction::SetValue,
                    AccessibleAction::Increment,
                    AccessibleAction::Decrement,
                ] {
                    let state = retained.state.clone();
                    this = this.on_a11y_action(action, move |data, window, cx| {
                        state.update(cx, |state, cx| {
                            let old = state.value().start();
                            let next = match action {
                                AccessibleAction::Increment => old + state.step_value(),
                                AccessibleAction::Decrement => old - state.step_value(),
                                AccessibleAction::SetValue => match data {
                                    Some(gpui::accesskit::ActionData::NumericValue(value))
                                        if value.is_finite() =>
                                    {
                                        *value as f32
                                    }
                                    _ => return,
                                },
                                _ => return,
                            };
                            if !next.is_finite() {
                                return;
                            }
                            let next = next.clamp(state.min_value(), state.max_value());
                            if next != old {
                                state.set_value(next, window, cx);
                                cx.emit(SliderEvent::Change(state.value()));
                            }
                        });
                    });
                }
                this.on_mouse_up(MouseButton::Left, window_release(retained.state.clone()))
                    .on_mouse_up_out(MouseButton::Left, window_release(retained.state.clone()))
            })
            .child(
                SliderPresentation::new(&retained.state)
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

fn window_release(state: Entity<SliderState>) -> impl Fn(&MouseUpEvent, &mut Window, &mut App) {
    move |_, _, cx| state.update(cx, |state, cx| state.handle_release(cx))
}
