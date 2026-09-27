use super::*;
use crate::protocol::ChoiceOption;
use gpui_kit::base::{Radio, Tab};

#[derive(Clone, Copy, PartialEq)]
enum ChoiceKind {
    Tabs,
    Radio,
}

fn spec(node: &Node) -> Option<(ChoiceKind, &String, &[ChoiceOption], &String, bool)> {
    match node {
        Node::Tabs {
            id,
            options,
            selected,
            disabled,
            ..
        } => Some((ChoiceKind::Tabs, id, options, selected, *disabled)),
        Node::RadioGroup {
            id,
            options,
            selected,
            disabled,
            ..
        } => Some((ChoiceKind::Radio, id, options, selected, *disabled)),
        _ => None,
    }
}

pub(super) struct RetainedChoices {
    pub focus: HashMap<String, FocusHandle>,
    roving: String,
    kind: ChoiceKind,
}

impl DartView {
    pub(super) fn reconcile_choices(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let mut mounted = HashSet::new();
        self.snapshot.root.visit(&mut |node| {
            let Some((kind, id, options, selected, disabled)) = spec(node) else {
                return;
            };
            mounted.insert(id.clone());
            if self.choices.get(id).is_some_and(|r| r.kind != kind) {
                if self.choices[id]
                    .focus
                    .values()
                    .any(|f| f.is_focused(window))
                {
                    window.blur(cx);
                }
                self.choices.remove(id);
            }
            let retained = self
                .choices
                .entry(id.clone())
                .or_insert_with(|| RetainedChoices {
                    focus: HashMap::new(),
                    roving: selected.clone(),
                    kind,
                });
            let had_focus = retained.focus.values().any(|f| f.is_focused(window));
            let focused = retained
                .focus
                .iter()
                .find(|(_, f)| f.is_focused(window))
                .map(|(id, _)| id.clone());
            retained
                .focus
                .retain(|id, _| options.iter().any(|o| o.id == *id));
            for option in options {
                retained
                    .focus
                    .entry(option.id.clone())
                    .or_insert_with(|| cx.focus_handle());
            }
            if !options
                .iter()
                .any(|o| o.id == retained.roving && !o.disabled)
                || !had_focus
            {
                retained.roving = selected.clone();
            }
            if had_focus {
                if disabled {
                    window.blur(cx);
                } else if !options
                    .iter()
                    .any(|o| Some(&o.id) == focused.as_ref() && !o.disabled)
                {
                    if let Some(focus) = retained.focus.get(&retained.roving) {
                        focus.focus(window, cx);
                    }
                }
            }
            for (key, focus) in &mut retained.focus {
                *focus = focus.clone().tab_stop(!disabled && *key == retained.roving);
            }
        });
        self.choices.retain(|id, _| mounted.contains(id));
    }

