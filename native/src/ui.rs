use crate::diagnostics::Counters;
use crate::{
    Command, Events,
    protocol::{Event, Node, Snapshot, TableData},
};
use async_channel::Receiver;
use gpui_kit::base::ScrollbarHandle;
use gpui_kit::component::{
    ActiveTheme, StyledExt,
    button::{Button, ButtonVariants},
    input::{Input, InputEvent, InputState},
    table::{Column, DataTable, TableDelegate, TableState},
};
use gpui_kit::*;
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    rc::Rc,
    sync::Arc,
};

struct Rows(Arc<TableData>, Rc<Counters>);

impl TableDelegate for Rows {
    fn columns_count(&self, _: &App) -> usize {
        self.0.columns.len()
    }
    fn rows_count(&self, _: &App) -> usize {
        self.0.rows.len()
    }
    fn column(&self, index: usize, _: &App) -> Column {
        Column::new(format!("column-{index}"), self.0.columns[index].clone()).width(px(200.))
    }
    fn render_td(
        &mut self,
        row: usize,
        col: usize,
        _: &mut Window,
        _: &mut Context<TableState<Self>>,
    ) -> impl IntoElement {
        self.1.cells.set(self.1.cells.get() + 1);
        div().child(self.0.rows[row][col].clone())
    }
    fn render_tr(
        &mut self,
        row: usize,
        _: &mut Window,
        _: &mut Context<TableState<Self>>,
    ) -> Stateful<Div> {
        self.1.rows.set(self.1.rows.get() + 1);
        div().id(("row", row))
    }
}

struct RetainedInput {
    state: Entity<InputState>,
    placeholder: String,
    _subscription: Subscription,
}

pub(crate) struct DartView {
    snapshot: Snapshot,
    events: Events,
    inputs: HashMap<String, RetainedInput>,
    tables: HashMap<String, Entity<TableState<Rows>>>,
    counters: Rc<Counters>,
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
            .map(|(id, entity)| {
                let table = entity.read(cx);
                let offset = table.vertical_scroll_handle.offset();
                (
                    id.clone(),
                    json!({
                        "entity": entity.entity_id().as_u64(),
                        "visible_rows": table.visible_range().rows(),
                        "row_count": table.delegate().0.rows.len(),
                        "scroll_y": f32::from(offset.y),
                    }),
                )
            })
            .collect::<serde_json::Map<_, _>>();
        let mut labels = serde_json::Map::new();
        self.snapshot.root.visit(&mut |node| {
            if let Node::Text { id, text } = node {
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
        json!({"revision": self.snapshot.revision, "inputs": inputs, "tables": tables, "labels": labels,
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
            || row >= table.read(cx).delegate().0.rows.len()
        {
            return Err("Invalid selection or row".into());
        }
        input.state.update(cx, |input, cx| {
            input.set_value(text.to_owned(), window, cx);
            input.set_selected_range(selection, cx);
            input.focus(window, cx);
        });
        table.update(cx, |table, cx| table.scroll_to_row(row, cx));
        cx.notify();
        Ok(())
    }

    fn new(
        snapshot: Snapshot,
        events: Events,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let mut view = Self {
            snapshot,
            events,
            inputs: HashMap::new(),
            tables: HashMap::new(),
            counters: Rc::new(Counters::default()),
        };
        view.reconcile(window, cx);
        view
    }

    fn publish(&mut self, snapshot: Snapshot, window: &mut Window, cx: &mut Context<Self>) {
        if snapshot.revision <= self.snapshot.revision {
            self.events.emit(Event::Error {
                message: "Revision must increase".into(),
            });
            return;
        }
        self.snapshot = snapshot;
        self.reconcile(window, cx);
        self.events.emit(Event::Applied {
            revision: self.snapshot.revision,
        });
        cx.notify();
    }

    fn reconcile(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let mut input_ids = HashSet::new();
        let mut table_ids = HashSet::new();
        self.snapshot.root.visit(&mut |node| match node {
            Node::Input { id, placeholder } => {
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
            Node::Table { id, data } => {
                table_ids.insert(id.clone());
                if let Some(table) = self.tables.get(id) {
                    table.update(cx, |table, cx| {
                        if table.delegate().0 != *data {
                            table.delegate_mut().0 = data.clone();
                            table.refresh(cx);
                            cx.notify();
                        }
                    });
                } else {
                    let table = cx.new(|cx| {
                        TableState::new(Rows(data.clone(), self.counters.clone()), window, cx)
                    });
                    self.tables.insert(id.clone(), table);
                }
            }
            _ => {}
        });
        self.inputs.retain(|id, _| input_ids.contains(id));
        self.tables.retain(|id, _| table_ids.contains(id));
    }

    fn materialize(&self, node: &Node) -> AnyElement {
        let id = SharedString::from(node.id().to_owned());
        match node {
            Node::Column { children, .. } => div()
                .id(id)
                .v_flex()
                .gap_3()
                .w_full()
                .children(children.iter().map(|child| self.materialize(child)))
                .into_any_element(),
            Node::Text { text, .. } => div().id(id).child(text.clone()).into_any_element(),
            Node::Button { label, .. } => {
                let events = self.events.clone();
                let event_id = node.id().to_owned();
                let revision = self.snapshot.revision;
                Button::new(id)
                    .primary()
                    .label(label.clone())
                    .on_click(move |_, _, _| {
                        events.emit(Event::Click {
                            revision,
                            id: event_id.clone(),
                        });
                    })
                    .into_any_element()
            }
            Node::Input { id, .. } => Input::new(&self.inputs[id].state)
                .id(SharedString::from(id.clone()))
                .into_any_element(),
            Node::Table { id, .. } => div()
                .id(SharedString::from(id.clone()))
                .w_full()
                .h(px(320.))
                .child(DataTable::new(&self.tables[id]).stripe(true).bordered(true))
                .into_any_element(),
        }
    }
}

#[cfg(test)]
mod tests;

impl Render for DartView {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.counters
            .materializations
            .set(self.counters.materializations.get() + 1);
        div()
            .id("gpuidart")
            .size_full()
            .p_5()
            .bg(cx.theme().background)
            .text_color(cx.theme().foreground)
            .child(self.materialize(&self.snapshot.root))
    }
}

pub(crate) fn run(
    initial: Snapshot,
    receiver: Receiver<Command>,
    events: Events,
) -> Result<(), String> {
    let failure = Arc::new(std::sync::Mutex::new(None));
    let result = failure.clone();
    gpui_kit::application()
        .with_assets(gpui_kit::assets::Assets)
        .run(move |cx| {
            gpui_kit::init(cx);
            let options = WindowOptions {
                window_bounds: Some(WindowBounds::centered(size(px(860.), px(650.)), cx)),
                titlebar: Some(TitlebarOptions {
                    title: Some("GPUI-Dart integration spike".into()),
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
                    *failure.lock().unwrap() = Some(error.to_string());
                    cx.quit();
                    return;
                }
            };
            let view = content.expect("window content");
            cx.on_window_closed(|cx, _| {
                if cx.windows().is_empty() {
                    cx.quit();
                }
            })
            .detach();
            events.emit(Event::Ready);
            events.emit(Event::Applied {
                revision: view.read(cx).snapshot.revision,
            });
            cx.spawn(async move |cx| {
                while let Ok(command) = receiver.recv().await {
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
    let error = result.lock().unwrap().take();
    match error {
        Some(error) => Err(error),
        None => Ok(()),
    }
}
