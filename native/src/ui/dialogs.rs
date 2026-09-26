use super::*;
use gpui_kit::base::TestSupportExt;
use gpui_kit::component::WindowExt;
use std::cell::Cell;

pub(super) type ActiveDialog = Rc<RefCell<Option<Rc<Session>>>>;

pub(super) struct Session {
    pub id: String,
    revision: u64,
    confirmed: Cell<bool>,
    closed: Cell<bool>,
}

fn finish(active: &ActiveDialog, session: &Rc<Session>, events: &Events) {
    if session.closed.replace(true) {
        return;
    }
    if active
        .borrow()
        .as_ref()
        .is_some_and(|current| Rc::ptr_eq(current, session))
    {
        active.borrow_mut().take();
    }
    events.emit(Event::DialogResult {
        revision: session.revision,
        id: session.id.clone(),
        confirmed: session.confirmed.get(),
    });
}

impl DartView {
    pub(super) fn reconcile_dialog(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(session) = self.active_dialog.borrow().clone() else {
            return;
        };
        let mut mounted = false;
        self.snapshot.root.visit(&mut |node| {
            if let Node::ConfirmDialog {
                id,
                disabled: false,
                ..
            } = node
            {
                mounted |= *id == session.id;
            }
        });
        if !mounted {
            finish(&self.active_dialog, &session, &self.events);
            window.close_dialog(cx);
        }
    }

    pub(super) fn dialog_element(
        &self,
        node: &Node,
        colors: &ThemeColor,
    ) -> Result<AnyElement, String> {
        let Node::ConfirmDialog {
            id,
            label,
            title,
            message,
            confirm_label,
            cancel_label,
            disabled,
            ..
        } = node
        else {
            return Err("Dialog materializer received a different node kind".into());
        };
        let (id, title, message, confirm_label, cancel_label) = (
            id.clone(),
            title.clone(),
            message.clone(),
            confirm_label.clone(),
            cancel_label.clone(),
        );
        let active = self.active_dialog.clone();
        let events = self.events.clone();
        let revision = self.snapshot.revision;
        Ok(apply_node_style(
            super::semantics::control(Button::new(SharedString::from(id.clone())), node, *disabled)
                .accessibility_id(id.clone())
                .accessibility_label(accessible_name(node))
                .label(label.clone())
                .disabled(*disabled)
                .on_click(move |_, window, cx| {
                    if active.borrow().is_some() {
                        return;
                    }
                    let session = Rc::new(Session {
                        id: id.clone(),
                        revision,
                        confirmed: Cell::new(false),
                        closed: Cell::new(false),
                    });
                    *active.borrow_mut() = Some(session.clone());
                    window.refresh();
                    let (active, events) = (active.clone(), events.clone());
                    let (title, message, confirm_label, cancel_label) = (
                        title.clone(),
                        message.clone(),
                        confirm_label.clone(),
                        cancel_label.clone(),
                    );
                    window.open_dialog(cx, move |dialog, _, _| {
                        let accepted = session.clone();
                        let (closed, active, events) =
                            (session.clone(), active.clone(), events.clone());
                        let (ok_session, ok_active, ok_events) =
                            (session.clone(), active.clone(), events.clone());
                        let (cancel_session, cancel_active, cancel_events) =
                            (session.clone(), active.clone(), events.clone());
                        // Supply the actual modal content and buttons. At this pin,
                        // button_props configures decisions but creates no footer.
                        let content = div()
                            .id("confirmation-content")
                            .test_support()
                            .role(Role::Dialog)
                            .aria_label(title.clone())
                            .accessibility_id(json!(["dialog", session.id]).to_string())
                            .a11y_synthetic_children(|tree| tree.parent_node().set_modal())
                            .v_flex()
                            .gap_4()
                            .child(
                                div()
                                    .id("confirmation-title")
                                    .role(Role::Heading)
                                    .aria_level(2)
                                    .aria_label(title.clone())
                                    .text_lg()
                                    .child(title.clone()),
                            )
                            .child(
                                div()
                                    .id("confirmation-message")
                                    .role(Role::Label)
                                    .aria_value(message.clone())
                                    .child(message.clone()),
                            )
                            .child(
                                div()
                                    .h_flex()
                                    .justify_end()
                                    .gap_2()
                                    .child(
                                        Button::new("cancel").label(cancel_label.clone()).on_click(
                                            move |_, window, cx| {
                                                finish(
                                                    &cancel_active,
                                                    &cancel_session,
                                                    &cancel_events,
                                                );
                                                window.close_dialog(cx);
                                                window.refresh();
                                            },
                                        ),
                                    )
                                    .child(
                                        Button::new("ok")
                                            .primary()
                                            .label(confirm_label.clone())
                                            .on_click(move |_, window, cx| {
                                                ok_session.confirmed.set(true);
                                                finish(&ok_active, &ok_session, &ok_events);
                                                window.close_dialog(cx);
                                                window.refresh();
                                            }),
                                    ),
                            );
                        dialog
                            .child(content)
                            .close_button(false)
                            .overlay_closable(false)
                            .on_ok(move |_, _, _| {
                                accepted.confirmed.set(true);
                                true
                            })
                            .on_close(move |_, window, _| {
                                finish(&active, &closed, &events);
                                window.refresh();
                            })
                    });
                }),
            node,
            colors,
        )
        .into_any_element())
    }
}
