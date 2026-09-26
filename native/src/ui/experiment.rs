use super::*;
use crate::datasets::Upload;
use crate::experiment::{
    Incoming, Request, Setup,
    model::{self, Change as ExperimentChange, Strategy},
    reply,
};
use std::cell::Cell;
use std::time::Instant;

mod frame;
#[cfg(test)]
pub(super) use frame::BoundsProbe;
use frame::{Frame, FrameProbe};

pub(crate) fn validate_geometry(snapshot: &Snapshot) -> Result<(), String> {
    for node in model::children(&snapshot.root)? {
        if !matches!(node.style().and_then(|s| s.height), Some(StyleSize::Px(height)) if height > 0.)
        {
            return Err(
                "Experiment parts require positive fixed heights for equivalent cached layout"
                    .into(),
            );
        }
    }
    Ok(())
}

struct ExperimentView {
    strategy: Strategy,
    snapshot: Snapshot,
    datasets: Vec<Upload>,
    whole: Option<Entity<DartView>>,
    parts: HashMap<String, Entity<DartView>>,
    scroll: ScrollHandle,
    frame: Rc<Cell<Frame>>,
}

fn initial_for(snapshot: Snapshot, data: &[Upload]) -> Initial {
    let mut needed = HashSet::new();
    snapshot.root.visit(&mut |node| {
        if let Node::Table { dataset, .. } = node {
            needed.insert(dataset.clone());
        }
    });
    Initial {
        snapshot,
        datasets: data
            .iter()
            .filter(|d| needed.contains(&d.id))
            .map(|d| Upload {
                id: d.id.clone(),
                revision: d.revision,
                data: crate::protocol::TableData {
                    columns: d.data.columns.clone(),
                    rows: d.data.rows.clone(),
                    ids: d.data.ids.clone(),
                    format: d.data.format.clone(),
                },
            })
            .collect(),
        window: Default::default(),
    }
}
fn view_for(
    snapshot: Snapshot,
    data: &[Upload],
    embedded: bool,
    window: &mut Window,
    cx: &mut App,
) -> Entity<DartView> {
    let initial = initial_for(snapshot, data);
    cx.new(|cx| {
        let mut view = DartView::new(
            initial,
            Events(Arc::new(|event| {
                if let Event::Error { message } = event {
                    eprintln!("Experiment view: {message}");
                }
            })),
            window,
            cx,
        );
        view.embedded = embedded;
        #[cfg(test)]
        {
            view.experiment_bounds = Some(Rc::new(RefCell::new(HashMap::new())));
        }
        view
    })
}
impl ExperimentView {
    fn new(setup: Setup, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let mut this = Self {
            strategy: setup.strategy,
            snapshot: setup.initial.snapshot,
            datasets: setup.initial.datasets,
            whole: None,
            parts: HashMap::new(),
            scroll: ScrollHandle::new(),
            frame: Rc::new(Cell::new(Frame::default())),
        };
        if this.strategy == Strategy::Subviews {
            for node in model::children(&this.snapshot.root).expect("validated experiment root") {
                let snapshot = Snapshot {
                    revision: 1,
                    actions: Vec::new(),
                    root: node.clone(),
                };
                this.parts.insert(
                    node.id().to_owned(),
                    view_for(snapshot, &this.datasets, true, window, cx),
                );
            }
        } else {
            this.whole = Some(view_for(
                this.snapshot.clone(),
                &this.datasets,
                false,
                window,
                cx,
            ));
        }
        this
    }
    fn update_description(
        &mut self,
        base: u64,
        revision: u64,
        change: ExperimentChange,
        resync: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Result<Value, String> {
        let candidate = model::propose(
            &self.snapshot,
            self.strategy,
            base,
            revision,
            change,
            resync,
        )?;
        let validation = Instant::now();
        validate_geometry(&candidate.snapshot)?;
        datasets::validate_references(&candidate.snapshot, |id| {
            self.datasets.iter().any(|d| d.id == id)
        })?;
        datasets::validate_views(&candidate.snapshot, |id| {
            self.datasets
                .iter()
                .find(|d| d.id == id)
                .map(|d| d.data.columns.len())
        })?;
        let validation_us = candidate.validation_us + validation.elapsed().as_micros() as u64;
        let applying = Instant::now();
        if let Some(whole) = &self.whole {
            whole.update(cx, |view, cx| {
                view.publish(candidate.snapshot.clone(), window, cx)
            });
        } else {
            let nodes = model::children(&candidate.snapshot.root)?;
            let ids: HashSet<_> = nodes.iter().map(|node| node.id()).collect();
            self.parts.retain(|id, _| ids.contains(id.as_str()));
            for node in nodes {
                if let Some(part) = self.parts.get(node.id()) {
                    if candidate.changed_parts.iter().any(|id| id == node.id()) {
                        let snapshot = Snapshot {
                            revision,
                            actions: Vec::new(),
                            root: node.clone(),
                        };
                        part.update(cx, |view, cx| view.publish(snapshot, window, cx));
                    }
                } else {
                    let snapshot = Snapshot {
                        revision,
                        actions: Vec::new(),
                        root: node.clone(),
                    };
                    self.parts.insert(
                        node.id().to_owned(),
                        view_for(snapshot, &self.datasets, true, window, cx),
                    );
                }
            }
        }
        self.snapshot = candidate.snapshot;
        cx.notify();
        Ok(
            json!({"staging_us":candidate.staging_us, "validation_us":validation_us,
            "application_us":applying.elapsed().as_micros() as u64}),
        )
    }
    fn prepare(&mut self, window: &mut Window, cx: &mut Context<Self>) -> Result<(), String> {
        let input_view = self
            .whole
            .as_ref()
            .or_else(|| self.parts.get("retained-input"))
            .ok_or("No input owner")?;
        let input = input_view
            .read(cx)
            .inputs
            .get("retained-input")
            .ok_or("No retained input")?
            .state
            .clone();
        let table_view = self
            .whole
            .as_ref()
            .or_else(|| self.parts.get("retained-table"))
            .ok_or("No table owner")?;
        let table = table_view
            .read(cx)
            .tables
            .get("retained-table")
            .ok_or("No retained table")?
            .state
            .clone();
        input.update(cx, |state, cx| {
            state.set_value("retained selection", window, cx);
            state.set_selected_range(1..7, cx);
            state.focus(window, cx);
        });
        table.update(cx, |state, cx| state.scroll_to_row(800, cx));
        cx.notify();
        Ok(())
    }
    fn inspect(&self, window: &Window, cx: &App) -> Value {
        let mut inputs = serde_json::Map::new();
        let mut tables = serde_json::Map::new();
        let mut labels = serde_json::Map::new();
        let mut counts = serde_json::Map::new();
        for view in self.whole.iter().chain(self.parts.values()) {
            let value = view.read(cx).inspect(window, cx);
            inputs.extend(value["inputs"].as_object().unwrap().clone());
            tables.extend(value["tables"].as_object().unwrap().clone());
            labels.extend(value["labels"].as_object().unwrap().clone());
            for (key, value) in value["native"].as_object().unwrap() {
                let sum = counts.get(key).and_then(Value::as_u64).unwrap_or(0)
                    + value.as_u64().unwrap_or(0);
                counts.insert(key.clone(), json!(sum));
            }
        }
        let frames = window.frame_duration_snapshot();
        json!({"revision":self.snapshot.revision, "inputs":inputs,"tables":tables,"labels":labels,"native":counts,
            "part_materializations":self.parts.iter().map(|(id,view)| (id.clone(),view.read(cx).materialization_count())).collect::<HashMap<_,_>>(),
            "window":{"width":f32::from(window.viewport_size().width),"height":f32::from(window.viewport_size().height),"scale_factor":window.scale_factor()},
            "draw":{"samples":frames.draw_duration_histogram.len(),"p50_us":frames.draw_duration_histogram.value_at_quantile(0.5) as f64 / 1000.,"p95_us":frames.draw_duration_histogram.value_at_quantile(0.95) as f64 / 1000.},
            "frame":self.frame.get()})
    }
}

#[cfg(test)]
mod tests;
impl Render for ExperimentView {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let content = if let Some(whole) = &self.whole {
            whole.clone().into_any_element()
        } else {
            let colors = cx.theme().colors.clone();
            let nodes = model::children(&self.snapshot.root).expect("validated experiment root");
            let body = apply_node_style(
                div()
                    .id(SharedString::from(self.snapshot.root.id().to_owned()))
                    .v_flex()
                    .gap_3()
                    .w_full()
                    .children(nodes.iter().map(|node| {
                        let height = match node.style().and_then(|s| s.height) {
                            Some(StyleSize::Px(height)) => height,
                            _ => unreachable!("validated experiment height"),
                        };
                        let mut size = div().w_full().h(px(height));
                        self.parts
                            .get(node.id())
                            .expect("committed part")
                            .clone()
                            .cached(size.style().clone())
                    })),
                &self.snapshot.root,
                &colors,
            );
            div()
                .id("gpuidart")
                .size_full()
                .overflow_y_scroll()
                .track_scroll(&self.scroll)
                .bg(cx.theme().background)
                .text_color(cx.theme().foreground)
                .child(div().w_full().p_5().child(body))
                .vertical_scrollbar(&self.scroll)
                .into_any_element()
        };
        FrameProbe::new(content, self.snapshot.revision, self.frame.clone())
    }
}