    pub(super) fn choice_input(
        &mut self,
        id: &str,
        option: &str,
        generation: &FocusHandle,
        key: Option<&str>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> bool {
        let Some((kind, _, options, selected, false)) = self.snapshot.root.find(id).and_then(spec)
        else {
            return false;
        };
        let Some(retained) = self.choices.get_mut(id) else {
            return false;
        };
        if retained.focus.get(option) != Some(generation) {
            return false;
        }
        let enabled: Vec<_> = options
            .iter()
            .filter(|o| !o.disabled)
            .map(|o| o.id.as_str())
            .collect();
        let Some(index) = enabled.iter().position(|o| *o == option) else {
            return false;
        };
        if kind == ChoiceKind::Tabs && matches!(key, Some("up" | "down")) {
            return false;
        }
        let (target, activate) = match key {
            None | Some("enter" | "space") => (index, true),
            Some("left" | "up") => (
                (index + enabled.len() - 1) % enabled.len(),
                kind == ChoiceKind::Radio,
            ),
            Some("right" | "down") => ((index + 1) % enabled.len(), kind == ChoiceKind::Radio),
            Some("home") => (0, kind == ChoiceKind::Radio),
            Some("end") => (enabled.len() - 1, kind == ChoiceKind::Radio),
            _ => return false,
        };
        retained.roving = enabled[target].to_owned();
        for (key, focus) in &mut retained.focus {
            *focus = focus.clone().tab_stop(*key == retained.roving);
            if *key == retained.roving {
                focus.focus(window, cx);
            }
        }
        if activate && (kind == ChoiceKind::Tabs || retained.roving != *selected) {
            let revision = self.snapshot.revision;
            let id = id.to_owned();
            let selected = retained.roving.clone();
            self.events.emit(match kind {
                ChoiceKind::Tabs => Event::TabChange {
                    revision,
                    id,
                    selected,
                },
                ChoiceKind::Radio => Event::RadioChange {
                    revision,
                    id,
                    selected,
                },
            });
        }
        cx.notify();
        true
    }

    pub(super) fn choices_element(
        &self,
        node: &Node,
        colors: &ThemeColor,
        cx: &Context<Self>,
    ) -> Result<AnyElement, String> {
        let Some((kind, id, options, selected, disabled)) = spec(node) else {
            return Err("Choice materializer received a different node kind".into());
        };
        let retained = self
            .choices
            .get(id)
            .ok_or_else(|| format!("Missing retained tabs: {id}"))?;
        let mut children = Vec::with_capacity(options.len());
        for (index, option) in options.iter().enumerate() {
            let focus = retained
                .focus
                .get(&option.id)
                .ok_or_else(|| format!("Missing tab focus: {}", option.id))?;
            let key = json!([
                id,
                if kind == ChoiceKind::Tabs {
                    "tab"
                } else {
                    "radio"
                },
                option.id
            ])
            .to_string();
            let activate = cx.listener({
                let id = id.clone();
                let option = option.id.clone();
                let focus = focus.clone();
                move |this, _: &ClickEvent, window, cx| {
                    this.choice_input(&id, &option, &focus, None, window, cx);
                }
            });
            let key_down = cx.listener({
                let id = id.clone();
                let option = option.id.clone();
                let focus = focus.clone();
                move |this, event: &KeyDownEvent, window, cx| {
                    if event.keystroke.modifiers == Modifiers::default()
                        && this.choice_input(
                            &id,
                            &option,
                            &focus,
                            Some(&event.keystroke.key),
                            window,
                            cx,
                        )
                    {
                        window.prevent_default();
                        cx.stop_propagation();
                    }
                }
            });
            let inactive = disabled || option.disabled;
            let selected = option.id == *selected;
            let element = match kind {
                ChoiceKind::Tabs => Tab::new(SharedString::from(key.clone()))
                    .accessibility_id(key)
                    .accessibility_label(option.label.clone())
                    .set_position(index + 1, options.len())
                    .selected(selected)
                    .disabled(inactive)
                    .on_click(activate)
                    .track_focus(focus)
                    .on_key_down(key_down)
                    .focus(|style| style.border_color(colors.ring).bg(colors.accent))
                    .a11y_synthetic_children(move |tree| {
                        if inactive {
                            tree.parent_node().set_disabled();
                        }
                    })
                    .px_4()
                    .py_2()
                    .border_b_2()
                    .border_color(if selected {
                        colors.primary
                    } else {
                        colors.border
                    })
                    .bg(if selected {
                        colors.accent
                    } else {
                        colors.background
                    })
                    .text_color(if inactive {
                        colors.muted_foreground
                    } else {
                        colors.foreground
                    })
                    .child(option.label.clone())
                    .into_any_element(),
                ChoiceKind::Radio => Radio::new(SharedString::from(key.clone()))
                    .accessibility_id(key)
                    .accessibility_label(option.label.clone())
                    .set_position(index + 1, options.len())
                    .checked(selected)
                    .disabled(inactive)
                    .on_change(move |_, event, window, cx| activate(event, window, cx))
                    .track_focus(focus)
                    .tab_stop(option.id == retained.roving && !inactive)
                    .on_key_down(key_down)
                    .focus(|style| style.border_color(colors.ring).bg(colors.accent))
                    .a11y_synthetic_children(move |tree| {
                        if inactive {
                            tree.parent_node().set_disabled();
                        }
                    })
                    .flex()
                    .items_center()
                    .gap_2()
                    .border_1()
                    .border_color(colors.background)
                    .px_2()
                    .py_2()
                    .text_color(if inactive {
                        colors.muted_foreground
                    } else {
                        colors.foreground
                    })
                    .child(
                        div()
                            .size_4()
                            .rounded_full()
                            .border_1()
                            .border_color(colors.border)
                            .bg(if selected {
                                colors.primary
                            } else {
                                colors.background
                            }),
                    )
                    .child(option.label.clone())
                    .into_any_element(),
            };
            children.push(element);
        }
        Ok(apply_node_style(
            div()
                .id(SharedString::from(id.clone()))
                .test_support()
                .role(if kind == ChoiceKind::Tabs {
                    Role::TabList
                } else {
                    Role::RadioGroup
                })
                .aria_label(accessible_name(node))
                .accessibility_id(id.clone())
                .flex()
                .flex_row()
                .flex_wrap()
                .children(children),
            node,
            colors,
        )
        .into_any_element())
    }
}
