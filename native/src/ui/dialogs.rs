use super::*;
use gpui_kit::component::{WindowExt, dialog::DialogButtonProps};
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
            Button::new(SharedString::from(id.clone()))
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
                        dialog
                            .title(title.clone())
                            .child(message.clone())
                            .overlay_closable(false)
                            .button_props(
                                DialogButtonProps::default()
                                    .show_cancel(true)
                                    .ok_text(confirm_label.clone())
                                    .cancel_text(cancel_label.clone()),
                            )
                            .on_ok(move |_, _, _| {
                                accepted.confirmed.set(true);
                                true
                            })
                            .on_close(move |_, _, _| finish(&active, &closed, &events))
                    });
                }),
            node,
            colors,
        )
        .into_any_element())
    }
}
