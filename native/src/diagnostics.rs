use crate::{Events, protocol::Event, ui::DartView};
use gpui_kit::{App, Entity, Window};
use serde::Deserialize;
use serde_json::{Value, json};
use std::cell::Cell;

#[derive(Default)]
pub(crate) struct Counters {
    pub materializations: Cell<u64>,
    pub rows: Cell<u64>,
    pub cells: Cell<u64>,
}

impl Counters {
    pub fn read(&self) -> Value {
        json!({"materializations": self.materializations.get(), "rows_constructed": self.rows.get(), "cells_constructed": self.cells.get()})
    }
}

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Request {
    Inspect {
        request: u64,
    },
    Repaint {
        request: u64,
        frames: u32,
    },
    Prepare {
        request: u64,
        input: String,
        text: String,
        start: usize,
        end: usize,
        table: String,
        row: usize,
    },
}

pub(crate) fn handle(
    request: Request,
    view: &Entity<DartView>,
    events: &Events,
    window: &mut Window,
    cx: &mut App,
) {
    match request {
        Request::Inspect { request } => reply(request, view, events, window, cx),
        Request::Repaint { request, frames } if frames <= 600 => {
            let target = view.read(cx).materialization_count() + u64::from(frames);
            repaint(request, target, view.clone(), events.clone(), window, cx);
        }
        Request::Repaint { request, .. } => events.emit(Event::Diagnostic {
            request,
            data: json!({"error":"At most 600 diagnostic frames"}),
        }),
        Request::Prepare {
            request,
            input,
            text,
            start,
            end,
            table,
            row,
        } => {
            let outcome = view.update(cx, |view, cx| {
                view.prepare(&input, &text, start..end, &table, row, window, cx)
            });
            match outcome {
                Ok(()) => window.on_next_frame({
                    let view = view.clone();
                    let events = events.clone();
                    move |window, cx| reply(request, &view, &events, window, cx)
                }),
                Err(error) => events.emit(Event::Diagnostic {
                    request,
                    data: json!({"error": error}),
                }),
            }
        }
    }
}

fn reply(request: u64, view: &Entity<DartView>, events: &Events, window: &Window, cx: &App) {
    events.emit(Event::Diagnostic {
        request,
        data: view.read(cx).inspect(window, cx),
    });
}

fn repaint(
    request: u64,
    target: u64,
    view: Entity<DartView>,
    events: Events,
    window: &mut Window,
    cx: &mut App,
) {
    if view.read(cx).materialization_count() >= target {
        reply(request, &view, &events, window, cx);
        return;
    }
    window.refresh();
    window.on_next_frame(move |window, cx| repaint(request, target, view, events, window, cx));
}
