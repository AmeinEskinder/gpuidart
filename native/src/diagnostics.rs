use crate::{Events, protocol::Event, ui::DartView};
use gpui_kit::{App, Entity, Window};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::cell::Cell;

#[derive(Default)]
pub(crate) struct Counters {
    pub materializations: Cell<u64>,
    pub rows: Cell<u64>,
    pub cells: Cell<u64>,
    pub data_records_checked: Cell<u64>,
    pub data_cells_written: Cell<u64>,
    pub view_recomputes: Cell<u64>,
}

impl Counters {
    pub fn read(&self) -> Value {
        json!({"materializations": self.materializations.get(), "rows_constructed": self.rows.get(), "cells_constructed": self.cells.get(), "data_records_checked": self.data_records_checked.get(), "data_cells_written": self.data_cells_written.get(), "view_recomputes": self.view_recomputes.get()})
    }
}

#[derive(Deserialize, Serialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Request {
    Runtime {
        request: u64,
    },
    Cell {
        request: u64,
        dataset: String,
        row: usize,
        column: usize,
    },
    FormattedCell {
        request: u64,
        table: String,
        row: usize,
        column: usize,
    },
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

impl Request {
    pub(crate) fn id(&self) -> u64 {
        match self {
            Self::Runtime { request }
            | Self::Cell { request, .. }
            | Self::FormattedCell { request, .. }
            | Self::Inspect { request }
            | Self::Repaint { request, .. }
            | Self::Prepare { request, .. } => *request,
        }
    }
}

pub(crate) fn handle(
    request: Request,
    view: &Entity<DartView>,
    events: &Events,
    window: &mut Window,
    cx: &mut App,
) {
    match request {
        Request::Runtime { request } => events.emit(Event::Diagnostic {
            request,
            data: crate::runtime_info::read(),
        }),
        Request::Cell {
            request,
            dataset,
            row,
            column,
        } => events.emit(Event::Diagnostic {
            request,
            data: view.read(cx).cell(&dataset, row, column),
        }),
        Request::FormattedCell {
            request,
            table,
            row,
            column,
        } => events.emit(Event::Diagnostic {
            request,
            data: view.read(cx).formatted_cell(&table, row, column, cx),
        }),
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
                Ok(()) => {
                    // A next-frame callback can run before the draw that consumes
                    // TableState's deferred scroll. Require a render before reply.
                    let target = view.read(cx).materialization_count() + 1;
                    repaint(request, target, view.clone(), events.clone(), window, cx);
                }
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
