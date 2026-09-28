use super::*;
use crate::protocol::MenuEntry;
use gpui_kit::component::menu::{PopupMenu, PopupMenuItem};

#[derive(Clone)]
struct Target {
    table: String,
    entity: EntityId,
    data: SharedDataset,
    generation: u64,
    source: usize,
    record: String,
}

pub(super) struct Session {
    serial: u64,
    target: Target,
    entries: Vec<MenuEntry>,
    menu: Entity<PopupMenu>,
    position: Point<Pixels>,
    restore: FocusHandle,
    focus: FocusHandle,
    _subscription: Subscription,
}

impl Rows {
    pub(super) fn context_row(
        &self,
        row: Stateful<Div>,
        source: usize,
        cx: &Context<TableState<Self>>,
    ) -> Stateful<Div> {
        if !self.has_context_menu {
            return row;
        }
        let data = self.data.borrow();
        let Some(record) = data
            .data
            .ids
            .as_ref()
            .and_then(|ids| ids.get(source))
            .cloned()
        else {
            return row;
        };
        let target = Target {
            table: self.table_id.clone(),
            entity: cx.entity().entity_id(),
            data: self.data.clone(),
            generation: data.generation,
            source,
            record,
        };
        let owner = self.owner.clone();
        row.capture_any_mouse_down(move |event, window, cx| {
            if event.button != MouseButton::Right {
                return;
            }
            let _ = owner.update(cx, |view, cx| {
                view.open_row_menu(target.clone(), event.position, window, cx)
            });
            window.prevent_default();
            cx.stop_propagation();
        })
    }
}

impl DartView {
    fn valid_row_target(&self, target: &Target, cx: &App) -> bool {
        let Some(table) = self.tables.get(&target.table) else {
            return false;
        };
        if table.state.entity_id() != target.entity
            || !Rc::ptr_eq(&table.state.read(cx).delegate().data, &target.data)
        {
            return false;
        }
        let data = target.data.borrow();
        data.generation == target.generation
            && data
                .data
                .ids
                .as_ref()
                .and_then(|ids| ids.get(target.source))
                == Some(&target.record)
    }

    fn current_row_entries(&self, id: &str) -> Option<&[MenuEntry]> {
        match self.snapshot.root.find(id) {
            Some(Node::Table { context_menu, .. }) if !context_menu.is_empty() => {
                Some(context_menu)
            }
            _ => None,
        }
    }

    fn open_row_menu(
        &mut self,
        target: Target,
        position: Point<Pixels>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> bool {
        if !self.valid_row_target(&target, cx) {
            return false;
        }
        let Some(entries) = self.current_row_entries(&target.table).map(<[_]>::to_vec) else {
            return false;
        };
        self.close_row_menu(window, cx);
        let Some(table) = self.tables.get(&target.table) else {
            return false;
        };
        let restore = table.state.read(cx).focus_handle(cx);
        restore.focus(window, cx);
        self.next_row_menu += 1;
        let serial = self.next_row_menu;
        let owner = cx.entity().downgrade();
        let menu = PopupMenu::build(window, cx, |mut menu, _, _| {
            menu = menu.action_context(restore.clone());
            for entry in &entries {
                menu = menu.item(match entry {
                    MenuEntry::Separator => PopupMenuItem::separator(),
                    MenuEntry::Action {
                        id,
                        label,
                        action,
                        checked,
                        disabled,
                    } => {
                        let (id, action, owner) = (id.clone(), action.clone(), owner.clone());
                        PopupMenuItem::new(label.clone())
                            .checked(*checked)
                            .disabled(*disabled)
                            .on_click(move |_, window, cx| {
                                let _ = owner.update(cx, |view, cx| {
                                    view.invoke_row_menu(serial, &id, &action, window, cx)
                                });
                            })
                    }
                });
            }
            menu
        });
        let focus = menu.read(cx).focus_handle(cx);
        let subscription = cx.subscribe_in(
            &menu,
            window,
            move |this, _, _: &DismissEvent, window, cx| {
                if this.row_menu.as_ref().is_some_and(|s| s.serial == serial) {
                    this.close_row_menu(window, cx);
                }
            },
        );
        focus.focus(window, cx);
        self.row_menu = Some(Session {
            serial,
            target,
            entries,
            menu,
            position,
            restore,
            focus,
            _subscription: subscription,
        });
        cx.notify();
        true
    }

    fn invoke_row_menu(
        &mut self,
        serial: u64,
        entry: &str,
        action: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(session) = self.row_menu.as_ref().filter(|s| s.serial == serial) else {
            return;
        };
        let enabled = self
            .current_row_entries(&session.target.table)
            .is_some_and(|items| {
                items.iter().any(|item| {
                    matches!(item,
                MenuEntry::Action { id, action: current, disabled: false, .. }
                    if id == entry && current == action)
                })
            });
        if enabled && self.valid_row_target(&session.target, cx) {
            let data = session.target.data.borrow();
            self.events.emit(Event::RowAction {
                revision: self.snapshot.revision,
                id: session.target.table.clone(),
                dataset: data.id.clone(),
                dataset_revision: data.revision,
                record: session.target.record.clone(),
                action: action.to_owned(),
            });
        }
        self.close_row_menu(window, cx);
    }

    fn close_row_menu(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(session) = self.row_menu.take() {
            if session.focus.contains_focused(window, cx) {
                if self
                    .tables
                    .get(&session.target.table)
                    .is_some_and(|table| table.state.entity_id() == session.target.entity)
                {
                    session.restore.focus(window, cx);
                } else {
                    window.blur(cx);
                }
            }
            cx.notify();
        }
    }

    pub(super) fn reconcile_row_menu(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.row_menu.as_ref().is_some_and(|s| {
            !self.valid_row_target(&s.target, cx)
                || self.current_row_entries(&s.target.table) != Some(s.entries.as_slice())
        }) {
            self.close_row_menu(window, cx);
        }
    }

    pub(super) fn keyboard_row_menu(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> bool {
        let target = self.tables.iter().find_map(|(id, table)| {
            let state = table.state.read(cx);
            if !state.focus_handle(cx).is_focused(window) {
                return None;
            }
            let source = match *state
                .delegate()
                .index
                .borrow()
                .entries
                .get(state.selected_row()?)?
            {
                crate::protocol::ViewEntry::Record(source) => source,
                crate::protocol::ViewEntry::Group(_) => return None,
            };
            let data = state.delegate().data.borrow();
            Some(Target {
                table: id.clone(),
                entity: table.state.entity_id(),
                data: state.delegate().data.clone(),
                generation: data.generation,
                source,
                record: data.data.ids.as_ref()?.get(source)?.clone(),
            })
        });
        let Some(target) = target else {
            return false;
        };
        let viewport = window.viewport_size();
        self.open_row_menu(
            target,
            point(viewport.width / 2., viewport.height / 2.),
            window,
            cx,
        )
    }

    pub(super) fn row_menu_element(&self) -> Option<AnyElement> {
        self.row_menu.as_ref().map(|session| {
            deferred(
                anchored()
                    .position(session.position)
                    .snap_to_window_with_margin(px(8.))
                    .child(div().occlude().child(session.menu.clone())),
            )
            .with_priority(gpui_kit::base::POPUP_PRIORITY)
            .into_any_element()
        })
    }
}

#[cfg(test)]
mod tests;
