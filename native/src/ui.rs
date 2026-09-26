use crate::datasets::{self, Change, Edit, Initial, SharedDataset, Store, Update};
use crate::diagnostics::Counters;
use crate::{
    Command, Events,
    protocol::{
        Align as StyleAlign, CellIcon, Color as StyleColor, Event, FontWeight as StyleFontWeight,
        Justify as StyleJustify, KeystrokeSpec, Node, Size as StyleSize, Snapshot, Style,
        TableView, ThemeToken,
    },
};
use async_channel::Receiver;
use gpui_kit::assets::IconName;
use gpui_kit::base::ScrollbarHandle;
use gpui_kit::component::theme::ThemeColor;
use gpui_kit::component::{
    ActiveTheme, Icon, StyledExt,
    button::{Button, ButtonVariants},
    input::{Input, InputEvent, InputState},
    scroll::ScrollableElement,
    table::{Column, DataTable, TableDelegate, TableEvent, TableState},
};
use gpui_kit::*;
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    rc::Rc,
    sync::Arc,
    time::Instant,
};

struct Rows {
    data: SharedDataset,
    /// View index: view row -> source row. Identity mapping when the table
    /// has no view.
    index: Rc<RefCell<Vec<usize>>>,
    counters: Rc<Counters>,
}

impl Rows {
    fn source_row(&self, view_row: usize) -> usize {
        self.index.borrow()[view_row]
    }
}

impl TableDelegate for Rows {
    fn columns_count(&self, _: &App) -> usize {
        self.data.borrow().data.columns.len()
    }
    fn rows_count(&self, _: &App) -> usize {
        self.index.borrow().len()
    }
    fn column(&self, index: usize, _: &App) -> Column {
        Column::new(
            format!("column-{index}"),
            self.data.borrow().data.columns[index].clone(),
        )
        .width(px(200.))
    }
    fn render_td(
        &mut self,
        row: usize,
        col: usize,
        _: &mut Window,
        cx: &mut Context<TableState<Self>>,
    ) -> impl IntoElement {
        self.counters.cells.set(self.counters.cells.get() + 1);
        let source = self.source_row(row);
        let data = self.data.borrow();
        let raw = data.data.rows[source][col].clone();
        let Some(format) = data
            .data
            .format
            .as_ref()
            .and_then(|format| format.columns.get(&col))
        else {
            return div().child(raw).into_any_element();
        };
        let formatted = format.apply(&raw);
        let colors = cx.theme().colors.clone();
        let color = formatted.color.map(|color| resolve_color(color, &colors));
        let mut cell = div().child(formatted.text);
        if let Some(color) = color {
            cell = cell.text_color(color);
        }
        let Some(icon) = formatted.icon else {
            return cell.into_any_element();
        };
        let mut icon = Icon::new(match icon {
            CellIcon::ArrowUp => IconName::ArrowUp,
            CellIcon::ArrowDown => IconName::ArrowDown,
            CellIcon::Dot => IconName::Dot,
            CellIcon::Warning => IconName::TriangleAlert,
        });
        if let Some(color) = color {
            icon = icon.text_color(color);
        }
        div()
            .h_flex()
            .items_center()
            .gap_1()
            .child(icon)
            .child(cell)
            .into_any_element()
    }
    fn render_tr(
        &mut self,
        row: usize,
        _: &mut Window,
        _: &mut Context<TableState<Self>>,
    ) -> Stateful<Div> {
        self.counters.rows.set(self.counters.rows.get() + 1);
        // Key real rows by source record so element identity survives view
        // changes; the table also asks for filler rows past the view's end.
        match self.index.borrow().get(row) {
            Some(&source) => div().id(("row", source)),
            None => div().id(("row-filler", row)),
        }
    }
}

struct RetainedInput {
    state: Entity<InputState>,
    placeholder: String,
    _subscription: Subscription,
}

struct RetainedTable {
    state: Entity<TableState<Rows>>,
    view: Option<TableView>,
    /// Selection anchor in identity mode: the record ID. Index-mode
    /// selection lives only in `TableState` as a view row, as before.
    selected_record: Option<String>,
    /// Last emitted (row, record), so programmatic re-resolution and
    /// redundant clears do not emit duplicate selection events. Events are
    /// delivered deferred, after the table state has settled.
    selection_notified: Option<(Option<usize>, Option<String>)>,
}

/// Selection decision for a view recompute.
enum ViewSelection {
    /// Keep the selected record at this view row.
    Keep(usize),
    /// The selected record left the view: clear and emit the null event.
    Gone,
    /// Unconditional clear (Replace without identity).
    Clear,
    /// Keep the view-row index, clamped into range (index mode, edits).
    Clamp,
}