fn after_paint(
    view: Entity<ExperimentView>,
    previous: u64,
    mut response: Value,
    window: &mut Window,
    cx: &mut App,
) {
    if view.read(cx).frame.get().serial > previous {
        response["state"] = view.read(cx).inspect(window, cx);
        reply(&response);
        return;
    }
    view.update(cx, |_, cx| cx.notify());
    window.on_next_frame(move |window, cx| after_paint(view, previous, response, window, cx));
}

pub(crate) fn run(setup: Setup, receiver: Receiver<Incoming>) -> Result<(), String> {
    #[cfg(windows)]
    unsafe {
        #[link(name = "user32")]
        unsafe extern "system" {
            fn SetProcessDpiAwarenessContext(value: isize) -> i32;
        }
        SetProcessDpiAwarenessContext(-4);
    }
    let failure = Arc::new(std::sync::Mutex::new(None));
    let result = failure.clone();
    gpui_kit::application().with_assets(gpui_kit::assets::Assets).run(move |cx| {
        gpui_kit::init(cx);
        let options = WindowOptions {
            window_bounds:Some(WindowBounds::centered(size(px(setup.initial.window.width),px(setup.initial.window.height)),cx)),
            titlebar:Some(TitlebarOptions{title:Some("Snapshot strategy experiment".into()),..Default::default()}),
            ..Default::default()
        };
        let mut content = None;
        let opened = cx.open_window(options, |window,cx| {
            let view = cx.new(|cx| ExperimentView::new(setup,window,cx));
            content = Some(view.clone());
            cx.new(|cx| gpui_kit::component::Root::new(view,window,cx))
        });
        let (handle,view) = match (opened, content) {
            (Ok(handle),Some(view)) => (handle,view),
            (Err(error),_) => { *failure.lock().unwrap()=Some(error.to_string()); cx.quit(); return; }
            _ => { *failure.lock().unwrap()=Some("Missing experiment view".into()); cx.quit(); return; }
        };
        let _ = handle.update(cx, |_,window,cx| after_paint(view.clone(),0,json!({"request":0,"passed":true,"ready":true}),window,cx));
        cx.on_window_closed(|cx,_| { if cx.windows().is_empty() { cx.quit(); } }).detach();
        cx.spawn(async move |cx| {
            while let Ok(incoming) = receiver.recv().await {
                let close = matches!(incoming.request,Ok(Request::Close{..}));
                if handle.update(cx, |_,window,cx| {
                    let request = match incoming.request {
                        Ok(request) => request,
                        Err(error) => { reply(&json!({"request":0,"passed":false,"error":error,"decode_us":incoming.decode_us})); return; }
                    };
                    let mut response = json!({"request":request.id(),"passed":true,"bytes":incoming.bytes,"decode_us":incoming.decode_us});
                    let previous = view.read(cx).frame.get().serial;
                    match request {
                        Request::Update { base,revision,change,resync,.. } => {
                            match view.update(cx, |view,cx| view.update_description(base,revision,change,resync,window,cx)) {
                                Ok(stages) => response["stages"]=stages,
                                Err(error) => { response["passed"]=json!(false); response["error"]=json!(error); response["state"]=view.read(cx).inspect(window,cx); reply(&response); return; }
                            }
                            after_paint(view.clone(),previous,response,window,cx);
                        }
                        Request::Prepare { .. } => {
                            if let Err(error) = view.update(cx, |view,cx| view.prepare(window,cx)) { response["passed"]=json!(false); response["error"]=json!(error); }
                            after_paint(view.clone(),previous,response,window,cx);
                        }
                        Request::Inspect { .. } | Request::Close { .. } => {
                            response["state"]=view.read(cx).inspect(window,cx);
                            response["runtime"]=crate::runtime_info::read();
                            reply(&response);
                        }
                    }
                }).is_err() || close { break; }
            }
            let _=cx.update(|cx| cx.quit());
        }).detach();
    });
    result.lock().unwrap().take().map_or(Ok(()), Err)
}
