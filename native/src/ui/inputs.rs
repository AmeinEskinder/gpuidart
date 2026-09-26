use super::*;
use crate::input_control::{self, Operation, Request, Selection, State, Status};

pub(super) fn capture(
    input: &Entity<InputState>,
    generation: u64,
    controlled: bool,
    window: &mut Window,
    cx: &mut App,
) -> State {
    input.update(cx, |input, cx| {
        let value = input.value().to_string();
        let range = input.selected_range();
        State {
            generation,
            edit_revision: 0,
            controlled,
            selection: Selection {
                start: value[..range.start].encode_utf16().count(),
                end: value[..range.end].encode_utf16().count(),
            },
            value,
            composing: input.marked_text_range(window, cx).is_some(),
        }
    })
}

impl DartView {
    /// Sample immediately before every guarded write, including composition
    /// changes for which the underlying input did not send a notification.
    pub(super) fn refresh_input(
        &mut self,
        id: &str,
        emit: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Option<State> {
        let input = self.inputs.get_mut(id)?;
        let old = &input.version;
        let mut state = capture(&input.state, old.generation, old.controlled, window, cx);
        let changed = state.value != old.value
            || state.selection != old.selection
            || state.composing != old.composing;
        state.edit_revision = old.edit_revision + u64::from(changed);
        input.version = state.clone();
        if changed && state.controlled && emit {
            self.events.emit(Event::Input {
                revision: self.snapshot.revision,
                id: id.to_owned(),
                value: state.value.clone(),
                input_state: Some(state.clone()),
            });
        }
        Some(state)
    }

    pub(super) fn input_command(
        &mut self,
        request: Request,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let state = self.refresh_input(&request.id, true, window, cx);
        let (status, state) = match (state, request.operation) {
            (None, _) => (Status::Missing, None),
            (Some(state), Operation::Read {}) => (Status::Read, Some(state)),
            (
                Some(state),
                Operation::Write {
                    generation,
                    base_revision,
                    text,
                    selection,
                },
            ) => {
                let status = if !state.controlled {
                    Some(Status::NotControlled)
                } else if state.composing {
                    Some(Status::Composing)
                } else if state.generation != generation || state.edit_revision != base_revision {
                    Some(Status::Stale)
                } else {
                    None
                };
                if let Some(status) = status {
                    (status, Some(state))
                } else {
                    let value = text.as_deref().unwrap_or(&state.value);
                    let bytes = selection.as_ref().map(|s| {
                        input_control::byte_offset(value, s.start)
                            .zip(input_control::byte_offset(value, s.end))
                            .map(|(start, end)| start..end)
                    });
                    if matches!(bytes, Some(None)) {
                        (Status::InvalidSelection, Some(state))
                    } else {
                        if let Some(input) = self.inputs.get(&request.id) {
                            input.state.update(cx, |input, cx| {
                                if let Some(text) = text.filter(|text| text != &state.value) {
                                    input.set_value(text, window, cx);
                                }
                                if let Some(Some(range)) = bytes {
                                    input.set_selected_range(range, cx);
                                }
                            });
                        }
                        // Record the programmatic state before queued notifications
                        // run. They must not echo this write as a native user edit.
                        (
                            Status::Applied,
                            self.refresh_input(&request.id, false, window, cx),
                        )
                    }
                }
            }
        };
        self.events.emit(Event::InputResult {
            request: request.request,
            id: request.id,
            status,
            state,
        });
    }
}