pub(crate) struct DartView {
    snapshot: Snapshot,
    events: Events,
    inputs: HashMap<String, RetainedInput>,
    tables: HashMap<String, RetainedTable>,
    table_subscriptions: HashMap<String, Subscription>,
    scroll: ScrollHandle,
    datasets: Store,
    counters: Rc<Counters>,
    failure: Option<String>,
    _key_interceptor: Subscription,
}

impl DartView {
    pub(crate) fn materialization_count(&self) -> u64 {
        self.counters.materializations.get()
    }

    pub(crate) fn inspect(&self, window: &Window, cx: &App) -> Value {
        let inputs = self
            .inputs
            .iter()
            .map(|(id, input)| {
                let state = input.state.read(cx);
                (
                    id.clone(),
                    json!({
                        "entity": input.state.entity_id().as_u64(),
                        "text": state.value().to_string(),
                        "selection": state.selected_range(),
                        "focused": state.focus_handle(cx).is_focused(window),
                    }),
                )
            })
            .collect::<serde_json::Map<_, _>>();
        let tables = self
            .tables
            .iter()
            .map(|(id, retained)| {
                let table = retained.state.read(cx);
                let offset = table.vertical_scroll_handle.offset();
                let source_rows = table.delegate().data.borrow().data.rows.len();
                let view_rows = table.delegate().index.borrow().len();
                let spec_hash = retained.view.as_ref().map(|view| {
                    use std::hash::{Hash, Hasher};
                    let mut hasher = std::collections::hash_map::DefaultHasher::new();
                    serde_json::to_string(view).unwrap_or_default().hash(&mut hasher);
                    hasher.finish()
                });
                (
                    id.clone(),
                    json!({
                        "entity": retained.state.entity_id().as_u64(),
                        "visible_rows": table.visible_range().rows(),
                        "row_count": source_rows,
                        "dataset": table.delegate().data.borrow().id,
                        "dataset_revision": table.delegate().data.borrow().revision,
                        "scroll_y": f32::from(offset.y),
                        "view": {"source_rows": source_rows, "view_rows": view_rows, "spec_hash": spec_hash},
                        "selection": {"row": table.selected_row(), "record": retained.selected_record},
                        "focused": table.focus_handle(cx).is_focused(window),
                    }),
                )
            })
            .collect::<serde_json::Map<_, _>>();
        let mut labels = serde_json::Map::new();
        self.snapshot.root.visit(&mut |node| {
            if let Node::Text { id, text, .. } = node {
                labels.insert(id.clone(), json!(text));
            }
        });
        macro_rules! histogram {
            ($hist:expr) => {{
                let histogram = $hist;
                json!({
                    "samples": histogram.len(),
                    "p50_us": histogram.value_at_quantile(0.50) as f64 / 1000.0,
                    "p95_us": histogram.value_at_quantile(0.95) as f64 / 1000.0,
                    "p99_us": histogram.value_at_quantile(0.99) as f64 / 1000.0,
                })
            }};
        }
        let frames = window.frame_duration_snapshot();
        let input = window.input_latency_snapshot();
        json!({"revision": self.snapshot.revision, "native_process_id": std::process::id(), "inputs": inputs, "tables": tables, "labels": labels,
            "window": {"width": f32::from(window.viewport_size().width), "height": f32::from(window.viewport_size().height), "scale_factor": window.scale_factor(), "scroll_y": f32::from(self.scroll.offset().y)},
            "native": self.counters.read(),
            "draw": histogram!(frames.draw_duration_histogram),
            "dirty_to_present_submit": histogram!(frames.dirty_to_present_histogram),
            "present_interval": histogram!(frames.present_interval_histogram),
            "input_to_frame": histogram!(input.latency_histogram),
        })
    }

