use super::*;
use crate::protocol::{ActionBinding, MenuEntry, MenuSpec};
use gpui_kit::base::GlobalState;
#[cfg(not(target_os = "macos"))]
use gpui_kit::component::menu::AppMenuBar;

#[derive(Clone, PartialEq, serde::Deserialize, Action)]
#[action(namespace = gpuidart, no_json)]
pub(super) struct MenuInvoke {
    pub menu: String,
    pub entry: String,
    pub action: String,
}

pub(super) type AppliedMenus = Option<(Vec<MenuSpec>, Vec<ActionBinding>)>;

fn native_menus(specs: &[MenuSpec]) -> Vec<Menu> {
    specs
        .iter()
        .map(|menu| {
            Menu::new(menu.label.clone()).items(menu.items.iter().map(|item| match item {
                MenuEntry::Separator => MenuItem::separator(),
                MenuEntry::Action {
                    id,
                    label,
                    action,
                    checked,
                    disabled,
                } => MenuItem::Action {
                    name: label.clone().into(),
                    action: Box::new(MenuInvoke {
                        menu: menu.id.clone(),
                        entry: id.clone(),
                        action: action.clone(),
                    }),
                    os_action: None,
                    checked: *checked,
                    disabled: *disabled,
                },
            }))
        })
        .collect()
}

impl DartView {
    pub(super) fn reconcile_menus(&mut self, cx: &mut Context<Self>) -> Result<(), String> {
        if self.applied_menus.as_ref().is_some_and(|(menus, actions)| {
            menus == &self.snapshot.menus && actions == &self.snapshot.actions
        }) {
            return Ok(());
        }
        if self.applied_menus.is_none() && self.snapshot.menus.is_empty() {
            self.applied_menus = Some((vec![], self.snapshot.actions.clone()));
            return Ok(());
        }
        let mut bindings = Vec::new();
        for menu in &self.snapshot.menus {
            for entry in &menu.items {
                if let MenuEntry::Action {
                    id,
                    action,
                    disabled: false,
                    ..
                } = entry
                {
                    let binding = self
                        .snapshot
                        .actions
                        .iter()
                        .find(|a| a.name == *action && a.context == "global")
                        .ok_or_else(|| format!("Missing menu action: {action}"))?;
                    let keys = binding.keys.replace("meta", "cmd").replace('+', "-");
                    bindings.push(
                        KeyBinding::load(
                            &keys,
                            Box::new(MenuInvoke {
                                menu: menu.id.clone(),
                                entry: id.clone(),
                                action: action.clone(),
                            }),
                            None,
                            false,
                            None,
                            &gpui::DummyKeyboardMapper,
                        )
                        .map_err(|e| e.to_string())?,
                    );
                }
            }
        }
        // GPUI exposes whole-keymap replacement. Preserve every foreign binding;
        // replace only this action type, including when menu IDs/shortcuts change.
        let preserved: Vec<_> = cx
            .key_bindings()
            .borrow()
            .bindings()
            .filter(|b| !b.action().as_any().is::<MenuInvoke>())
            .cloned()
            .collect();
        cx.clear_key_bindings();
        cx.bind_keys(preserved.into_iter().chain(bindings));
        cx.set_menus(native_menus(&self.snapshot.menus));
        GlobalState::global_mut(cx).set_app_menus(
            native_menus(&self.snapshot.menus)
                .into_iter()
                .map(Menu::owned)
                .collect(),
        );
        #[cfg(not(target_os = "macos"))]
        if self.snapshot.menus.is_empty() {
            self.menu_bar = None;
        } else if let Some(bar) = &self.menu_bar {
            bar.update(cx, |bar, cx| bar.reload(cx));
        } else {
            self.menu_bar = Some(AppMenuBar::new(cx));
        }
        self.applied_menus = Some((self.snapshot.menus.clone(), self.snapshot.actions.clone()));
        Ok(())
    }

    pub(super) fn invoke_menu(
        &mut self,
        invocation: &MenuInvoke,
        _: &mut Window,
        _: &mut Context<Self>,
    ) {
        let enabled = self.snapshot.menus.iter().find(|m|m.id == invocation.menu)
            .is_some_and(|m|m.items.iter().any(|entry| matches!(entry,
                MenuEntry::Action { id, action, disabled:false, .. } if *id == invocation.entry && *action == invocation.action)));
        if enabled {
            self.events.emit(Event::Action {
                revision: self.snapshot.revision,
                name: invocation.action.clone(),
                context: "global".into(),
            });
        }
    }

    pub(super) fn menu_action_enabled(&self, name: &str) -> bool {
        let mut referenced = false;
        for menu in &self.snapshot.menus {
            for entry in &menu.items {
                if let MenuEntry::Action {
                    action, disabled, ..
                } = entry
                {
                    if action == name {
                        referenced = true;
                        if !disabled {
                            return true;
                        }
                    }
                }
            }
        }
        !referenced
    }
}
