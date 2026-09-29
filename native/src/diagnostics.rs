use crate::{Events, protocol::Event, ui::DartView};
use gpui_kit::{
    App, Entity, KeyUpEvent, Keystroke, PathPromptOptions, PlatformInput, SharedString, Window,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{cell::Cell, path::Path};

#[derive(Default)]
pub(crate) struct Counters {
    pub materializations: Cell<u64>,
    pub rows: Cell<u64>,
    pub cells: Cell<u64>,
    pub data_records_checked: Cell<u64>,
    pub data_cells_written: Cell<u64>,
    pub view_recomputes: Cell<u64>,
    /// View indices computed off the frame thread, a subset of the recomputes.
    pub view_jobs: Cell<u64>,
}

impl Counters {
    pub fn read(&self) -> Value {
        json!({"materializations": self.materializations.get(), "rows_constructed": self.rows.get(), "cells_constructed": self.cells.get(), "data_records_checked": self.data_records_checked.get(), "data_cells_written": self.data_cells_written.get(), "view_recomputes": self.view_recomputes.get(), "view_jobs": self.view_jobs.get()})
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
    Focus {
        request: u64,
        input: String,
    },
    SelectRow {
        request: u64,
        table: String,
        row: usize,
    },
    Inspect {
        request: u64,
    },
    Semantics {
        request: u64,
    },
    Key {
        request: u64,
        key: String,
    },
    Repaint {
        request: u64,
        frames: u32,
    },
    /// The frames the view rendered since the last mark and the longest
    /// interval between two of them; `mark` starts the next interval set.
    FrameGaps {
        request: u64,
        #[serde(default)]
        mark: bool,
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
    /// Native file or folder chooser; replies with the chosen paths, or null
    /// when the user cancelled, once the dialog closes.
    PromptPaths {
        request: u64,
        #[serde(default)]
        files: bool,
        #[serde(default)]
        directories: bool,
        #[serde(default)]
        multiple: bool,
        #[serde(default)]
        prompt: Option<String>,
    },
    /// Native save dialog starting in `directory`.
    PromptSavePath {
        request: u64,
        directory: String,
        #[serde(default)]
        suggested_name: Option<String>,
    },
    /// Opens an http, https or mailto URL with the OS handler.
    OpenUrl {
        request: u64,
        url: String,
    },
    /// Shows a path in the OS file manager.
    RevealPath {
        request: u64,
        path: String,
    },
}

impl Request {
    pub(crate) fn id(&self) -> u64 {
        match self {
            Self::Runtime { request }
            | Self::Cell { request, .. }
            | Self::FormattedCell { request, .. }
            | Self::Focus { request, .. }
            | Self::SelectRow { request, .. }
            | Self::Inspect { request }
            | Self::Semantics { request }
            | Self::Key { request, .. }
            | Self::Repaint { request, .. }
            | Self::FrameGaps { request, .. }
            | Self::Prepare { request, .. }
            | Self::PromptPaths { request, .. }
            | Self::PromptSavePath { request, .. }
            | Self::OpenUrl { request, .. }
            | Self::RevealPath { request, .. } => *request,
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
        Request::PromptPaths {
            request,
            files,
            directories,
            multiple,
            prompt,
        } => {
            let receiver = cx.prompt_for_paths(PathPromptOptions {
                files,
                directories,
                multiple,
                prompt: prompt.map(SharedString::from),
            });
            let events = events.clone();
            cx.spawn(async move |_| {
                let data = match receiver.await {
                    Ok(Ok(Some(paths))) => json!({
                        "paths": paths.iter().map(|path| path.to_string_lossy()).collect::<Vec<_>>()
                    }),
                    Ok(Ok(None)) => json!({"paths": Value::Null}),
                    Ok(Err(error)) => json!({"error": error.to_string()}),
                    Err(_) => json!({"error": "The path prompt closed without a result"}),
                };
                events.emit(Event::Diagnostic { request, data });
            })
            .detach();
        }
        Request::PromptSavePath {
            request,
            directory,
            suggested_name,
        } => {
            let receiver = cx.prompt_for_new_path(Path::new(&directory), suggested_name.as_deref());
            let events = events.clone();
            cx.spawn(async move |_| {
                let data = match receiver.await {
                    Ok(Ok(Some(path))) => json!({"path": path.to_string_lossy()}),
                    Ok(Ok(None)) => json!({"path": Value::Null}),
                    Ok(Err(error)) => json!({"error": error.to_string()}),
                    Err(_) => json!({"error": "The save prompt closed without a result"}),
                };
                events.emit(Event::Diagnostic { request, data });
            })
            .detach();
        }
        Request::OpenUrl { request, url } => {
            let allowed = ["http://", "https://", "mailto:"]
                .iter()
                .any(|scheme| url.starts_with(scheme));
            if allowed {
                cx.open_url(&url);
            }
            events.emit(Event::Diagnostic {
                request,
                data: if allowed {
                    json!({"opened": true})
                } else {
                    json!({"error": "Only http, https and mailto URLs open"})
                },
            });
        }
        Request::RevealPath { request, path } => {
            cx.reveal_path(Path::new(&path));
            events.emit(Event::Diagnostic {
                request,
                data: json!({"revealed": true}),
            });
        }
        Request::Semantics { request } => {
            let tree = window
                .debug_a11y_tree_json()
                .and_then(|text| serde_json::from_str::<Value>(&text).ok());
            events.emit(Event::Diagnostic {
                request,
                data: json!({"active":window.is_a11y_active(),"tree":tree}),
            });
        }
        Request::Key { request, key } => {
            let parsed = if key.len() > 64 {
                None
            } else {
                Keystroke::parse(&key).ok()
            };
            match parsed {
                Some(key) => {
                    // GPUI dispatch, not OS injection or an IME simulation. Send
                    // key-up as well: native Space activation completes there.
                    window.dispatch_keystroke(key.clone(), cx);
                    window.dispatch_event(PlatformInput::KeyUp(KeyUpEvent { keystroke: key }), cx);
                    window.refresh();
                    events.emit(Event::Diagnostic {
                        request,
                        data: json!({"ok":true,"source":"gpui_key_dispatch"}),
                    });
                }
                None => events.emit(Event::Diagnostic {
                    request,
                    data: json!({"error":"Invalid diagnostic keystroke"}),
                }),
            }
        }
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
        Request::SelectRow {
            request,
            table,
            row,
        } => {
            let outcome = view.update(cx, |view, cx| view.select_table_row(&table, row, cx));
            events.emit(Event::Diagnostic {
                request,
                data: match outcome {
                    Ok(()) => json!({"selected": row}),
                    Err(error) => json!({"error": error}),
                },
            });
        }
        Request::Focus { request, input } => {
            let outcome = view.update(cx, |view, cx| view.focus_input(&input, window, cx));
            events.emit(Event::Diagnostic {
                request,
                data: match outcome {
                    Ok(()) => json!({"focused": input}),
                    Err(error) => json!({"error": error}),
                },
            });
        }
        Request::Inspect { request } => reply(request, view, events, window, cx),
        Request::FrameGaps { request, mark } => events.emit(Event::Diagnostic {
            request,
            data: view.update(cx, |view, _| view.frame_gaps(mark)),
        }),
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