    pub(crate) fn prepare(
        &mut self,
        input: &str,
        text: &str,
        selection: std::ops::Range<usize>,
        table: &str,
        row: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Result<(), String> {
        let input = self.inputs.get(input).ok_or("Unknown input")?;
        let table = self.tables.get(table).ok_or("Unknown table")?;
        if selection.start > selection.end
            || selection.end > text.len()
            || !text.is_char_boundary(selection.start)
            || !text.is_char_boundary(selection.end)
            || row >= table.state.read(cx).delegate().rows_count(cx)
        {
            return Err("Invalid selection or row".into());
        }
        input.state.update(cx, |input, cx| {
            input.set_value(text.to_owned(), window, cx);
            input.set_selected_range(selection, cx);
            input.focus(window, cx);
        });
        table
            .state
            .update(cx, |table, cx| table.scroll_to_row(row, cx));
        cx.notify();
        Ok(())
    }

    fn new(initial: Initial, events: Events, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let this = cx.entity();
        let key_interceptor = cx.intercept_keystrokes(move |event, window, cx| {
            let view = this.read(cx);
            let Some((name, context)) = view.match_action(&event.keystroke, window, cx) else {
                return;
            };
            view.events.emit(Event::Action {
                revision: view.snapshot.revision,
                name,
                context,
            });
            window.prevent_default();
            cx.stop_propagation();
        });
        let mut view = Self {
            snapshot: initial.snapshot,
            datasets: Store::new(initial.datasets),
            events,
            inputs: HashMap::new(),
            tables: HashMap::new(),
            table_subscriptions: HashMap::new(),
            scroll: ScrollHandle::new(),
            counters: Rc::new(Counters::default()),
            failure: None,
            _key_interceptor: key_interceptor,
        };
        if let Err(message) = view.reconcile(window, cx) {
            view.fail(message, cx);
        }
        view
    }

    fn fail(&mut self, message: String, cx: &mut Context<Self>) {
        if self.failure.is_none() {
            self.events.emit(Event::Error {
                message: message.clone(),
            });
            self.failure = Some(message);
            cx.quit();
        }
    }

    fn publish(&mut self, snapshot: Snapshot, window: &mut Window, cx: &mut Context<Self>) {
        let timer = Instant::now();
        if snapshot.revision <= self.snapshot.revision {
            self.events.emit(Event::Rejected {
                revision: snapshot.revision,
                message: "Revision must increase".into(),
            });
            return;
        }
        if let Err(message) = snapshot
            .validate()
            .and_then(|_| {
                datasets::validate_references(&snapshot, |id| {
                    self.datasets.entries.contains_key(id)
                })
            })
            .and_then(|_| {
                datasets::validate_views(&snapshot, |id| {
                    self.datasets
                        .entries
                        .get(id)
                        .map(|data| data.borrow().data.columns.len())
                })
            })
        {
            self.events.emit(Event::Rejected {
                revision: snapshot.revision,
                message,
            });
            return;
        }
        self.snapshot = snapshot;
        if let Err(message) = self.reconcile(window, cx) {
            self.fail(message, cx);
            return;
        }
        self.events.emit(Event::Applied {
            revision: self.snapshot.revision,
            native_apply_us: timer.elapsed().as_micros() as u64,
        });
        cx.notify();
    }

    pub(crate) fn cell(&self, dataset: &str, row: usize, column: usize) -> Value {
        let Some(data) = self.datasets.entries.get(dataset) else {
            return json!({"error":"Unknown dataset"});
        };
        let data = data.borrow();
        match data.data.rows.get(row).and_then(|row| row.get(column)) {
            Some(value) => json!({"value":value, "revision":data.revision}),
            None => json!({"error":"Invalid cell"}),
        }
    }

    /// Focuses a retained input without touching value, selection or scroll.
    pub(crate) fn focus_input(
        &mut self,
        input: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Result<(), String> {
        let input = self.inputs.get(input).ok_or("Unknown input")?;
        input.state.update(cx, |input, cx| input.focus(window, cx));
        cx.notify();
        Ok(())
    }

    /// The formatted rendering of a cell at view coordinates, for tests and
    /// diagnostics; mirrors what `render_td` paints.
    pub(crate) fn formatted_cell(&self, table: &str, row: usize, column: usize, cx: &App) -> Value {
        let Some(retained) = self.tables.get(table) else {
            return json!({"error":"Unknown table"});
        };
        let delegate = retained.state.read(cx).delegate();
        let Some(&source) = delegate.index.borrow().get(row) else {
            return json!({"error":"Invalid row"});
        };
        let data = delegate.data.borrow();
        let Some(raw) = data.data.rows.get(source).and_then(|row| row.get(column)) else {
            return json!({"error":"Invalid cell"});
        };
        let Some(format) = data
            .data
            .format
            .as_ref()
            .and_then(|format| format.columns.get(&column))
        else {
            return json!({"text": raw});
        };
        let formatted = format.apply(raw);
        json!({
            "text": formatted.text,
            "color": formatted.color,
            "icon": formatted.icon,
        })
    }

    fn update_dataset(&mut self, update: Update, parse_us: u64, cx: &mut Context<Self>) {
        let timer = Instant::now();
        let request = update.request;
        let id = update.id.clone();
        let revision = update.revision;
        let replace = matches!(&update.change, Change::Replace { .. });
        // Columns an edit touches, for the view-recompute check. Row edits
        // touch every column; Replace is handled separately.
        let touched: Option<HashSet<usize>> = match &update.change {
            Change::Edit { edits } => {
                let width = self
                    .datasets
                    .entries
                    .get(&update.id)
                    .map(|data| data.borrow().data.columns.len())
                    .unwrap_or(0);
                Some(
                    edits
                        .iter()
                        .flat_map(|edit| match edit {
                            Edit::Cell { column, .. } => vec![*column],
                            Edit::Row { .. } => (0..width).collect(),
                        })
                        .collect(),
                )
            }
            _ => None,
        };
        if matches!(&update.change, Change::Release) {
            let mut referenced = false;
            self.snapshot.root.visit(&mut |node| {
                if let Node::Table { dataset, .. } = node {
                    referenced |= dataset == &id;
                }
            });
            if referenced {
                self.events.emit(Event::DatasetRejected {
                    request,
                    message: "Remove dataset references from the view before releasing it".into(),
                });
                return;
            }
        }
        match self.datasets.apply(update) {
            Ok(work) => {
                let table_ids: Vec<String> = self
                    .tables
                    .iter()
                    .filter(|(_, retained)| {
                        retained.state.read(cx).delegate().data.borrow().id == id
                    })
                    .map(|(table_id, _)| table_id.clone())
                    .collect();
                for table_id in table_ids {
                    // A cell edit only triggers a view recompute when it
                    // touches a column the view sorts or filters on.
                    let recompute = replace
                        || match (&self.tables[&table_id].view, &touched) {
                            (Some(view), Some(touched)) => view
                                .referenced_columns()
                                .iter()
                                .any(|column| touched.contains(column)),
                            _ => false,
                        };
                    if recompute {
                        self.recompute_table_view(&table_id, replace, cx);
                    } else {
                        let state = self.tables[&table_id].state.clone();
                        state.update(cx, |_, cx| cx.notify());
                    }
                }
                self.counters
                    .data_records_checked
                    .set(self.counters.data_records_checked.get() + work.records_checked as u64);
                self.counters
                    .data_cells_written
                    .set(self.counters.data_cells_written.get() + work.cells_written as u64);
                #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
                crate::input_trace::record_sequence(
                    "update_applied",
                    None,
                    json!({"request": request, "revision": revision, "first_cell": self.cell(&id, 0, 2)}),
                );
                self.events.emit(Event::DatasetApplied {
                    request,
                    id,
                    revision,
                    parse_us,
                    apply_us: timer.elapsed().as_micros() as u64,
                    work,
                });
            }
            Err(message) => self
                .events
                .emit(Event::DatasetRejected { request, message }),
        }
    }

    /// Recomputes a table's view index after its spec or dataset changed.
    ///
    /// Selection: in identity mode the selected record ID is re-resolved to
    /// its new view row; if it left the view the selection clears and the
    /// subscription emits the null `TableSelection`. `reset_scroll` (Replace)
    /// keeps the historic unconditional scroll reset; otherwise the first
    /// visible record stays anchored if it remains in the view, else the
    /// scroll resets to the top.
    fn recompute_table_view(&mut self, id: &str, reset_scroll: bool, cx: &mut Context<Self>) {
        let Some(retained) = self.tables.get(id) else {
            return;
        };
        let table = retained.state.clone();
        let spec = retained.view.clone();
        let selected_record = retained.selected_record.clone();
        let (index, data, anchor_source) = {
            let state = table.read(cx);
            let anchor = state.visible_range().rows().start;
            let anchor_source = state.delegate().index.borrow().get(anchor).copied();
            (
                state.delegate().index.clone(),
                state.delegate().data.clone(),
                anchor_source,
            )
        };
        let (new_index, selection, anchor_view) = {
            let data = data.borrow();
            let new_index = match &spec {
                Some(spec) => spec.compute_index(&data.data),
                None => (0..data.data.rows.len()).collect::<Vec<_>>(),
            };
            let selection = match (&selected_record, &data.data.ids) {
                (Some(record), Some(ids)) => ids
                    .iter()
                    .position(|id| id == record)
                    .and_then(|source| new_index.iter().position(|&row| row == source))
                    .map_or(ViewSelection::Gone, ViewSelection::Keep),
                _ if reset_scroll => ViewSelection::Clear,
                _ => ViewSelection::Clamp,
            };
            let anchor_view =
                anchor_source.and_then(|source| new_index.iter().position(|&row| row == source));
            (new_index, selection, anchor_view)
        };
        let view_len = new_index.len();
        *index.borrow_mut() = new_index;
        self.counters
            .view_recomputes
            .set(self.counters.view_recomputes.get() + 1);
        table.update(cx, |table, cx| {
            match selection {
                ViewSelection::Keep(view_row) => {
                    if table.selected_row() != Some(view_row) {
                        table.set_selected_row(view_row, cx);
                    }
                }
                ViewSelection::Gone | ViewSelection::Clear => {
                    table.clear_selection(cx);
                }
                ViewSelection::Clamp => {
                    if table.selected_row().is_some_and(|row| row >= view_len) {
                        table.clear_selection(cx);
                    }
                }
            }
            // set_selected_row defers a scroll-to-selection; the anchor and
            // reset rules below take precedence over it.
            table
                .vertical_scroll_handle
                .0
                .borrow_mut()
                .deferred_scroll_to_item = None;
            if reset_scroll {
                table
                    .vertical_scroll_handle
                    .set_offset(point(px(0.), px(0.)));
                table
                    .horizontal_scroll_handle
                    .set_offset(point(px(0.), px(0.)));
                table.refresh(cx);
            } else if let Some(view_row) = anchor_view {
                table.scroll_to_row(view_row, cx);
            } else {
                table
                    .vertical_scroll_handle
                    .set_offset(point(px(0.), px(0.)));
            }
            cx.notify();
        });
        if matches!(selection, ViewSelection::Gone | ViewSelection::Clear) {
            if let Some(retained) = self.tables.get_mut(id) {
                retained.selected_record = None;
            }
        }
    }

    fn reconcile(&mut self, window: &mut Window, cx: &mut Context<Self>) -> Result<(), String> {
        let mut input_ids = HashSet::new();
        let mut table_ids = HashSet::new();
        let mut changed_views = Vec::new();
        let mut failure = None;
        self.snapshot.root.visit(&mut |node| match node {
            Node::Input {
                id, placeholder, ..
            } => {
                input_ids.insert(id.clone());
                if let Some(input) = self.inputs.get_mut(id) {
                    if input.placeholder != *placeholder {
                        input.state.update(cx, |state, cx| {
                            state.set_placeholder(placeholder.clone(), window, cx)
                        });
                        input.placeholder = placeholder.clone();
                    }
                } else {
                    let state =
                        cx.new(|cx| InputState::new(window, cx).placeholder(placeholder.clone()));
                    let event_id = id.clone();
                    let subscription =
                        cx.subscribe_in(&state, window, move |this, input, event, _, cx| {
                            if matches!(event, InputEvent::Change) {
                                this.events.emit(Event::Input {
                                    revision: this.snapshot.revision,
                                    id: event_id.clone(),
                                    value: input.read(cx).value().to_string(),
                                });
                            }
                        });
                    self.inputs.insert(
                        id.clone(),
                        RetainedInput {
                            state,
                            placeholder: placeholder.clone(),
                            _subscription: subscription,
                        },
                    );
                }
            }
            Node::Table {
                id, dataset, view, ..
            } => {
                let Some(data) = self.datasets.entries.get(dataset).cloned() else {
                    failure = Some(format!("Missing retained dataset: {dataset}"));
                    return;
                };
                table_ids.insert(id.clone());
                if let Some(retained) = self.tables.get_mut(id) {
                    let swapped = !Rc::ptr_eq(&retained.state.read(cx).delegate().data, &data);
                    if swapped {
                        let index = retained.state.read(cx).delegate().index.clone();
                        *index.borrow_mut() = match view {
                            Some(view) => view.compute_index(&data.borrow().data),
                            None => (0..data.borrow().data.rows.len()).collect(),
                        };
                        retained.state.update(cx, |table, cx| {
                            table.delegate_mut().data = data.clone();
                            table.clear_selection(cx);
                            table
                                .vertical_scroll_handle
                                .set_offset(point(px(0.), px(0.)));
                            table
                                .horizontal_scroll_handle
                                .set_offset(point(px(0.), px(0.)));
                            table.refresh(cx);
                            cx.notify();
                        });
                        retained.selected_record = None;
                        retained.view = view.clone();
                    } else if retained.view != *view {
                        retained.view = view.clone();
                        changed_views.push(id.clone());
                    }
                } else {
                    let index = Rc::new(RefCell::new(match view {
                        Some(view) => view.compute_index(&data.borrow().data),
                        None => (0..data.borrow().data.rows.len()).collect(),
                    }));
                    let table = cx.new(|cx| {
                        TableState::new(
                            Rows {
                                data: data.clone(),
                                index,
                                counters: self.counters.clone(),
                            },
                            window,
                            cx,
                        )
                    });
                    let event_id = id.clone();
                    let subscription = cx.subscribe(&table, move |this, table, event, cx| {
                        let (row, record) = match event {
                            TableEvent::SelectRow(row) => {
                                let delegate = table.read(cx).delegate();
                                let source = delegate.index.borrow()[*row];
                                let record = delegate
                                    .data
                                    .borrow()
                                    .data
                                    .ids
                                    .as_ref()
                                    .map(|ids| ids[source].clone());
                                (Some(*row), record)
                            }
                            TableEvent::ClearSelection => (None, None),
                            _ => return,
                        };
                        let Some(retained) = this.tables.get_mut(&event_id) else {
                            return;
                        };
                        retained.selected_record = record.clone();
                        let notified = (row, record);
                        if retained.selection_notified.as_ref() == Some(&notified) {
                            return;
                        }
                        retained.selection_notified = Some(notified.clone());
                        let data = table.read(cx).delegate().data.borrow();
                        this.events.emit(Event::TableSelection {
                            revision: this.snapshot.revision,
                            id: event_id.clone(),
                            dataset: data.id.clone(),
                            dataset_revision: data.revision,
                            row: notified.0,
                            record: notified.1,
                        });
                    });
                    self.table_subscriptions.insert(id.clone(), subscription);
                    self.tables.insert(
                        id.clone(),
                        RetainedTable {
                            state: table,
                            view: view.clone(),
                            selected_record: None,
                            selection_notified: None,
                        },
                    );
                }
            }
            _ => {}
        });
        if let Some(message) = failure {
            return Err(message);
        }
        self.inputs.retain(|id, _| input_ids.contains(id));
        self.tables.retain(|id, _| table_ids.contains(id));
        self.table_subscriptions
            .retain(|id, _| table_ids.contains(id));
        for id in changed_views {
            self.recompute_table_view(&id, false, cx);
        }
        Ok(())
    }

    /// Resolves a keystroke against the snapshot's action bindings. Contexts
    /// are tried from the focused node up to the root, then `global`.
    fn match_action(
        &self,
        keystroke: &Keystroke,
        window: &Window,
        cx: &App,
    ) -> Option<(String, String)> {
        if self.snapshot.actions.is_empty() {
            return None;
        }
        let spec = spec_from_keystroke(keystroke);
        let mut chain = self.focused_context_chain(window, cx).unwrap_or_default();
        chain.push("global".to_owned());
        for context in &chain {
            if let Some(binding) = self.snapshot.actions.iter().find(|binding| {
                binding.context == *context
                    && KeystrokeSpec::parse(&binding.keys).is_ok_and(|keys| keys == spec)
            }) {
                return Some((binding.name.clone(), binding.context.clone()));
            }
        }
        None
    }

    /// Node IDs from the focused input or table up to the root, innermost
    /// first. Buttons use an internal focus handle that gpui-kit does not
    /// expose, so a focused button resolves as no focused node.
    fn focused_context_chain(&self, window: &Window, cx: &App) -> Option<Vec<String>> {
        let focused = window.focused(cx)?;
        for (id, input) in &self.inputs {
            if input.state.read(cx).focus_handle(cx) == focused {
                return self.context_chain(id);
            }
        }
        for (id, table) in &self.tables {
            if table.state.read(cx).focus_handle(cx) == focused {
                return self.context_chain(id);
            }
        }
        None
    }

    fn context_chain(&self, target: &str) -> Option<Vec<String>> {
        fn visit(node: &Node, target: &str, trail: &mut Vec<String>) -> bool {
            trail.push(node.id().to_owned());
            if node.id() == target {
                return true;
            }
            if let Node::Column { children, .. } | Node::Row { children, .. } = node {
                for child in children {
                    if visit(child, target, trail) {
                        return true;
                    }
                }
            }
            trail.pop();
            false
        }
        let mut trail = Vec::new();
        if visit(&self.snapshot.root, target, &mut trail) {
            trail.reverse();
            Some(trail)
        } else {
            None
        }
    }

    fn materialize(&self, node: &Node, colors: &ThemeColor) -> Result<AnyElement, String> {
        let id = SharedString::from(node.id().to_owned());
        Ok(match node {
            Node::Column { children, .. } => apply_node_style(
                div().id(id).v_flex().gap_3().w_full().children(
                    children
                        .iter()
                        .map(|child| self.materialize(child, colors))
                        .collect::<Result<Vec<_>, _>>()?,
                ),
                node,
                colors,
            )
            .into_any_element(),
            Node::Row { children, .. } => apply_node_style(
                div().id(id).h_flex().flex_wrap().gap_3().w_full().children(
                    children
                        .iter()
                        .map(|child| self.materialize(child, colors))
                        .collect::<Result<Vec<_>, _>>()?,
                ),
                node,
                colors,
            )
            .into_any_element(),
            Node::Text { text, .. } => {
                apply_node_style(div().id(id).child(text.clone()), node, colors).into_any_element()
            }
            Node::Button { label, .. } => {
                let events = self.events.clone();
                let event_id = node.id().to_owned();
                let revision = self.snapshot.revision;
                apply_node_style(
                    Button::new(id)
                        .primary()
                        .label(label.clone())
                        .on_click(move |_, _, _| {
                            #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
                            crate::input_trace::record(
                                "native_click_handler",
                                json!({"id": event_id}),
                            );
                            events.emit(Event::Click {
                                revision,
                                id: event_id.clone(),
                                #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
                                debug_input_sequence: crate::input_trace::sequence(),
                            });
                        }),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Input { id, .. } => apply_node_style(
                Input::new(
                    &self
                        .inputs
                        .get(id)
                        .ok_or_else(|| format!("Missing retained input: {id}"))?
                        .state,
                )
                .id(SharedString::from(id.clone())),
                node,
                colors,
            )
            .into_any_element(),
            Node::Table { id, .. } => apply_node_style(
                div()
                    .id(SharedString::from(id.clone()))
                    .w_full()
                    .h(px(320.))
                    .child(
                        DataTable::new(
                            &self
                                .tables
                                .get(id)
                                .ok_or_else(|| format!("Missing retained table: {id}"))?
                                .state,
                        )
                        .stripe(true)
                        .bordered(true),
                    ),
                node,
                colors,
            )
            .into_any_element(),
        })
    }
}

fn spec_from_keystroke(keystroke: &Keystroke) -> KeystrokeSpec {
    KeystrokeSpec {
        ctrl: keystroke.modifiers.control,
        alt: keystroke.modifiers.alt,
        shift: keystroke.modifiers.shift,
        meta: keystroke.modifiers.platform,
        key: keystroke.key.to_ascii_lowercase(),
    }
}

fn apply_node_style<T: Styled>(element: T, node: &Node, colors: &ThemeColor) -> T {
    match node.style() {
        Some(style) => apply_style(element, style, colors),
        None => element,
    }
}

fn style_length(size: StyleSize) -> Length {
    match size {
        StyleSize::Px(value) => px(value).into(),
        StyleSize::Full => relative(1.).into(),
        StyleSize::Fit => Length::Auto,
    }
}

fn resolve_color(color: StyleColor, colors: &ThemeColor) -> Hsla {
    match color {
        StyleColor::Hex(value) => rgba(value).into(),
        StyleColor::Token(token) => match token {
            ThemeToken::Background => colors.background,
            ThemeToken::Foreground => colors.foreground,
            ThemeToken::Primary => colors.primary,
            ThemeToken::PrimaryForeground => colors.primary_foreground,
            ThemeToken::Secondary => colors.secondary,
            ThemeToken::SecondaryForeground => colors.secondary_foreground,
            ThemeToken::Muted => colors.muted,
            ThemeToken::MutedForeground => colors.muted_foreground,
            ThemeToken::Accent => colors.accent,
            ThemeToken::AccentForeground => colors.accent_foreground,
            ThemeToken::Danger => colors.danger,
            ThemeToken::DangerForeground => colors.danger_foreground,
            ThemeToken::Border => colors.border,
            ThemeToken::Success => colors.success,
            ThemeToken::Warning => colors.warning,
            ThemeToken::Info => colors.info,
        },
    }
}

/// Applies a wire style to any styled element. `border_color` implies a 1 px
/// border so the color is visible; no border-width field exists in this milestone.
fn apply_style<T: Styled>(element: T, style: &Style, colors: &ThemeColor) -> T {
    let mut element = element;
    if let Some([top, right, bottom, left]) = style.padding {
        element = element
            .pt(px(top))
            .pr(px(right))
            .pb(px(bottom))
            .pl(px(left));
    }
    if let Some(gap) = style.gap {
        element = element.gap(px(gap));
    }
    if let Some(width) = style.width {
        element = element.w(style_length(width));
    }
    if let Some(height) = style.height {
        element = element.h(style_length(height));
    }
    if let Some(align) = style.align {
        element = match align {
            StyleAlign::Start => element.items_start(),
            StyleAlign::Center => element.items_center(),
            StyleAlign::End => element.items_end(),
            StyleAlign::Stretch => element.items_stretch(),
        };
    }
    if let Some(justify) = style.justify {
        element = match justify {
            StyleJustify::Start => element.justify_start(),
            StyleJustify::Center => element.justify_center(),
            StyleJustify::End => element.justify_end(),
            StyleJustify::SpaceBetween => element.justify_between(),
        };
    }
    if let Some(background) = style.background {
        element = element.bg(resolve_color(background, colors));
    }
    if let Some(foreground) = style.foreground {
        element = element.text_color(resolve_color(foreground, colors));
    }
    if let Some(border_color) = style.border_color {
        element = element
            .border_1()
            .border_color(resolve_color(border_color, colors));
    }
    if let Some(radius) = style.border_radius {
        element = element.rounded(px(radius));
    }
    if let Some(size) = style.font_size {
        element = element.text_size(px(size));
    }
    if let Some(weight) = style.font_weight {
        element = element.font_weight(match weight {
            StyleFontWeight::Normal => FontWeight::NORMAL,
            StyleFontWeight::Medium => FontWeight::MEDIUM,
            StyleFontWeight::Semibold => FontWeight::SEMIBOLD,
            StyleFontWeight::Bold => FontWeight::BOLD,
        });
    }
    element
}

#[cfg(test)]
mod tests;

impl Render for DartView {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.counters
            .materializations
            .set(self.counters.materializations.get() + 1);
        let colors = cx.theme().colors.clone();
        let content = match self.materialize(&self.snapshot.root, &colors) {
            Ok(content) => content,
            Err(message) => {
                self.fail(message, cx);
                div().child("Unable to render this view").into_any_element()
            }
        };
        let root = div()
            .id("gpuidart")
            .size_full()
            .overflow_y_scroll()
            .track_scroll(&self.scroll)
            .bg(cx.theme().background)
            .text_color(cx.theme().foreground)
            .child(div().w_full().p_5().child(content))
            .vertical_scrollbar(&self.scroll);
        #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
        let root = crate::input_trace::observe(root);
        root
    }
}

pub(crate) fn run(
    initial: Initial,
    receiver: Receiver<Command>,
    events: Events,
    trace: Arc<crate::trace::Trace>,
    before_quit: Option<Arc<dyn Fn() + Send + Sync>>,
) -> Result<(), String> {
    #[cfg(target_os = "linux")]
    if gpui::guess_compositor() != "X11" {
        return Err("This host currently supports Linux X11. Set DISPLAY and launch with WAYLAND_DISPLAY and ZED_HEADLESS unset. Native Wayland is not verified.".into());
    }
    #[cfg(target_os = "macos")]
    if unsafe { libc::pthread_main_np() } != 1 {
        return Err(
            "GPUI on macOS requires the process main thread; use the native companion launcher."
                .into(),
        );
    }
    let initial_key = crate::trace::Key {
        operation: "initial",
        request: 1,
    };
    trace.point("native.run", initial_key, None, None);
    let failure = Arc::new(std::sync::Mutex::new(None));
    let result = failure.clone();
    gpui_kit::application()
        .with_assets(gpui_kit::assets::Assets)
        .run(move |cx| {
            if let Some(before_quit) = before_quit {
                cx.on_app_quit(move |_| {
                    before_quit();
                    std::future::ready(())
                })
                .detach();
            }
            gpui_kit::init(cx);
            let options = WindowOptions {
                window_bounds: Some(WindowBounds::centered(
                    size(px(initial.window.width), px(initial.window.height)),
                    cx,
                )),
                titlebar: Some(TitlebarOptions {
                    title: Some(initial.window.title.clone().into()),
                    ..Default::default()
                }),
                ..Default::default()
            };
            let mut content = None;
            let opened = cx.open_window(options, |window, cx| {
                let view = cx.new(|cx| DartView::new(initial, events.clone(), window, cx));
                content = Some(view.clone());
                cx.new(|cx| gpui_kit::component::Root::new(view, window, cx))
            });
            let handle = match opened {
                Ok(handle) => handle,
                Err(error) => {
                    events.emit(Event::Error {
                        message: error.to_string(),
                    });
                    *failure.lock().unwrap_or_else(|error| error.into_inner()) =
                        Some(error.to_string());
                    cx.quit();
                    return;
                }
            };
            let Some(view) = content else {
                events.emit(Event::Error {
                    message: "Window opened without view content".into(),
                });
                *failure.lock().unwrap_or_else(|error| error.into_inner()) =
                    Some("Window opened without view content".into());
                cx.quit();
                return;
            };
            if let Some(message) = &view.read(cx).failure {
                *failure.lock().unwrap_or_else(|error| error.into_inner()) = Some(message.clone());
                cx.quit();
                return;
            }
            trace.point("native.window_opened", initial_key, None, None);
            cx.on_window_closed(|cx, _| {
                if cx.windows().is_empty() {
                    cx.quit();
                }
            })
            .detach();
            events.emit(Event::Ready);
            events.emit(Event::Applied {
                revision: view.read(cx).snapshot.revision,
                native_apply_us: 0,
            });
            cx.spawn(async move |cx| {
                while let Ok(command) = receiver.recv().await {
                    trace.point("native.dequeue", command.trace_key(), None, None);
                    let _dispatch = trace.dispatch(command.trace_key());
                    match command {
                        Command::Publish(snapshot) => {
                            if handle
                                .update(cx, |_, window, cx| {
                                    view.update(cx, |view, cx| view.publish(snapshot, window, cx))
                                })
                                .is_err()
                            {
                                break;
                            }
                        }
                        Command::Close => break,
                        Command::Dataset(update, parse_us) => {
                            if handle
                                .update(cx, |_, _, cx| {
                                    view.update(cx, |view, cx| {
                                        view.update_dataset(update, parse_us, cx)
                                    })
                                })
                                .is_err()
                            {
                                break;
                            }
                        }
                        Command::Diagnostic(request) => {
                            if handle
                                .update(cx, |_, window, cx| {
                                    crate::diagnostics::handle(request, &view, &events, window, cx)
                                })
                                .is_err()
                            {
                                break;
                            }
                        }
                    }
                }
                let _ = cx.update(|cx| cx.quit());
            })
            .detach();
        });
    let error = result
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .take();
    match error {
        Some(error) => Err(error),
        None => Ok(()),
    }
}
