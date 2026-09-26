use super::*;
use gpui_kit::base::Tab;

pub(super) struct RetainedTabs {
    pub focus: HashMap<String, FocusHandle>,
    roving: String,
}

impl DartView {
    pub(super) fn reconcile_tabs(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let mut mounted = HashSet::new();
        self.snapshot.root.visit(&mut |node| {
            let Node::Tabs {
                id,
                options,
                selected,
                disabled,
                ..
            } = node
            else {
                return;
            };
            mounted.insert(id.clone());
            let retained = self.tabs.entry(id.clone()).or_insert_with(|| RetainedTabs {
                focus: HashMap::new(),
                roving: selected.clone(),
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
                if *disabled {
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
        self.tabs.retain(|id, _| mounted.contains(id));
    }

    pub(super) fn tab_input(
        &mut self,
        id: &str,
        option: &str,
        generation: &FocusHandle,
        key: Option<&str>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> bool {
        let mut spec = None;
        self.snapshot.root.visit(&mut |node| {
            if matches!(node, Node::Tabs { id: current, .. } if current == id) {
                spec = Some(node.clone());
            }
        });
        let Some(Node::Tabs {
            options,
            disabled: false,
            ..
        }) = spec
        else {
            return false;
        };
        let Some(retained) = self.tabs.get_mut(id) else {
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
        let (target, activate) = match key {
            None | Some("enter" | "space") => (index, true),
            Some("left") => ((index + enabled.len() - 1) % enabled.len(), false),
            Some("right") => ((index + 1) % enabled.len(), false),
            Some("home") => (0, false),
            Some("end") => (enabled.len() - 1, false),
            _ => return false,
        };
        retained.roving = enabled[target].to_owned();
        for (key, focus) in &mut retained.focus {
            *focus = focus.clone().tab_stop(*key == retained.roving);
            if *key == retained.roving {
                focus.focus(window, cx);
            }
        }
        if activate {
            self.events.emit(Event::TabChange {
                revision: self.snapshot.revision,
                id: id.to_owned(),
                selected: retained.roving.clone(),
            });
        }
        cx.notify();
        true
    }

    pub(super) fn tabs_element(
        &self,
        node: &Node,
        colors: &ThemeColor,
        cx: &Context<Self>,
    ) -> Result<AnyElement, String> {
        let Node::Tabs {
            id,
            options,
            selected,
            disabled,
            ..
        } = node
        else {
            return Err("Tab materializer received a different node kind".into());
        };
        let retained = self
            .tabs
            .get(id)
            .ok_or_else(|| format!("Missing retained tabs: {id}"))?;
        let mut children = Vec::with_capacity(options.len());
        for (index, option) in options.iter().enumerate() {
            let focus = retained
                .focus
                .get(&option.id)
                .ok_or_else(|| format!("Missing tab focus: {}", option.id))?;
            let key = json!([id, "tab", option.id]).to_string();
            let activate = cx.listener({
                let id = id.clone();
                let option = option.id.clone();
                let focus = focus.clone();
                move |this, _: &ClickEvent, window, cx| {
                    this.tab_input(&id, &option, &focus, None, window, cx);
                }
            });
            let key_down = cx.listener({
                let id = id.clone();
                let option = option.id.clone();
                let focus = focus.clone();
                move |this, event: &KeyDownEvent, window, cx| {
                    if event.keystroke.modifiers == Modifiers::default()
                        && this.tab_input(
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
            let inactive = *disabled || option.disabled;
            children.push(
                Tab::new(SharedString::from(key.clone()))
                    .accessibility_id(key)
                    .accessibility_label(option.label.clone())
                    .set_position(index + 1, options.len())
                    .selected(option.id == *selected)
                    .disabled(inactive)
                    .on_click(activate)
                    .track_focus(focus)
                    .on_key_down(key_down)
                    .a11y_synthetic_children(move |tree| {
                        if inactive {
                            tree.parent_node().set_disabled();
                        }
                    })
                    .px_4()
                    .py_2()
                    .border_b_2()
                    .border_color(if option.id == *selected {
                        colors.primary
                    } else {
                        colors.border
                    })
                    .bg(if option.id == *selected {
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
            );
        }
        Ok(apply_node_style(
            div()
                .id(SharedString::from(id.clone()))
                .test_support()
                .role(Role::TabList)
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
