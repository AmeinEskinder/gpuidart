use crate::datasets::{self, Change, Edit, Initial, SharedDataset, Store, Update};
use crate::diagnostics::Counters;
use crate::{
    Command, Events,
    protocol::{
        Align as StyleAlign, CellIcon, Color as StyleColor, Draw, Easing, Event,
        FontWeight as StyleFontWeight, ImageEncoding, ImageFit, IndexPatch,
        Justify as StyleJustify, KeystrokeSpec, MenuEntry, Node, ScrollAxis, Size as StyleSize,
        Snapshot, Style, TableData, TableView, ThemeToken, Touched, TreeIndex, ViewEntry,
        ViewIndex, apply_in_place, rollback,
    },
};
use async_channel::Receiver;
use gpui::{ScrollStrategy, UniformListScrollHandle, uniform_list};
use gpui_kit::assets::IconName;
use gpui_kit::base::{ScrollbarHandle, TestSupportExt};
use gpui_kit::component::WindowExt as _;
use gpui_kit::component::theme::ThemeColor;
use gpui_kit::component::{
    ActiveTheme, Disableable, Icon, IconNamed, Sizable, StyledExt,
    button::{Button, ButtonVariants, DropdownButton},
    checkbox::Checkbox,
    input::{Input, InputEvent, InputState},
    menu::PopupMenuItem,
    progress::Progress,
    scroll::ScrollableElement,
    separator::Separator,
    switch::Switch,
    table::{Column, DataTable, TableDelegate, TableEvent, TableState},
};
use gpui_kit::gpui::{
    Animation, AnimationExt, BorderStyle, PathBuilder, bounce, canvas, ease_in_out, ease_out_quint,
    linear, quad,
};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use serde_json::{Value, json};
use std::{
    cell::{Cell, RefCell},
    collections::{HashMap, HashSet, VecDeque},
    rc::Rc,
    sync::Arc,
    time::{Duration, Instant},
};

struct Rows {
    owner: WeakEntity<DartView>,
    has_context_menu: bool,
    table_id: String,
    data: SharedDataset,
    /// View index: view row -> source row. Identity mapping when the table
    /// has no view.
    index: Rc<RefCell<ViewIndex>>,
    counters: Rc<Counters>,
}

impl Rows {
    fn entry(&self, view_row: usize) -> ViewEntry {
        self.index.borrow().entries[view_row]
    }

    /// The text of a group header cell: the key with its count in the
    /// grouped column, an aggregate in its column, nothing elsewhere.
    fn group_cell(&self, group: usize, col: usize) -> String {
        let index = self.index.borrow();
        let summary = &index.groups[group];
        if col == summary.column {
            return format!("{} ({})", summary.key, summary.count);
        }
        let Some((_, text)) = summary.aggregates.iter().find(|(column, _)| *column == col) else {
            return String::new();
        };
        let data = self.data.borrow();
        match data.data.format.as_ref().and_then(|f| f.columns.get(&col)) {
            Some(format) => format.apply(text).text,
            None => text.clone(),
        }
    }

    fn record_key(&self, source: usize) -> String {
        let data = self.data.borrow();
        match &data.data.ids {
            Some(ids) => json!([self.table_id, data.id, "record", ids[source]]).to_string(),
            None => json!([self.table_id, data.id, "source", source]).to_string(),
        }
    }
}

impl TableDelegate for Rows {
    fn columns_count(&self, _: &App) -> usize {
        self.data.borrow().data.columns.len()
    }
    fn rows_count(&self, _: &App) -> usize {
        self.index.borrow().entries.len()
    }
    fn column(&self, index: usize, _: &App) -> Column {
        Column::new(
            format!("column-{index}"),
            self.data.borrow().data.columns[index].clone(),
        )
        .width(px(200.))
    }
    fn render_th(
        &mut self,
        col: usize,
        _: &mut Window,
        _: &mut Context<TableState<Self>>,
    ) -> impl IntoElement {
        let label = self.data.borrow().data.columns[col].clone();
        div()
            .id(("column-header", col))
            .role(Role::ColumnHeader)
            .accessibility_id(json!([self.table_id, "column", col]).to_string())
            .aria_column_index(col)
            .test_support()
            .aria_label(label.clone())
            .size_full()
            .child(label)
    }
    fn render_td(
        &mut self,
        row: usize,
        col: usize,
        _: &mut Window,
        cx: &mut Context<TableState<Self>>,
    ) -> impl IntoElement {
        self.counters.cells.set(self.counters.cells.get() + 1);
        let source = match self.entry(row) {
            ViewEntry::Record(source) => source,
            ViewEntry::Group(group) => {
                let text = self.group_cell(group, col);
                let cell_id = json!([self.table_id, "group", group, "cell", col]).to_string();
                return div()
                    .id(SharedString::from(cell_id.clone()))
                    .accessibility_id(cell_id)
                    .role(Role::Cell)
                    .test_support()
                    .aria_row_index(row)
                    .aria_column_index(col)
                    .aria_label(text.clone())
                    .font_weight(FontWeight::SEMIBOLD)
                    .child(text)
                    .into_any_element();
            }
        };
        let data = self.data.borrow();
        let raw = data.data.rows[source][col].clone();
        let cell_id = json!([self.record_key(source), "cell", col]).to_string();
        let semantic_cell = div()
            .id(SharedString::from(cell_id.clone()))
            .accessibility_id(cell_id)
            .role(Role::Cell)
            .test_support()
            .aria_row_index(row)
            .aria_column_index(col);
        let Some(format) = data
            .data
            .format
            .as_ref()
            .and_then(|format| format.columns.get(&col))
        else {
            return semantic_cell
                .aria_label(raw.clone())
                .child(raw)
                .into_any_element();
        };
        let formatted = format.apply(&raw);
        let colors = cx.theme().colors.clone();
        let color = formatted.color.map(|color| resolve_color(color, &colors));
        let mut cell = semantic_cell
            .aria_label(formatted.text.clone())
            .child(formatted.text);
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
        cx: &mut Context<TableState<Self>>,
    ) -> Stateful<Div> {
        self.counters.rows.set(self.counters.rows.get() + 1);
        // Key real rows by source record so element identity survives view
        // changes; the table also asks for filler rows past the view's end.
        match self.index.borrow().entries.get(row) {
            Some(&ViewEntry::Group(group)) => div()
                .id(("group-row", group))
                .accessibility_id(json!([self.table_id, "group", group]).to_string())
                .aria_row_index(row)
                .bg(cx.theme().muted),
            Some(&ViewEntry::Record(source)) => {
                let key = self.record_key(source);
                let row_element = div()
                    .id(SharedString::from(key.clone()))
                    .accessibility_id(key)
                    .aria_row_index(row)
                    .on_a11y_action(AccessibleAction::Click, {
                        let table = cx.entity().downgrade();
                        let source_key = self.record_key(source);
                        move |_, _, cx| {
                            let _ = table.update(cx, |table, cx| {
                                // Resolve against the current view: an OS client may invoke
                                // an old frame after a sort/filter has already been applied.
                                let current = {
                                    let rows = table.delegate();
                                    rows.index.borrow().entries.iter().position(|entry| {
                                        matches!(entry, ViewEntry::Record(source)
                                            if rows.record_key(*source) == source_key)
                                    })
                                };
                                if let Some(row) = current {
                                    table.set_selected_row(row, cx);
                                }
                            });
                        }
                    });
                self.context_row(row_element, source, cx)
            }
            None => div().id(("row-filler", row)),
        }
    }
}

struct RetainedInput {
    state: Entity<InputState>,
    placeholder: String,
    _subscription: Subscription,
    _observer: Subscription,
    version: crate::input_control::State,
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
    /// The view job in flight, if any.
    pending: Option<PendingView>,
}

/// Records at or above this count compute their view index off the frame
/// thread; below it the compute costs less than a frame and runs in place.
const VIEW_JOB_ROWS: usize = 10_000;

/// A view job in flight: the table keeps showing its last index, adjusted
/// for the records edited under it, until the job's result swaps in.
struct PendingView {
    job: u64,
    reset_scroll: bool,
    /// The selection the job resolves; one made while it ran is resolved
    /// again at the swap.
    selected_record: Option<String>,
    started: Instant,
    _task: gpui::Task<()>,
}

/// What a view job reads: the spec, a snapshot of the records, and the
/// selection and first visible entry to carry across the swap.
struct ViewInputs {
    spec: Option<TableView>,
    records: Arc<TableData>,
    selected_record: Option<String>,
    anchor_source: Option<ViewEntry>,
}

struct ViewResult {
    index: ViewIndex,
    /// The selected record's row in the new index, when it is still shown.
    selection_row: Option<usize>,
    /// The first visible entry's row in the new index, when it is still shown.
    anchor_view: Option<usize>,
}

impl ViewInputs {
    fn compute(&self) -> ViewResult {
        let index = ViewIndex::compute(self.spec.as_ref(), &self.records);
        let selection_row = match (&self.selected_record, &self.records.ids) {
            (Some(record), Some(ids)) => ids
                .iter()
                .position(|id| id == record)
                .and_then(|source| index.row_of(ViewEntry::Record(source))),
            _ => None,
        };
        let anchor_view = self.anchor_source.and_then(|entry| index.row_of(entry));
        ViewResult {
            index,
            selection_row,
            anchor_view,
        }
    }
}

/// What a dataset change does to the index a table shows while the next
/// one computes.
enum IndexChange {
    /// The spec changed under the same records: the last index stays.
    None,
    /// New records: dataset order.
    Replace,
    /// Records appended: shown behind the last index in dataset order.
    Append,
    /// Records inserted, deleted or moved: the last index follows them.
    Edits(Vec<IndexPatch>),
}

/// A dataset update that arrived while a view job read the dataset.
struct QueuedUpdate {
    update: Update,
    parse_us: u64,
}

/// Frames this view rendered since the `frame_gaps` diagnostic last marked
/// it: how many, and the longest interval between two of them. The frame
/// before the mark starts the first interval, so a stall that begins at
/// the mark is measured in full.
struct FrameGaps {
    marked: Instant,
    last_frame: Option<Instant>,
    frames: u64,
    longest: Duration,
}

impl FrameGaps {
    fn new() -> Self {
        Self {
            marked: Instant::now(),
            last_frame: None,
            frames: 0,
            longest: Duration::ZERO,
        }
    }

    fn frame(&mut self, now: Instant) {
        if let Some(last) = self.last_frame {
            self.longest = self.longest.max(now - last);
        }
        self.last_frame = Some(now);
        self.frames += 1;
    }

    fn read(&self) -> Value {
        json!({
            "frames": self.frames,
            "longest_gap_us": self.longest.as_micros() as u64,
            "since_mark_us": self.marked.elapsed().as_micros() as u64,
        })
    }

    fn mark(&mut self) {
        self.marked = Instant::now();
        self.frames = 0;
        self.longest = Duration::ZERO;
    }
}

/// A list over one dataset column: the shared records, the view index its
/// items follow and the scroll position retained by node ID.
struct RetainedList {
    data: SharedDataset,
    index: Rc<RefCell<ViewIndex>>,
    view: Option<TableView>,
    scroll: UniformListScrollHandle,
}

/// A container kept as its own GPUI entity and rendered through a cached
/// element, so frames reuse its rendered subtree until a change touches it.
struct RetainedSubtree {
    view: Entity<SubtreeView>,
    height: f32,
}

/// Renders one cached container of the owning view on demand. The owner is
/// read, never borrowed mutably, so the shared retained state serves both.
struct SubtreeView {
    owner: gpui::WeakEntity<DartView>,
    id: String,
    renders: Cell<u64>,
}

impl Render for SubtreeView {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.renders.set(self.renders.get() + 1);
        let Some(owner) = self.owner.upgrade() else {
            return div().into_any_element();
        };
        let colors = cx.theme().colors.clone();
        let owner = owner.read(cx);
        match crate::protocol::node_by_id(&owner.snapshot.root, &owner.index, &self.id) {
            Some(node) => owner
                .materialize_node(node, &colors, cx, true)
                .unwrap_or_else(|_| div().into_any_element()),
            None => div().into_any_element(),
        }
    }
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

/// A Lucide icon addressed by its asset path, for names that arrive as text.
struct LucideIcon(SharedString);

impl IconNamed for LucideIcon {
    fn path(self) -> SharedString {
        self.0
    }
}

struct RetainedImage {
    hash: u64,
    image: Arc<gpui::Image>,
}

/// A tree's Kit state, kept by node ID across publications.
struct RetainedTree {
    state: Entity<gpui_kit::component::tree::TreeState>,
    items: Vec<crate::protocol::TreeItemSpec>,
    selected: Option<String>,
    _subscription: gpui_kit::gpui::Subscription,
}

fn build_tree_items(
    specs: &[crate::protocol::TreeItemSpec],
) -> Vec<gpui_kit::component::tree::TreeItem> {
    specs
        .iter()
        .map(|spec| {
            gpui_kit::component::tree::TreeItem::new(spec.id.clone(), spec.label.clone())
                .expanded(spec.expanded)
                .disabled(spec.disabled)
                .children(build_tree_items(&spec.children))
        })
        .collect()
}

/// A resizable pane group's Kit state, kept by node ID across publications.
struct RetainedPanes {
    state: Entity<gpui_kit::base::ResizableState>,
    axis: crate::protocol::PanesAxis,
    published: Vec<crate::protocol::PaneSpec>,
    _subscription: gpui_kit::gpui::Subscription,
}

pub(crate) struct DartView {
    #[cfg(all(test, feature = "snapshot-experiment"))]
    experiment_bounds: Option<Rc<RefCell<HashMap<String, Bounds<Pixels>>>>>,
    #[cfg(feature = "snapshot-experiment")]
    embedded: bool,
    snapshot: Snapshot,
    applied_theme: Option<crate::protocol::ThemeSpec>,
    applied_menus: menus::AppliedMenus,
    menu_bar: Option<Entity<gpui_kit::component::menu::AppMenuBar>>,
    trace: Option<Arc<crate::trace::Trace>>,
    events: Events,
    inputs: HashMap<String, RetainedInput>,
    next_input_generation: u64,
    charts: HashMap<String, charts::RetainedChart>,
    choices: HashMap<String, choices::RetainedChoices>,
    sliders: HashMap<String, controls::RetainedSlider>,
    selects: HashMap<String, controls::RetainedSelect>,
    date_pickers: HashMap<String, controls::RetainedDatePicker>,
    active_dialog: dialogs::ActiveDialog,
    /// Checkbox and switch values toggled by the user since the last commit.
    /// Shown until the next publication, whose values are authoritative.
    checkbox_shown: Rc<RefCell<HashMap<String, bool>>>,
    /// Radio options and tabs chosen by the user since the last commit, by node.
    choice_shown: Rc<RefCell<HashMap<String, String>>>,
    /// Scroll containers keep their offset by ID across publications.
    scrolls: HashMap<String, ScrollHandle>,
    /// Resizable pane groups by node ID: the Kit state that holds the
    /// dragged sizes, the axis it was built for and the specs last published.
    panes: HashMap<String, RetainedPanes>,
    /// Trees by node ID: the Kit state holding the entries, their expansion
    /// and the selection, with the items and selection last published.
    trees: HashMap<String, RetainedTree>,
    /// The sheet node whose sheet the window shows, if any.
    active_sheet: Option<String>,
    /// Set by a publication that carries or drops a sheet. Once the window
    /// has rendered (so Kit's window root exists) a publication reconciles
    /// the sheet at once, and its acknowledgement covers it; before that the
    /// first frame reconciles after it has rendered.
    sheets_dirty: bool,
    root_ready: bool,
    row_menu: Option<row_menus::Session>,
    next_row_menu: u64,
    tables: HashMap<String, RetainedTable>,
    lists: HashMap<String, RetainedList>,
    /// View jobs started, numbering them so a superseded job's result is
    /// told from the current one's.
    view_jobs: u64,
    frame_gaps: FrameGaps,
    /// Dataset updates by dataset ID, in arrival order, waiting for a view
    /// job over that dataset to land.
    queued_updates: HashMap<String, VecDeque<QueuedUpdate>>,
    /// Cached containers by node ID.
    subtrees: HashMap<String, RetainedSubtree>,
    /// Decoded inline images by node ID, so a frame reuses the decode and
    /// GPUI's cache sees one image identity per node and content.
    images: RefCell<HashMap<String, RetainedImage>>,
    /// This view, for element handlers built outside its own render.
    handle: gpui::WeakEntity<DartView>,
    /// IDs and parents of the applied tree, kept in step by operation updates.
    index: TreeIndex,
    /// The last revision whose content paint the input trace recorded.
    #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
    painted_revision: std::rc::Rc<std::cell::Cell<u64>>,
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

    /// The frames rendered since the last mark, marking again if asked.
    pub(crate) fn frame_gaps(&mut self, mark: bool) -> Value {
        let gaps = self.frame_gaps.read();
        if mark {
            self.frame_gaps.mark();
        }
        gaps
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
                let view_rows = table.delegate().index.borrow().entries.len();
                let groups = table.delegate().index.borrow().groups.len();
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
                        "view": {"source_rows": source_rows, "view_rows": view_rows, "groups": groups, "spec_hash": spec_hash, "pending": retained.pending.is_some()},
                        "selection": {"row": table.selected_row(), "record": retained.selected_record},
                        "focused": table.focus_handle(cx).is_focused(window),
                    }),
                )
            })
            .collect::<serde_json::Map<_, _>>();
        let trees = self
            .trees
            .iter()
            .map(|(id, retained)| {
                let state = retained.state.read(cx);
                let entries: Vec<serde_json::Value> = (0..)
                    .map_while(|ix| state.entry(ix))
                    .map(|entry| {
                        json!({"id": entry.item().id.to_string(), "depth": entry.depth(), "expanded": entry.is_expanded(), "folder": entry.is_folder()})
                    })
                    .collect();
                (
                    id.clone(),
                    json!({"selected": state.selected_item().map(|item| item.id.to_string()), "entries": entries}),
                )
            })
            .collect::<serde_json::Map<_, _>>();
        let scrolls = self
            .scrolls
            .iter()
            .map(|(id, handle)| {
                let offset = handle.offset();
                (
                    id.clone(),
                    json!({"x": f32::from(offset.x), "y": f32::from(offset.y)}),
                )
            })
            .collect::<serde_json::Map<_, _>>();
        let panes = self
            .panes
            .iter()
            .map(|(id, retained)| {
                let sizes: Vec<f32> = retained
                    .state
                    .read(cx)
                    .sizes()
                    .iter()
                    .map(|size| f32::from(*size))
                    .collect();
                (id.clone(), json!(sizes))
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
        let lists = self
            .lists
            .iter()
            .map(|(id, list)| {
                (
                    id.clone(),
                    json!({
                        "dataset": list.data.borrow().id,
                        "dataset_revision": list.data.borrow().revision,
                        "view_rows": list.index.borrow().entries.len(),
                        "selected_shown": self.choice_shown.borrow().get(id),
                    }),
                )
            })
            .collect::<serde_json::Map<String, Value>>();
        let subtrees = self
            .subtrees
            .iter()
            .map(|(id, retained)| {
                (
                    id.clone(),
                    json!({"renders": retained.view.read(cx).renders.get(), "height": retained.height}),
                )
            })
            .collect::<serde_json::Map<String, Value>>();
        let mut native = self.counters.read();
        native["dataset_copies"] = json!(self.datasets.copies.get());
        json!({"charts": self.inspect_charts(), "theme": self.inspect_theme(cx), "revision": self.snapshot.revision, "native_process_id": std::process::id(), "inputs": inputs, "tables": tables, "lists": lists, "subtrees": subtrees, "labels": labels, "scrolls": scrolls, "panes": panes, "trees": trees, "active_sheet": self.active_sheet.clone(), "controls": self.inspect_controls(window, cx),
            "focus_handle": window.focused(cx).map(|focus| format!("{focus:?}")),
            "window": {"width": f32::from(window.viewport_size().width), "height": f32::from(window.viewport_size().height), "scale_factor": window.scale_factor(), "scroll_y": f32::from(self.scroll.offset().y)},
            "native": native,
            "frame_gaps": self.frame_gaps.read(),
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
        let handle = cx.entity().downgrade();
        let this = cx.entity();
        let key_interceptor = cx.intercept_keystrokes(move |event, window, cx| {
            let view = this.read(cx);
            let Some((name, context)) = view.match_action(&event.keystroke, window, cx) else {
                if event.keystroke.key == "f10"
                    && event.keystroke.modifiers.shift
                    && !event.keystroke.modifiers.control
                    && !event.keystroke.modifiers.alt
                    && !event.keystroke.modifiers.platform
                {
                    let opened = this.update(cx, |view, cx| view.keyboard_row_menu(window, cx));
                    if opened {
                        window.prevent_default();
                        cx.stop_propagation();
                    }
                }
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
            #[cfg(all(test, feature = "snapshot-experiment"))]
            experiment_bounds: None,
            #[cfg(feature = "snapshot-experiment")]
            embedded: false,
            trace: None,
            index: TreeIndex::of(&initial.snapshot.root),
            #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
            painted_revision: Default::default(),
            snapshot: initial.snapshot,
            applied_theme: None,
            applied_menus: None,
            menu_bar: None,
            datasets: Store::new(initial.datasets),
            events,
            inputs: HashMap::new(),
            next_input_generation: 0,
            charts: HashMap::new(),
            choices: HashMap::new(),
            sliders: HashMap::new(),
            selects: HashMap::new(),
            date_pickers: HashMap::new(),
            active_dialog: Default::default(),
            checkbox_shown: Default::default(),
            choice_shown: Default::default(),
            scrolls: HashMap::new(),
            panes: HashMap::new(),
            trees: HashMap::new(),
            active_sheet: None,
            sheets_dirty: false,
            root_ready: false,
            row_menu: None,
            next_row_menu: 0,
            tables: HashMap::new(),
            lists: HashMap::new(),
            view_jobs: 0,
            frame_gaps: FrameGaps::new(),
            queued_updates: HashMap::new(),
            subtrees: HashMap::new(),
            images: RefCell::new(HashMap::new()),
            table_subscriptions: HashMap::new(),
            scroll: ScrollHandle::new(),
            counters: Rc::new(Counters::default()),
            failure: None,
            _key_interceptor: key_interceptor,
            handle,
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
        if let Err(message) = snapshot.validate() {
            self.events.emit(Event::Rejected {
                revision: snapshot.revision,
                message,
            });
            return;
        }
        self.commit(snapshot, timer, window, cx);
    }

    /// Applies operations computed against the applied revision. A stale base
    /// or a failing operation rejects the update and leaves the description.
    fn apply_update(
        &mut self,
        update: crate::protocol::Update,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let timer = Instant::now();
        if update.base_revision != self.snapshot.revision {
            self.events.emit(Event::Rejected {
                revision: update.revision,
                message: format!(
                    "Stale base revision {}; the applied revision is {}",
                    update.base_revision, self.snapshot.revision
                ),
            });
            return;
        }
        let (touched, undo) =
            match apply_in_place(&mut self.snapshot.root, &mut self.index, &update) {
                Ok(applied) => applied,
                Err(message) => {
                    self.events.emit(Event::Rejected {
                        revision: update.revision,
                        message,
                    });
                    return;
                }
            };
        if let Err(message) = self.check_update(&update, &touched) {
            rollback(&mut self.snapshot.root, &mut self.index, undo);
            self.events.emit(Event::Rejected {
                revision: update.revision,
                message,
            });
            return;
        }
        self.snapshot.revision = update.revision;
        self.snapshot.actions = update.actions;
        self.snapshot.menus = update.menus;
        self.snapshot.theme = update.theme;
        self.finish_commit(timer, window, cx);
        self.notify_subtrees(
            touched
                .set
                .iter()
                .chain(&touched.inserted)
                .chain(&touched.structure)
                .map(String::as_str),
            cx,
        );
    }

    fn commit(
        &mut self,
        snapshot: Snapshot,
        timer: Instant,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if let Err(message) =
            datasets::validate_references(&snapshot, |id| self.datasets.entries.contains_key(id))
                .and_then(|_| {
                    datasets::validate_context_menus(&snapshot, |id| {
                        self.datasets
                            .entries
                            .get(id)
                            .is_some_and(|data| data.borrow().data.ids.is_some())
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
        self.index = TreeIndex::of(&self.snapshot.root);
        self.finish_commit(timer, window, cx);
        let all: Vec<String> = self.subtrees.keys().cloned().collect();
        self.notify_subtrees(all.iter().map(String::as_str), cx);
    }

    /// Shared tail of whole and operation commits: shown control values
    /// yield to the publication, retained entities reconcile, and the
    /// application learns the revision.
    fn finish_commit(&mut self, timer: Instant, window: &mut Window, cx: &mut Context<Self>) {
        self.checkbox_shown.borrow_mut().clear();
        self.choice_shown.borrow_mut().clear();
        if let Err(message) = self.reconcile(window, cx) {
            self.fail(message, cx);
            return;
        }
        self.events.emit(Event::Applied {
            revision: self.snapshot.revision,
            native_apply_us: timer.elapsed().as_micros() as u64,
            pending_views: self.pending_views(),
        });
        cx.notify();
        // A table that left the tree takes its view job with it; the
        // updates waiting on that job apply now.
        self.drain_queued_updates(cx);
    }

    /// Re-renders every cached container that holds one of `ids`, or is one.
    /// Other cached containers keep their rendered subtree.
    fn notify_subtrees<'a>(&self, ids: impl IntoIterator<Item = &'a str>, cx: &mut Context<Self>) {
        let mut due = HashSet::new();
        for id in ids {
            let mut current = Some(id);
            while let Some(candidate) = current {
                if self.subtrees.contains_key(candidate) {
                    due.insert(candidate.to_owned());
                    break;
                }
                current = self.index.parent(candidate);
            }
        }
        for id in due {
            if let Some(retained) = self.subtrees.get(&id) {
                retained.view.update(cx, |_, cx| cx.notify());
            }
        }
    }

    /// What an operation update can break beyond its own operations: the
    /// theme, bindings and menus it carries, and the datasets its touched
    /// nodes reference. Own fields were validated when the update parsed.
    fn check_update(
        &self,
        update: &crate::protocol::Update,
        touched: &Touched,
    ) -> Result<(), String> {
        update.validate_globals(&self.index.ids)?;
        let contains = |id: &str| self.datasets.entries.contains_key(id);
        let columns = |id: &str| {
            self.datasets
                .entries
                .get(id)
                .map(|data| data.borrow().data.columns.len())
        };
        let has_ids = |id: &str| {
            self.datasets
                .entries
                .get(id)
                .is_some_and(|data| data.borrow().data.ids.is_some())
        };
        for id in &touched.set {
            let node = crate::protocol::node_by_id(&self.snapshot.root, &self.index, id)
                .ok_or_else(|| format!("Set target vanished: {id}"))?;
            datasets::validate_dataset_node(node, &contains, &columns, &has_ids)?;
            crate::protocol::validate_button_menus_shallow(node, &update.actions)?;
        }
        for id in &touched.inserted {
            let node = crate::protocol::node_by_id(&self.snapshot.root, &self.index, id)
                .ok_or_else(|| format!("Inserted subtree vanished: {id}"))?;
            let mut error = None;
            node.visit(&mut |node| {
                if error.is_none() {
                    if let Err(message) =
                        datasets::validate_dataset_node(node, &contains, &columns, &has_ids)
                    {
                        error = Some(message);
                    }
                }
            });
            if let Some(message) = error {
                return Err(message);
            }
            crate::protocol::validate_button_menus(node, &update.actions)?;
        }
        Ok(())
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

    /// Selects a view row as if clicked; emits the usual selection event.
    pub(crate) fn select_table_row(
        &mut self,
        table: &str,
        row: usize,
        cx: &mut Context<Self>,
    ) -> Result<(), String> {
        let table = self.tables.get(table).ok_or("Unknown table")?;
        if row >= table.state.read(cx).delegate().rows_count(cx) {
            return Err("Invalid row".into());
        }
        table.state.update(cx, |table, cx| {
            table.set_selected_row(row, cx);
            cx.notify();
        });
        Ok(())
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
        let Some(ViewEntry::Record(source)) = delegate.index.borrow().entries.get(row).copied()
        else {
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
        // An update to records a view job is reading waits until the job's
        // index has landed, so no index ever refers to records it did not
        // see; the acknowledgement follows the apply.
        if self.view_pending_for(&update.id, cx) {
            self.queued_updates
                .entry(update.id.clone())
                .or_default()
                .push_back(QueuedUpdate { update, parse_us });
            return;
        }
        let timer = Instant::now();
        let request = update.request;
        let id = update.id.clone();
        let revision = update.revision;
        let replace = matches!(&update.change, Change::Replace { .. });
        // What the change does to the indices the tables hold, applied to
        // them while the next index computes.
        let index_change = match &update.change {
            Change::Replace { .. } => IndexChange::Replace,
            Change::Append { more: false, .. } => IndexChange::Append,
            Change::Edit { edits } => {
                IndexChange::Edits(edits.iter().filter_map(Edit::index_patch).collect())
            }
            _ => IndexChange::None,
        };
        // A structural edit changes which records exist, so every view index
        // over the dataset is stale afterwards, spec or not.
        let structural = matches!(&update.change, Change::Edit { edits } if edits.iter().any(Edit::is_structural))
            || matches!(&update.change, Change::Append { .. });
        // A slice with more to follow is stored and acknowledged only; the
        // views recompute and the tables notify at the last slice.
        let deferred = matches!(&update.change, Change::Append { more: true, .. });
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
                            Edit::Row { .. } | Edit::Insert { .. } => (0..width).collect(),
                            Edit::Delete { .. } | Edit::Move { .. } => Vec::new(),
                        })
                        .collect(),
                )
            }
            _ => None,
        };
        if matches!(&update.change, Change::Release) {
            let mut referenced = false;
            self.snapshot.root.visit(&mut |node| {
                if let Some(dataset) = node.dataset() {
                    referenced |= dataset == id;
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
        if let Change::Replace { data } = &update.change {
            let validation = datasets::validate_views(&self.snapshot, |name| {
                if name == id {
                    Some(data.columns.len())
                } else {
                    self.datasets
                        .entries
                        .get(name)
                        .map(|d| d.borrow().data.columns.len())
                }
            })
            .and_then(|_| {
                datasets::validate_context_menus(&self.snapshot, |name| {
                    if name == id {
                        data.ids.is_some()
                    } else {
                        self.datasets
                            .entries
                            .get(name)
                            .is_some_and(|d| d.borrow().data.ids.is_some())
                    }
                })
            });
            if let Err(message) = validation {
                self.events
                    .emit(Event::DatasetRejected { request, message });
                return;
            }
        }
        match self.datasets.apply(update) {
            Ok(work) if deferred => {
                self.counters
                    .data_records_checked
                    .set(self.counters.data_records_checked.get() + work.records_checked as u64);
                self.counters
                    .data_cells_written
                    .set(self.counters.data_cells_written.get() + work.cells_written as u64);
                self.events.emit(Event::DatasetApplied {
                    request,
                    id,
                    revision,
                    parse_us,
                    apply_us: timer.elapsed().as_micros() as u64,
                    work,
                    pending_views: self.pending_views(),
                });
            }
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
                        || structural
                        || match (&self.tables[&table_id].view, &touched) {
                            (Some(view), Some(touched)) => view
                                .referenced_columns()
                                .iter()
                                .any(|column| touched.contains(column)),
                            _ => false,
                        };
                    if recompute {
                        self.recompute_table_view(&table_id, replace, &index_change, cx);
                    } else {
                        let state = self.tables[&table_id].state.clone();
                        state.update(cx, |_, cx| cx.notify());
                    }
                }
                let mut bound = Vec::new();
                self.snapshot.root.visit(&mut |node| {
                    if node.dataset() == Some(id.as_str()) {
                        bound.push(node.id().to_owned());
                    }
                });
                self.notify_subtrees(bound.iter().map(String::as_str), cx);
                let mut list_changed = false;
                for retained in self.lists.values_mut() {
                    if retained.data.borrow().id != id {
                        continue;
                    }
                    list_changed = true;
                    let recompute = replace
                        || structural
                        || match (&retained.view, &touched) {
                            (Some(view), Some(touched)) => view
                                .referenced_columns()
                                .iter()
                                .any(|column| touched.contains(column)),
                            _ => false,
                        };
                    if recompute {
                        *retained.index.borrow_mut() = ViewIndex::compute(
                            retained.view.as_ref(),
                            &retained.data.borrow().data,
                        );
                        if replace {
                            retained.scroll.scroll_to_item(0, ScrollStrategy::Top);
                        }
                    }
                }
                if list_changed {
                    cx.notify();
                }
                self.update_charts(&id, touched.as_ref());
                cx.notify();
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
                    pending_views: self.pending_views(),
                });
            }
            Err(message) => self
                .events
                .emit(Event::DatasetRejected { request, message }),
        }
    }

    /// Recomputes a table's view index after its spec or dataset changed.
    ///
    /// A small dataset computes in place. A large one computes off the
    /// frame thread over a snapshot of its records while the table shows
    /// its last index adjusted for `change`; updates to that dataset wait
    /// in the queue meanwhile, and a later recompute supersedes the job.
    /// Either way the result lands through `apply_view_result`.
    fn recompute_table_view(
        &mut self,
        id: &str,
        reset_scroll: bool,
        change: &IndexChange,
        cx: &mut Context<Self>,
    ) {
        let Some(retained) = self.tables.get(id) else {
            return;
        };
        let started = Instant::now();
        let state = retained.state.clone();
        let inputs = {
            let table = state.read(cx);
            let anchor = table.visible_range().rows().start;
            let anchor_source = table.delegate().index.borrow().entries.get(anchor).copied();
            ViewInputs {
                spec: retained.view.clone(),
                records: table.delegate().data.borrow().data.clone(),
                selected_record: retained.selected_record.clone(),
                anchor_source,
            }
        };
        if inputs.spec.is_none() || inputs.records.rows.len() < VIEW_JOB_ROWS {
            if let Some(retained) = self.tables.get_mut(id) {
                retained.pending = None;
            }
            let selected_record = inputs.selected_record.clone();
            let result = inputs.compute();
            self.apply_view_result(id, reset_scroll, selected_record, result, started, cx);
            return;
        }
        {
            let index = state.read(cx).delegate().index.clone();
            let mut index = index.borrow_mut();
            match change {
                IndexChange::None => {}
                IndexChange::Replace => *index = ViewIndex::compute(None, &inputs.records),
                IndexChange::Append => index.extend_identity(inputs.records.rows.len()),
                IndexChange::Edits(patches) => {
                    for patch in patches {
                        index.patch(*patch);
                    }
                }
            }
        }
        state.update(cx, |table, cx| {
            table.refresh(cx);
            cx.notify();
        });
        self.view_jobs += 1;
        let job = self.view_jobs;
        self.counters
            .view_jobs
            .set(self.counters.view_jobs.get() + 1);
        let selected_record = inputs.selected_record.clone();
        let compute = cx
            .background_executor()
            .spawn(async move { inputs.compute() });
        let table_id = id.to_owned();
        let task = cx.spawn(async move |this, cx| {
            let result = compute.await;
            this.update(cx, |this, cx| {
                this.finish_view_job(&table_id, job, result, cx)
            })
            .ok();
        });
        if let Some(retained) = self.tables.get_mut(id) {
            retained.pending = Some(PendingView {
                job,
                reset_scroll,
                selected_record,
                started,
                _task: task,
            });
        }
    }

    /// Lands a view job's result unless the table left the tree or a later
    /// job superseded it, then applies the updates that waited on it.
    fn finish_view_job(&mut self, id: &str, job: u64, result: ViewResult, cx: &mut Context<Self>) {
        let pending = match self.tables.get_mut(id) {
            Some(retained)
                if retained
                    .pending
                    .as_ref()
                    .is_some_and(|pending| pending.job == job) =>
            {
                retained.pending.take()
            }
            _ => None,
        };
        let Some(pending) = pending else {
            return;
        };
        self.apply_view_result(
            id,
            pending.reset_scroll,
            pending.selected_record,
            result,
            pending.started,
            cx,
        );
        self.drain_queued_updates(cx);
    }

    /// Swaps a computed index into a table in one step.
    ///
    /// Selection: in identity mode the selected record ID is re-resolved to
    /// its new view row; if it left the view the selection clears and the
    /// subscription emits the null `TableSelection`. A record selected while
    /// a job ran is resolved here rather than from the job. `reset_scroll`
    /// (Replace) keeps the historic unconditional scroll reset; otherwise
    /// the first visible record stays anchored if it remains in the view,
    /// else the scroll resets to the top. Emits `TableView` once the index
    /// is in place.
    fn apply_view_result(
        &mut self,
        id: &str,
        reset_scroll: bool,
        job_record: Option<String>,
        result: ViewResult,
        started: Instant,
        cx: &mut Context<Self>,
    ) {
        let Some(retained) = self.tables.get(id) else {
            return;
        };
        let table = retained.state.clone();
        let (index, data) = {
            let state = table.read(cx);
            (
                state.delegate().index.clone(),
                state.delegate().data.clone(),
            )
        };
        let selection = match &retained.selected_record {
            Some(record) if data.borrow().data.ids.is_some() => {
                let row = if job_record.as_ref() == Some(record) {
                    result.selection_row
                } else {
                    let data = data.borrow();
                    data.data
                        .ids
                        .as_ref()
                        .and_then(|ids| ids.iter().position(|id| id == record))
                        .and_then(|source| result.index.row_of(ViewEntry::Record(source)))
                };
                row.map_or(ViewSelection::Gone, ViewSelection::Keep)
            }
            _ if reset_scroll => ViewSelection::Clear,
            _ => ViewSelection::Clamp,
        };
        let view_len = result.index.entries.len();
        let groups = result.index.groups.len();
        let anchor_view = result.anchor_view;
        *index.borrow_mut() = result.index;
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
                    // Nothing selected clears nothing: a new table or a
                    // replacement without a selection emits no null event.
                    if table.selected_row().is_some() {
                        table.clear_selection(cx);
                    }
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
        let (dataset, dataset_revision) = {
            let data = data.borrow();
            (data.id.clone(), data.revision)
        };
        self.events.emit(Event::TableView {
            revision: self.snapshot.revision,
            id: id.to_owned(),
            dataset,
            dataset_revision,
            view_rows: view_len,
            groups,
            compute_us: started.elapsed().as_micros() as u64,
        });
    }

    /// Whether a view job is reading this dataset's records.
    fn view_pending_for(&self, dataset: &str, cx: &App) -> bool {
        self.tables.values().any(|retained| {
            retained.pending.is_some()
                && retained.state.read(cx).delegate().data.borrow().id == dataset
        })
    }

    /// Tables whose view job is in flight, for the acknowledgements.
    fn pending_views(&self) -> Vec<String> {
        let mut pending: Vec<String> = self
            .tables
            .iter()
            .filter(|(_, retained)| retained.pending.is_some())
            .map(|(id, _)| id.clone())
            .collect();
        pending.sort();
        pending
    }

    /// Applies the updates that waited for a view job, in arrival order per
    /// dataset, until one of them starts another job.
    fn drain_queued_updates(&mut self, cx: &mut Context<Self>) {
        let datasets: Vec<String> = self.queued_updates.keys().cloned().collect();
        for dataset in datasets {
            while !self.view_pending_for(&dataset, cx) {
                let next = self
                    .queued_updates
                    .get_mut(&dataset)
                    .and_then(|queue| queue.pop_front());
                let Some(next) = next else {
                    self.queued_updates.remove(&dataset);
                    break;
                };
                self.update_dataset(next.update, next.parse_us, cx);
            }
        }
    }

    fn reconcile(&mut self, window: &mut Window, cx: &mut Context<Self>) -> Result<(), String> {
        self.reconcile_theme(cx)?;
        self.reconcile_menus(cx)?;
        self.reconcile_dialog(window, cx);
        self.reconcile_controls(window, cx);
        self.reconcile_choices(window, cx);
        self.reconcile_charts()?;
        let mut input_ids = HashSet::new();
        let mut table_ids = HashSet::new();
        let mut list_ids = HashSet::new();
        let mut scroll_ids = HashSet::new();
        let mut pane_ids = HashSet::new();
        let mut tree_ids = HashSet::new();
        let owner = cx.entity().downgrade();
        let mut changed_views: Vec<(String, bool)> = Vec::new();
        let mut failure = None;
        self.snapshot.root.visit(&mut |node| match node {
            Node::Tree {
                id,
                items,
                selected,
                ..
            } => {
                tree_ids.insert(id.clone());
                if let Some(retained) = self.trees.get_mut(id) {
                    if retained.items != *items {
                        retained
                            .state
                            .update(cx, |state, cx| state.set_items(build_tree_items(items), cx));
                        retained.items = items.clone();
                    }
                    if retained.selected != *selected {
                        let target = selected.as_ref().and_then(|item| {
                            retained
                                .state
                                .read(cx)
                                .index_of(&SharedString::from(item.clone()))
                        });
                        retained
                            .state
                            .update(cx, |state, cx| state.set_selected_index(target, cx));
                        retained.selected = selected.clone();
                    }
                } else {
                    let state = cx.new(|cx| {
                        gpui_kit::component::tree::TreeState::new(cx).items(build_tree_items(items))
                    });
                    if let Some(item) = selected {
                        let target = state.read(cx).index_of(&SharedString::from(item.clone()));
                        state.update(cx, |state, cx| state.set_selected_index(target, cx));
                    }
                    let event_id = id.clone();
                    let subscription = cx.subscribe(
                        &state,
                        move |this, _, event: &gpui_kit::component::tree::TreeEvent, _| {
                            let (item, expanded) = match event {
                                gpui_kit::component::tree::TreeEvent::Expanded(item) => {
                                    (item, true)
                                }
                                gpui_kit::component::tree::TreeEvent::Collapsed(item) => {
                                    (item, false)
                                }
                            };
                            this.events.emit(Event::TreeExpand {
                                revision: this.snapshot.revision,
                                id: event_id.clone(),
                                item: item.to_string(),
                                expanded,
                            });
                        },
                    );
                    self.trees.insert(
                        id.clone(),
                        RetainedTree {
                            state,
                            items: items.clone(),
                            selected: selected.clone(),
                            _subscription: subscription,
                        },
                    );
                }
            }
            Node::Sheet { .. } => {
                self.sheets_dirty = true;
            }
            Node::Scroll { id, .. } => {
                scroll_ids.insert(id.clone());
                self.scrolls
                    .entry(id.clone())
                    .or_insert_with(ScrollHandle::new);
            }
            Node::Panes {
                id, axis, panes, ..
            } => {
                pane_ids.insert(id.clone());
                match self.panes.get_mut(id) {
                    Some(retained) if retained.axis == *axis => {
                        if retained.published != *panes {
                            // A publication that changes a pane's size resizes
                            // it as a drag would; unchanged panes keep their
                            // dragged sizes.
                            for (index, (spec, before)) in
                                panes.iter().zip(retained.published.iter()).enumerate()
                            {
                                if let Some(size) =
                                    spec.size.filter(|size| Some(*size) != before.size)
                                {
                                    retained.state.update(cx, |state, cx| {
                                        state.resize_panel(index, px(size), window, cx)
                                    });
                                }
                            }
                            retained.published = panes.clone();
                        }
                    }
                    _ => {
                        let state = cx.new(|_| gpui_kit::base::ResizableState::default());
                        // Kit emits `Resized` at the end of a drag and after a
                        // programmatic resize alike; either reaches the
                        // application as `panes_resize` with every size.
                        let event_id = id.clone();
                        let subscription = cx.subscribe(
                            &state,
                            move |this, state, _: &gpui_kit::base::ResizablePanelEvent, cx| {
                                let sizes = state
                                    .read(cx)
                                    .sizes()
                                    .iter()
                                    .map(|size| f32::from(*size))
                                    .collect();
                                this.events.emit(Event::PanesResize {
                                    revision: this.snapshot.revision,
                                    id: event_id.clone(),
                                    sizes,
                                });
                            },
                        );
                        self.panes.insert(
                            id.clone(),
                            RetainedPanes {
                                state,
                                axis: *axis,
                                published: panes.clone(),
                                _subscription: subscription,
                            },
                        );
                    }
                }
            }
            Node::Input {
                id,
                placeholder,
                controlled,
                ..
            } => {
                input_ids.insert(id.clone());
                if let Some(input) = self.inputs.get_mut(id) {
                    if input.version.controlled != *controlled {
                        self.next_input_generation += 1;
                        input.version = inputs::capture(
                            &input.state,
                            self.next_input_generation,
                            *controlled,
                            window,
                            cx,
                        );
                    }
                    if input.placeholder != *placeholder {
                        input.state.update(cx, |state, cx| {
                            state.set_placeholder(placeholder.clone(), window, cx)
                        });
                        input.placeholder = placeholder.clone();
                    }
                } else {
                    let state =
                        cx.new(|cx| InputState::new(window, cx).placeholder(placeholder.clone()));
                    self.next_input_generation += 1;
                    let version = inputs::capture(
                        &state,
                        self.next_input_generation,
                        *controlled,
                        window,
                        cx,
                    );
                    let event_id = id.clone();
                    let subscription =
                        cx.subscribe_in(&state, window, move |this, input, event, _, cx| {
                            if matches!(event, InputEvent::Change)
                                && this
                                    .inputs
                                    .get(&event_id)
                                    .is_some_and(|input| !input.version.controlled)
                            {
                                this.events.emit(Event::Input {
                                    revision: this.snapshot.revision,
                                    id: event_id.clone(),
                                    value: input.read(cx).value().to_string(),
                                    input_state: None,
                                });
                            }
                        });
                    let event_id = id.clone();
                    let observer = cx.observe_in(&state, window, move |this, _, window, cx| {
                        if this
                            .inputs
                            .get(&event_id)
                            .is_some_and(|input| input.version.controlled)
                        {
                            this.refresh_input(&event_id, true, window, cx);
                        }
                    });
                    self.inputs.insert(
                        id.clone(),
                        RetainedInput {
                            state,
                            placeholder: placeholder.clone(),
                            _subscription: subscription,
                            _observer: observer,
                            version,
                        },
                    );
                }
            }
            Node::Table {
                id,
                dataset,
                view,
                context_menu,
                ..
            } => {
                let Some(data) = self.datasets.entries.get(dataset).cloned() else {
                    failure = Some(format!("Missing retained dataset: {dataset}"));
                    return;
                };
                table_ids.insert(id.clone());
                if let Some(retained) = self.tables.get_mut(id) {
                    if retained.state.read(cx).delegate().has_context_menu
                        != !context_menu.is_empty()
                    {
                        retained.state.update(cx, |table, cx| {
                            table.delegate_mut().has_context_menu = !context_menu.is_empty();
                            cx.notify();
                        });
                    }
                    let swapped = !Rc::ptr_eq(&retained.state.read(cx).delegate().data, &data);
                    if swapped {
                        // New records: dataset order until the view lands,
                        // selection and scroll reset now.
                        let index = retained.state.read(cx).delegate().index.clone();
                        *index.borrow_mut() = ViewIndex::compute(None, &data.borrow().data);
                        retained.pending = None;
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
                        if view.is_some() {
                            changed_views.push((id.clone(), true));
                        }
                    } else if retained.view != *view {
                        retained.view = view.clone();
                        changed_views.push((id.clone(), false));
                    }
                } else {
                    let index =
                        Rc::new(RefCell::new(ViewIndex::compute(None, &data.borrow().data)));
                    let table = cx.new(|cx| {
                        TableState::new(
                            Rows {
                                owner: owner.clone(),
                                has_context_menu: !context_menu.is_empty(),
                                table_id: id.clone(),
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
                                let entry = delegate.index.borrow().entries[*row];
                                let ViewEntry::Record(source) = entry else {
                                    // Group headers are summaries, not records: undo the
                                    // selection, and report nothing when none was selected.
                                    if let Some(retained) = this.tables.get_mut(&event_id) {
                                        if retained.selection_notified.is_none() {
                                            retained.selection_notified = Some((None, None));
                                        }
                                    }
                                    table.update(cx, |table, cx| table.clear_selection(cx));
                                    return;
                                };
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
                            pending: None,
                        },
                    );
                    if view.is_some() {
                        changed_views.push((id.clone(), true));
                    }
                }
            }
            Node::List {
                id, dataset, view, ..
            } => {
                let Some(data) = self.datasets.entries.get(dataset).cloned() else {
                    failure = Some(format!("Missing retained dataset: {dataset}"));
                    return;
                };
                if data.borrow().data.ids.is_none() {
                    failure = Some(format!("List {id} requires a dataset with record IDs"));
                    return;
                }
                list_ids.insert(id.clone());
                match self.lists.get_mut(id) {
                    Some(retained)
                        if Rc::ptr_eq(&retained.data, &data) && retained.view == *view => {}
                    Some(retained) => {
                        let swapped = !Rc::ptr_eq(&retained.data, &data);
                        retained.data = data.clone();
                        retained.view = view.clone();
                        *retained.index.borrow_mut() =
                            ViewIndex::compute(view.as_ref(), &data.borrow().data);
                        if swapped {
                            retained.scroll.scroll_to_item(0, ScrollStrategy::Top);
                        }
                    }
                    None => {
                        let index = ViewIndex::compute(view.as_ref(), &data.borrow().data);
                        self.lists.insert(
                            id.clone(),
                            RetainedList {
                                data,
                                index: Rc::new(RefCell::new(index)),
                                view: view.clone(),
                                scroll: UniformListScrollHandle::new(),
                            },
                        );
                    }
                }
            }
            _ => {}
        });
        if let Some(message) = failure {
            return Err(message);
        }
        let mut subtree_ids = HashSet::new();
        let subtree_owner = cx.entity().downgrade();
        self.snapshot.root.visit(&mut |node| {
            let Some(style) = node.style() else {
                return;
            };
            if !style.cached {
                return;
            }
            let Some(StyleSize::Px(height)) = style.height else {
                return;
            };
            subtree_ids.insert(node.id().to_owned());
            match self.subtrees.get_mut(node.id()) {
                Some(retained) => retained.height = height,
                None => {
                    let view = cx.new(|_| SubtreeView {
                        owner: subtree_owner.clone(),
                        id: node.id().to_owned(),
                        renders: Cell::new(0),
                    });
                    self.subtrees
                        .insert(node.id().to_owned(), RetainedSubtree { view, height });
                }
            }
        });
        self.subtrees.retain(|id, _| subtree_ids.contains(id));
        let mut image_ids = HashSet::new();
        self.snapshot.root.visit(&mut |node| {
            if let Node::Image { id, .. } = node {
                image_ids.insert(id.clone());
            }
        });
        self.images
            .borrow_mut()
            .retain(|id, _| image_ids.contains(id));
        self.inputs.retain(|id, _| input_ids.contains(id));
        self.lists.retain(|id, _| list_ids.contains(id));
        self.scrolls.retain(|id, _| scroll_ids.contains(id));
        self.panes.retain(|id, _| pane_ids.contains(id));
        self.trees.retain(|id, _| tree_ids.contains(id));
        if self.active_sheet.is_some() {
            self.sheets_dirty = true;
        }
        if self.sheets_dirty && self.root_ready {
            self.sheets_dirty = false;
            self.reconcile_sheets(window, cx);
        }
        self.tables.retain(|id, _| table_ids.contains(id));
        self.table_subscriptions
            .retain(|id, _| table_ids.contains(id));
        for (id, reset_scroll) in changed_views {
            self.recompute_table_view(&id, reset_scroll, &IndexChange::None, cx);
        }
        self.reconcile_row_menu(window, cx);
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
                    && (context != "global" || self.menu_action_enabled(&binding.name))
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
        for (id, slider) in &self.sliders {
            if slider.focus == focused {
                return self.context_chain(id);
            }
        }
        for (id, tabs) in &self.choices {
            if tabs.focus.values().any(|handle| *handle == focused) {
                return self.context_chain(id);
            }
        }
        for (id, select) in &self.selects {
            if select.state.read(cx).focus_handle(cx) == focused {
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
            if let Some(children) = node.children() {
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

    fn materialize(
        &self,
        node: &Node,
        colors: &ThemeColor,
        cx: &App,
    ) -> Result<AnyElement, String> {
        self.materialize_node(node, colors, cx, false)
    }

    /// `bypass_cache` renders a cached container itself; the placeholder
    /// path hands it to its entity instead.
    /// The decoded image for an inline-bytes node, decoded once per content.
    fn inline_image(&self, id: &str, bytes: &str, format: ImageEncoding) -> Arc<gpui::Image> {
        use std::hash::{Hash, Hasher};
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        bytes.hash(&mut hasher);
        format.hash(&mut hasher);
        let hash = hasher.finish();
        let mut images = self.images.borrow_mut();
        if let Some(retained) = images.get(id)
            && retained.hash == hash
        {
            return retained.image.clone();
        }
        let decoded = crate::protocol::decode_base64(bytes).unwrap_or_default();
        let format = match format {
            ImageEncoding::Png => gpui::ImageFormat::Png,
            ImageEncoding::Jpeg => gpui::ImageFormat::Jpeg,
            ImageEncoding::Webp => gpui::ImageFormat::Webp,
            ImageEncoding::Gif => gpui::ImageFormat::Gif,
            ImageEncoding::Svg => gpui::ImageFormat::Svg,
            ImageEncoding::Bmp => gpui::ImageFormat::Bmp,
            ImageEncoding::Tiff => gpui::ImageFormat::Tiff,
            ImageEncoding::Ico => gpui::ImageFormat::Ico,
        };
        let image = Arc::new(gpui::Image::from_bytes(format, decoded));
        images.insert(
            id.to_owned(),
            RetainedImage {
                hash,
                image: image.clone(),
            },
        );
        image
    }

    fn materialize_node(
        &self,
        node: &Node,
        colors: &ThemeColor,
        cx: &App,
        bypass_cache: bool,
    ) -> Result<AnyElement, String> {
        if !bypass_cache && node.style().is_some_and(|style| style.cached) {
            if let Some(retained) = self.subtrees.get(node.id()) {
                let mut size = div().w_full().h(px(retained.height));
                return Ok(div()
                    .id(SharedString::from(node.id().to_owned()))
                    .w_full()
                    .h(px(retained.height))
                    .child(retained.view.clone().cached(size.style().clone()))
                    .into_any_element());
            }
        }
        let id = SharedString::from(node.id().to_owned());
        let materialized = match node {
            Node::Column { children, .. } => apply_node_style(
                annotate(div().id(id), node)
                    .test_support()
                    .v_flex()
                    .gap_3()
                    .w_full()
                    .children(
                        children
                            .iter()
                            .map(|child| self.materialize(child, colors, cx))
                            .collect::<Result<Vec<_>, _>>()?,
                    ),
                node,
                colors,
            )
            .into_any_element(),
            Node::Row { children, .. } => apply_node_style(
                annotate(div().id(id), node)
                    .test_support()
                    .h_flex()
                    .flex_wrap()
                    .gap_3()
                    .w_full()
                    .children(
                        children
                            .iter()
                            .map(|child| self.materialize(child, colors, cx))
                            .collect::<Result<Vec<_>, _>>()?,
                    ),
                node,
                colors,
            )
            .into_any_element(),
            Node::Stack { children, .. } => apply_node_style(
                annotate(div().id(id), node)
                    .test_support()
                    .relative()
                    .children(
                        children
                            .iter()
                            .map(|child| {
                                let mut layer = div().absolute();
                                layer = match child.style().and_then(|style| style.inset) {
                                    Some(inset) => {
                                        if let Some(top) = inset.top {
                                            layer = layer.top(px(top));
                                        }
                                        if let Some(right) = inset.right {
                                            layer = layer.right(px(right));
                                        }
                                        if let Some(bottom) = inset.bottom {
                                            layer = layer.bottom(px(bottom));
                                        }
                                        if let Some(left) = inset.left {
                                            layer = layer.left(px(left));
                                        }
                                        layer
                                    }
                                    None => layer.inset_0(),
                                };
                                self.materialize(child, colors, cx)
                                    .map(|element| layer.child(element))
                            })
                            .collect::<Result<Vec<_>, _>>()?,
                    ),
                node,
                colors,
            )
            .into_any_element(),
            Node::Panes {
                id: panes_id,
                axis,
                panes,
                children,
                ..
            } => {
                let retained = self
                    .panes
                    .get(panes_id)
                    .ok_or_else(|| format!("Missing retained panes: {panes_id}"))?;
                let group_id = SharedString::from(panes_id.clone());
                let mut group = match axis {
                    crate::protocol::PanesAxis::Horizontal => gpui_kit::base::h_resizable(group_id),
                    crate::protocol::PanesAxis::Vertical => gpui_kit::base::v_resizable(group_id),
                }
                .with_state(&retained.state);
                for (index, child) in children.iter().enumerate() {
                    let spec = panes.get(index).copied().unwrap_or_default();
                    let mut panel = gpui_kit::base::resizable_panel()
                        .child(self.materialize(child, colors, cx)?);
                    if let Some(size) = spec.size {
                        panel = panel.size(px(size));
                    }
                    if spec.min.is_some() || spec.max.is_some() {
                        panel = panel.size_range(
                            px(spec.min.unwrap_or(0.))..spec.max.map_or(Pixels::MAX, px),
                        );
                    }
                    group = group.child(panel);
                }
                apply_node_style(
                    annotate(div().id(id), node).test_support().child(group),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Tree { id: tree_id, .. } => {
                let retained = self
                    .trees
                    .get(tree_id)
                    .ok_or_else(|| format!("Missing retained tree: {tree_id}"))?;
                let events = self.events.clone();
                let revision = self.snapshot.revision;
                let event_id = tree_id.clone();
                let element = gpui_kit::component::tree::tree(
                    &retained.state,
                    move |ix, entry, _selected, _window, _cx| {
                        let item = entry.item();
                        let chevron = entry.is_folder().then(|| {
                            let name = if entry.is_expanded() {
                                "icons/chevron-down.svg"
                            } else {
                                "icons/chevron-right.svg"
                            };
                            gpui_kit::component::Icon::new(LucideIcon(name.into()))
                                .with_size(gpui_kit::component::Size::Size(px(14.)))
                        });
                        let events = events.clone();
                        let event_id = event_id.clone();
                        let item_id = item.id.to_string();
                        gpui_kit::component::list::ListItem::new(ix)
                            .w_full()
                            .pl(px(16.) * entry.depth() + px(12.))
                            .child(
                                div()
                                    .id(item.id.clone())
                                    .test_support()
                                    .h_flex()
                                    .gap_2()
                                    .children(chevron)
                                    .child(item.label.clone()),
                            )
                            .on_click(move |_, _, _| {
                                events.emit(Event::TreeSelect {
                                    revision,
                                    id: event_id.clone(),
                                    item: item_id.clone(),
                                })
                            })
                    },
                );
                apply_node_style(
                    annotate(div().id(id), node).test_support().child(element),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Popover {
                id: popover_id,
                label,
                open,
                children,
                ..
            } => {
                let events = self.events.clone();
                let revision = self.snapshot.revision;
                let event_id = popover_id.clone();
                let content = div().v_flex().gap_2().children(
                    children
                        .iter()
                        .map(|child| self.materialize(child, colors, cx))
                        .collect::<Result<Vec<_>, _>>()?,
                );
                let mut popover = gpui_kit::component::popover::Popover::new(SharedString::from(
                    popover_id.clone(),
                ))
                .trigger(
                    Button::new(SharedString::from(format!("{popover_id}-trigger")))
                        .label(label.clone()),
                )
                .on_open_change(move |open, _, _| {
                    events.emit(Event::PopoverChange {
                        revision,
                        id: event_id.clone(),
                        open: *open,
                    })
                })
                .child(content);
                if let Some(open) = open {
                    popover = popover.open(*open);
                }
                apply_node_style(
                    annotate(div().id(id), node).test_support().child(popover),
                    node,
                    colors,
                )
                .into_any_element()
            }
            // The sheet's content lives in the window's sheet; the node itself
            // holds only its place in the tree.
            Node::Sheet { .. } => annotate(div().id(id), node)
                .test_support()
                .into_any_element(),
            Node::RichText {
                id: text_id,
                markdown,
                selectable,
                ..
            } => {
                let view = gpui_kit::base::TextView::markdown(
                    SharedString::from(format!("{text_id}-markdown")),
                    markdown.clone(),
                )
                .selectable(*selectable);
                apply_node_style(
                    annotate(div().id(id), node).test_support().child(view),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Scroll {
                id: scroll_id,
                axis,
                children,
                ..
            } => {
                let handle = self
                    .scrolls
                    .get(scroll_id)
                    .ok_or_else(|| format!("Missing retained scroll: {scroll_id}"))?;
                let content = match axis {
                    ScrollAxis::Horizontal => div().h_flex(),
                    ScrollAxis::Vertical | ScrollAxis::Both => div().v_flex(),
                }
                .gap_3()
                .children(
                    children
                        .iter()
                        .map(|child| self.materialize(child, colors, cx))
                        .collect::<Result<Vec<_>, _>>()?,
                );
                let mut container = annotate(div().id(id), node)
                    .test_support()
                    .track_scroll(handle)
                    .child(content);
                container = match axis {
                    ScrollAxis::Vertical => {
                        container.overflow_y_scroll().vertical_scrollbar(handle)
                    }
                    ScrollAxis::Horizontal => {
                        container.overflow_x_scroll().horizontal_scrollbar(handle)
                    }
                    ScrollAxis::Both => container
                        .overflow_scroll()
                        .vertical_scrollbar(handle)
                        .horizontal_scrollbar(handle),
                };
                apply_node_style(container, node, colors).into_any_element()
            }
            Node::Switch {
                label,
                checked,
                disabled,
                ..
            } => {
                let events = self.events.clone();
                let event_id = node.id().to_owned();
                let revision = self.snapshot.revision;
                let shown = self
                    .checkbox_shown
                    .borrow()
                    .get(node.id())
                    .copied()
                    .unwrap_or(*checked);
                let displayed = self.checkbox_shown.clone();
                apply_node_style(
                    Switch::new(id)
                        .accessibility_label(accessible_name(node))
                        .label(label.clone())
                        .checked(shown)
                        .disabled(*disabled)
                        .on_change(move |checked, window, _| {
                            displayed.borrow_mut().insert(event_id.clone(), *checked);
                            window.refresh();
                            events.emit(Event::SwitchChange {
                                revision,
                                id: event_id.clone(),
                                checked: *checked,
                            });
                        }),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Progress { value, .. } => {
                let bar = Progress::new(id.clone()).accessibility_label(accessible_name(node));
                let bar = match value {
                    Some(value) => bar.value(*value),
                    None => bar.loading(true),
                };
                apply_node_style(
                    annotate(div().id(id), node)
                        .test_support()
                        .w_full()
                        .child(bar),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Separator {
                vertical, label, ..
            } => {
                let rule = if *vertical {
                    Separator::vertical()
                } else {
                    Separator::horizontal()
                };
                let rule = if label.is_empty() {
                    rule
                } else {
                    rule.label(label.clone())
                };
                apply_node_style(
                    annotate(div().id(id), node).test_support().child(rule),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Icon {
                name, size, color, ..
            } => {
                let mut icon =
                    gpui_kit::component::Icon::new(LucideIcon(format!("icons/{name}.svg").into()));
                if let Some(size) = size {
                    icon = icon.with_size(gpui_kit::component::Size::Size(px(*size)));
                }
                if let Some(color) = color {
                    icon = icon.text_color(resolve_color(*color, colors));
                }
                apply_node_style(
                    annotate(div().id(id), node).test_support().child(icon),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Image {
                path,
                bytes,
                format,
                width,
                height,
                fit,
                ..
            } => {
                let source: gpui::ImageSource = match (path, bytes, format) {
                    (Some(path), _, _) => std::path::PathBuf::from(path).into(),
                    (None, Some(bytes), Some(format)) => {
                        self.inline_image(node.id(), bytes, *format).into()
                    }
                    _ => return Err(format!("Image {} has no source", node.id())),
                };
                let mut image = gpui::img(source).object_fit(match fit {
                    ImageFit::Contain => gpui::ObjectFit::Contain,
                    ImageFit::Cover => gpui::ObjectFit::Cover,
                    ImageFit::Fill => gpui::ObjectFit::Fill,
                    ImageFit::ScaleDown => gpui::ObjectFit::ScaleDown,
                    ImageFit::None => gpui::ObjectFit::None,
                });
                if let Some(width) = width {
                    image = image.w(px(*width));
                }
                if let Some(height) = height {
                    image = image.h(px(*height));
                }
                apply_node_style(
                    annotate(div().id(id), node).test_support().child(image),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Canvas { commands, .. } => {
                let draws: Vec<ResolvedDraw> = commands
                    .iter()
                    .map(|command| resolve_draw(command, colors))
                    .collect();
                let surface = canvas(
                    |_, _, _| (),
                    move |bounds, _, window, _| paint_draws(&draws, bounds, window),
                )
                .size_full();
                apply_node_style(
                    annotate(div().id(id), node).test_support().child(surface),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::List {
                column, selected, ..
            } => {
                let retained = self
                    .lists
                    .get(node.id())
                    .ok_or_else(|| format!("Missing retained list: {}", node.id()))?;
                let data = retained.data.clone();
                let index = retained.index.clone();
                let count = index.borrow().entries.len();
                let shown = self
                    .choice_shown
                    .borrow()
                    .get(node.id())
                    .cloned()
                    .or_else(|| selected.clone());
                let events = self.events.clone();
                let displayed = self.choice_shown.clone();
                let event_id = node.id().to_owned();
                let revision = self.snapshot.revision;
                let column = *column;
                let items = uniform_list(
                    SharedString::from(format!("{}-items", node.id())),
                    count,
                    move |range, _, cx| {
                        let index = index.borrow();
                        let data = data.borrow();
                        range
                            .map(|row| {
                                let ViewEntry::Record(source) = index.entries[row] else {
                                    return div().id(("list-gap", row)).into_any_element();
                                };
                                let text = data.data.rows[source]
                                    .get(column)
                                    .cloned()
                                    .unwrap_or_default();
                                let record = data
                                    .data
                                    .ids
                                    .as_ref()
                                    .map_or_else(String::new, |ids| ids[source].clone());
                                let is_selected = shown.as_deref() == Some(record.as_str());
                                let events = events.clone();
                                let displayed = displayed.clone();
                                let event_id = event_id.clone();
                                let dataset = data.id.clone();
                                let dataset_revision = data.revision;
                                let item_id = format!("{event_id}:{record}");
                                div()
                                    .id(SharedString::from(item_id.clone()))
                                    .accessibility_id(item_id)
                                    .role(Role::ListItem)
                                    .aria_label(text.clone())
                                    .test_support()
                                    .px_3()
                                    .py_1()
                                    .when(is_selected, |item| item.bg(cx.theme().accent))
                                    .child(text)
                                    .on_click(move |_, window, _| {
                                        displayed
                                            .borrow_mut()
                                            .insert(event_id.clone(), record.clone());
                                        window.refresh();
                                        events.emit(Event::ListSelect {
                                            revision,
                                            id: event_id.clone(),
                                            dataset: dataset.clone(),
                                            dataset_revision,
                                            row,
                                            record: record.clone(),
                                        });
                                    })
                                    .into_any_element()
                            })
                            .collect()
                    },
                )
                .track_scroll(&retained.scroll)
                .h_full()
                .w_full();
                apply_node_style(
                    annotate(div().id(id), node)
                        .test_support()
                        .w_full()
                        .h(px(320.))
                        .child(items),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::MenuButton { label, items, .. } => {
                let events = self.events.clone();
                let revision = self.snapshot.revision;
                let entries = items.clone();
                let button = DropdownButton::new(SharedString::from(format!("{}-menu", node.id())))
                    .button(
                        Button::new(SharedString::from(format!("{}-trigger", node.id())))
                            .accessibility_id(node.id().to_owned())
                            .accessibility_label(accessible_name(node))
                            .label(label.clone()),
                    )
                    .dropdown_menu(move |mut menu, _, _| {
                        for entry in &entries {
                            menu = match entry {
                                MenuEntry::Separator => menu.separator(),
                                MenuEntry::Action {
                                    label,
                                    action,
                                    checked,
                                    disabled,
                                    ..
                                } => {
                                    let events = events.clone();
                                    let action = action.clone();
                                    menu.item(
                                        PopupMenuItem::new(label.clone())
                                            .disabled(*disabled)
                                            .checked(*checked)
                                            .on_click(move |_, _, _| {
                                                events.emit(Event::Action {
                                                    revision,
                                                    name: action.clone(),
                                                    context: "global".into(),
                                                });
                                            }),
                                    )
                                }
                            };
                        }
                        menu
                    });
                apply_node_style(
                    annotate(div().id(id), node).test_support().child(button),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Text { text, .. } => apply_node_style(
                annotate(div().id(id), node)
                    .test_support()
                    .child(text.clone()),
                node,
                colors,
            )
            .into_any_element(),
            Node::Button { label, tooltip, .. } => {
                let events = self.events.clone();
                let event_id = node.id().to_owned();
                let revision = self.snapshot.revision;
                apply_node_style(
                    Button::new(id)
                        .accessibility_id(node.id().to_owned())
                        .accessibility_label(accessible_name(node))
                        .primary()
                        .label(label.clone())
                        .when_some(tooltip.clone(), |button, help| {
                            semantics::description(button.tooltip(help.clone()), help)
                        })
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
            Node::Checkbox {
                label,
                checked,
                disabled,
                ..
            } => {
                let events = self.events.clone();
                let event_id = node.id().to_owned();
                let revision = self.snapshot.revision;
                let shown = self
                    .checkbox_shown
                    .borrow()
                    .get(node.id())
                    .copied()
                    .unwrap_or(*checked);
                let displayed = self.checkbox_shown.clone();
                apply_node_style(
                    Checkbox::new(id)
                        .accessibility_id(node.id().to_owned())
                        .accessibility_label(accessible_name(node))
                        .label(label.clone())
                        .checked(shown)
                        .disabled(*disabled)
                        .a11y_synthetic_children({
                            let disabled = *disabled;
                            move |tree| {
                                if disabled {
                                    tree.parent_node().set_disabled();
                                }
                            }
                        })
                        .on_change(move |checked, window, _| {
                            displayed.borrow_mut().insert(event_id.clone(), *checked);
                            window.refresh();
                            events.emit(Event::CheckboxChange {
                                revision,
                                id: event_id.clone(),
                                checked: *checked,
                            });
                        }),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Chart { .. } => self.chart_element(node, colors)?,
            Node::Tabs { .. } | Node::RadioGroup { .. } => {
                self.choices_element(node, colors, cx)?
            }
            Node::Slider { .. } => self.slider_element(node, colors, cx)?,
            Node::Select { .. } => self.select_element(node, colors)?,
            Node::DatePicker { .. } => self.date_picker_element(node, colors)?,
            Node::ConfirmDialog { .. } => self.dialog_element(node, colors)?,
            Node::Input { id, .. } => {
                let state = &self
                    .inputs
                    .get(id)
                    .ok_or_else(|| format!("Missing retained input: {id}"))?
                    .state;
                apply_node_style(
                    control_root::AccessibleInput(
                        Input::new(state)
                            .id(SharedString::from(id.clone()))
                            .accessibility_id(id.clone())
                            .aria_label(accessible_name(node)),
                        state.read(cx).focus_handle(cx),
                    ),
                    node,
                    colors,
                )
                .into_any_element()
            }
            Node::Table { id, .. } => {
                let table = &self
                    .tables
                    .get(id)
                    .ok_or_else(|| format!("Missing retained table: {id}"))?
                    .state;
                let delegate = table.read(cx).delegate();
                apply_node_style(
                    annotate(div().id(SharedString::from(id.clone())), node)
                        .aria_row_count(delegate.index.borrow().entries.len())
                        .aria_column_count(delegate.data.borrow().data.columns.len())
                        .w_full()
                        .h(px(320.))
                        .child(DataTable::new(table).stripe(true).bordered(true)),
                    node,
                    colors,
                )
                .into_any_element()
            }
        };
        let materialized = animate(node, materialized);
        #[cfg(all(test, feature = "snapshot-experiment"))]
        if let Some(bounds) = &self.experiment_bounds {
            return Ok(experiment::BoundsProbe {
                child: materialized,
                id: node.id().to_owned(),
                bounds: bounds.clone(),
            }
            .into_any_element());
        }
        Ok(materialized)
    }
}

/// Wraps an element in a native timeline when its style asks for one. GPUI
/// drives the frames; the application is never involved.
fn animate(node: &Node, element: AnyElement) -> AnyElement {
    let Some(motion) = node.style().and_then(|style| style.animation.as_ref()) else {
        return element;
    };
    let mut animation = Animation::new(Duration::from_millis(u64::from(motion.duration_ms)));
    if motion.repeat {
        animation = animation.repeat();
    }
    animation = match motion.easing {
        Easing::Linear => animation.with_easing(linear),
        Easing::EaseInOut => animation.with_easing(ease_in_out),
        Easing::EaseOutQuint => animation.with_easing(ease_out_quint()),
        Easing::Bounce => animation.with_easing(bounce(ease_in_out)),
    };
    let opacity = motion.opacity;
    let offset = motion.offset;
    div()
        .id(SharedString::from(format!("{}:animation", node.id())))
        .child(element)
        .with_animation(
            SharedString::from(format!("{}:{}", node.id(), motion.key)),
            animation,
            move |wrapper, delta| {
                let mut wrapper = wrapper;
                if let Some([from, to]) = opacity {
                    wrapper = wrapper.opacity(from + (to - from) * delta);
                }
                if let Some([[x0, y0], [x1, y1]]) = offset {
                    wrapper = wrapper
                        .relative()
                        .left(px(x0 + (x1 - x0) * delta))
                        .top(px(y0 + (y1 - y0) * delta));
                }
                wrapper
            },
        )
        .into_any_element()
}

/// A canvas command with its colors resolved against the theme, relative to
/// the canvas origin.
enum ResolvedDraw {
    Rect {
        origin: Point<Pixels>,
        size: Size<Pixels>,
        fill: Option<Hsla>,
        stroke: Option<Hsla>,
        stroke_width: Pixels,
        radius: Pixels,
    },
    Path {
        points: Vec<Point<Pixels>>,
        close: bool,
        fill: Option<Hsla>,
        stroke: Option<Hsla>,
        width: Pixels,
    },
}

fn resolve_draw(command: &Draw, colors: &ThemeColor) -> ResolvedDraw {
    let color = |value: &Option<StyleColor>| value.map(|color| resolve_color(color, colors));
    match command {
        Draw::Rect {
            x,
            y,
            width,
            height,
            fill,
            stroke,
            stroke_width,
            radius,
        } => ResolvedDraw::Rect {
            origin: point(px(*x), px(*y)),
            size: size(px(*width), px(*height)),
            fill: color(fill),
            stroke: color(stroke),
            stroke_width: px(*stroke_width),
            radius: px(*radius),
        },
        Draw::Circle {
            cx,
            cy,
            radius,
            fill,
            stroke,
            stroke_width,
        } => ResolvedDraw::Rect {
            origin: point(px(cx - radius), px(cy - radius)),
            size: size(px(radius * 2.), px(radius * 2.)),
            fill: color(fill),
            stroke: color(stroke),
            stroke_width: px(*stroke_width),
            radius: px(*radius),
        },
        Draw::Line {
            x1,
            y1,
            x2,
            y2,
            color: stroke,
            width,
        } => ResolvedDraw::Path {
            points: vec![point(px(*x1), px(*y1)), point(px(*x2), px(*y2))],
            close: false,
            fill: None,
            stroke: Some(resolve_color(*stroke, colors)),
            width: px(*width),
        },
        Draw::Polyline {
            points,
            stroke,
            width,
            fill,
            close,
        } => ResolvedDraw::Path {
            points: points.iter().map(|[x, y]| point(px(*x), px(*y))).collect(),
            close: *close,
            fill: color(fill),
            stroke: color(stroke),
            width: px(*width),
        },
    }
}

fn paint_draws(draws: &[ResolvedDraw], bounds: Bounds<Pixels>, window: &mut Window) {
    let origin = bounds.origin;
    for draw in draws {
        match draw {
            ResolvedDraw::Rect {
                origin: offset,
                size,
                fill,
                stroke,
                stroke_width,
                radius,
            } => {
                let rect = Bounds {
                    origin: origin + *offset,
                    size: *size,
                };
                if let Some(fill) = fill {
                    window.paint_quad(quad(
                        rect,
                        *radius,
                        *fill,
                        Edges::default(),
                        Hsla::transparent_black(),
                        BorderStyle::Solid,
                    ));
                }
                if let Some(stroke) = stroke {
                    window.paint_quad(quad(
                        rect,
                        *radius,
                        Hsla::transparent_black(),
                        Edges::all(*stroke_width),
                        *stroke,
                        BorderStyle::Solid,
                    ));
                }
            }
            ResolvedDraw::Path {
                points,
                close,
                fill,
                stroke,
                width,
            } => {
                let trace = |mut builder: PathBuilder| {
                    let mut points = points.iter().map(|p| origin + *p);
                    if let Some(first) = points.next() {
                        builder.move_to(first);
                    }
                    for next in points {
                        builder.line_to(next);
                    }
                    if *close {
                        builder.close();
                    }
                    builder.build().ok()
                };
                if let Some(fill) = fill {
                    if let Some(path) = trace(PathBuilder::fill()) {
                        window.paint_path(path, *fill);
                    }
                }
                if let Some(stroke) = stroke {
                    if let Some(path) = trace(PathBuilder::stroke(*width)) {
                        window.paint_path(path, *stroke);
                    }
                }
            }
        }
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
    if let Some(size) = style.min_width {
        element = element.min_w(style_length(size));
    }
    if let Some(size) = style.max_width {
        element = element.max_w(style_length(size));
    }
    if let Some(size) = style.min_height {
        element = element.min_h(style_length(size));
    }
    if let Some(size) = style.max_height {
        element = element.max_h(style_length(size));
    }
    if let Some(flex) = style.flex {
        // Like Flutter's Expanded: share the remaining space from a zero
        // basis instead of adding to the content size.
        element = if flex > 0. {
            element.flex_grow(flex).flex_shrink(1.).flex_basis(px(0.))
        } else {
            element.flex_none()
        };
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

mod charts;
mod choices;
mod control_root;
mod controls;
mod menus;
#[cfg(test)]
mod menus_tests;
mod row_menus;
mod semantics;
#[cfg(test)]
mod semantics_tests;
mod slider;
#[cfg(test)]
mod tabs_tests;
mod theming;
use semantics::{accessible_name, annotate};
#[cfg(test)]
mod controls_tests;
mod dialogs;
#[cfg(feature = "snapshot-experiment")]
pub(crate) mod experiment;
#[cfg(test)]
mod input_tests;
mod inputs;
#[cfg(test)]
mod tests;

impl DartView {
    /// Opens or closes the window's sheet to match the description: the last
    /// open sheet node wins, and a closed or removed node closes it. Runs
    /// after a frame, once Kit's window root exists and is not mid-render.
    fn reconcile_sheets(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let mut wanted = None;
        self.snapshot.root.visit(&mut |node| {
            if let Node::Sheet {
                id,
                open: true,
                placement,
                title,
                size,
                ..
            } = node
            {
                wanted = Some((id.clone(), *placement, title.clone(), *size));
            }
        });
        let Some((id, placement, title, size)) = wanted else {
            if self.active_sheet.take().is_some() && window.has_active_sheet(cx) {
                window.close_sheet(cx);
            }
            return;
        };
        if self.active_sheet.as_deref() == Some(id.as_str()) && window.has_active_sheet(cx) {
            return;
        }
        let owner = cx.entity().downgrade();
        let events = self.events.clone();
        let title = SharedString::from(title);
        let placement = match placement {
            crate::protocol::SheetPlacement::Right => gpui_kit::component::Placement::Right,
            crate::protocol::SheetPlacement::Left => gpui_kit::component::Placement::Left,
            crate::protocol::SheetPlacement::Top => gpui_kit::component::Placement::Top,
            crate::protocol::SheetPlacement::Bottom => gpui_kit::component::Placement::Bottom,
        };
        let sheet_id = id.clone();
        // The builder runs on every frame the sheet is shown, so it
        // materializes the node's current children each time.
        window.open_sheet_at(placement, cx, move |sheet, _, cx| {
            let content: Vec<AnyElement> = owner
                .upgrade()
                .map(|view| {
                    let view = view.read(cx);
                    let colors = cx.theme().colors.clone();
                    match view.snapshot.root.find(&sheet_id) {
                        Some(Node::Sheet { children, .. }) => children
                            .iter()
                            .filter_map(|child| view.materialize(child, &colors, cx).ok())
                            .collect(),
                        _ => Vec::new(),
                    }
                })
                .unwrap_or_default();
            let events = events.clone();
            let owner = owner.clone();
            let event_id = sheet_id.clone();
            let mut sheet = sheet
                .title(title.clone())
                .child(div().v_flex().gap_3().size_full().children(content))
                .on_close(move |_, _, cx| {
                    let revision = owner
                        .upgrade()
                        .map_or(0, |view| view.read(cx).snapshot.revision);
                    events.emit(Event::SheetClose {
                        revision,
                        id: event_id.clone(),
                    });
                });
            if let Some(size) = size {
                sheet = sheet.size(px(size));
            }
            sheet
        });
        self.active_sheet = Some(id);
    }
}

impl Render for DartView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.reconcile_row_menu(window, cx);
        self.root_ready = true;
        if self.sheets_dirty {
            self.sheets_dirty = false;
            cx.defer_in(window, |this, window, cx| this.reconcile_sheets(window, cx));
        }
        self.counters
            .materializations
            .set(self.counters.materializations.get() + 1);
        self.frame_gaps.frame(Instant::now());
        #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
        for (id, retained) in &self.tables {
            let y = f32::from(retained.state.read(cx).vertical_scroll_handle.offset().y);
            crate::input_trace::record_table_scroll(id, self.counters.materializations.get(), y);
        }
        let colors = cx.theme().colors.clone();
        let content = match self.materialize(&self.snapshot.root, &colors, cx) {
            Ok(content) => content,
            Err(message) => {
                self.fail(message, cx);
                div().child("Unable to render this view").into_any_element()
            }
        };
        #[cfg(feature = "snapshot-experiment")]
        if self.embedded {
            return content;
        }
        let root = div()
            .id("gpuidart")
            .on_action(cx.listener(Self::invoke_menu))
            .role(Role::Group)
            .a11y_synthetic_children({
                let modal = self.active_dialog.clone();
                move |tree| {
                    if modal.borrow().is_some() {
                        tree.parent_node().set_hidden();
                    }
                }
            })
            .size_full()
            .overflow_y_scroll()
            .track_scroll(&self.scroll)
            .bg(cx.theme().background)
            .text_color(cx.theme().foreground)
            .children(
                self.menu_bar
                    .as_ref()
                    .map(|bar| div().h_8().w_full().child(bar.clone())),
            )
            .child(div().w_full().p_5().child(content))
            .vertical_scrollbar(&self.scroll)
            .children(self.row_menu_element());
        #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
        let root = crate::paint_trace::PaintMarker {
            child: crate::input_trace::observe(root).into_any_element(),
            revision: self.snapshot.revision,
            painted: self.painted_revision.clone(),
        };
        match &self.trace {
            Some(trace) if self.failure.is_none() => crate::paint_trace::ContentPaint {
                child: root.into_any_element(),
                trace: trace.clone(),
                revision: self.snapshot.revision,
            }
            .into_any_element(),
            _ => root.into_any_element(),
        }
    }
}

type Opened = (
    gpui::WindowHandle<gpui_kit::component::Root>,
    Entity<DartView>,
);

/// The windows the application holds, by the ID Dart addresses (0 is the
/// main window) and by GPUI's window ID for the close observer.
#[derive(Default)]
struct Windows {
    by_id: HashMap<u32, Opened>,
    ids: HashMap<gpui::WindowId, u32>,
}

impl Windows {
    fn insert(
        &mut self,
        window: u32,
        handle: gpui::WindowHandle<gpui_kit::component::Root>,
        view: Entity<DartView>,
    ) {
        self.ids
            .insert(gpui::AnyWindowHandle::from(handle).window_id(), window);
        self.by_id.insert(window, (handle, view));
    }

    fn get(&self, window: u32) -> Option<Opened> {
        self.by_id.get(&window).cloned()
    }

    fn handles(&self) -> Vec<gpui::WindowHandle<gpui_kit::component::Root>> {
        self.by_id.values().map(|(handle, _)| *handle).collect()
    }

    fn remove_by_window_id(&mut self, id: gpui::WindowId) -> Option<u32> {
        let window = self.ids.remove(&id)?;
        self.by_id.remove(&window);
        Some(window)
    }
}

/// Whether a window is presenting at a frame cadence right now, judged by
/// its own last three presents: the longer of the two gaps between them is
/// the cadence (a repaint between two ticks leaves one short gap), it
/// counts as one up to 50 ms, and the window is still in it while the
/// newest present is younger than the cadence and a half. The interval is
/// the window's own, so a 59 Hz panel and a 144 Hz one need no constant.
#[cfg(windows)]
fn painting_every_tick(presents: [Option<Instant>; 3]) -> bool {
    const SLOWEST_CADENCE: Duration = Duration::from_millis(50);
    let [Some(newest), Some(previous), older] = presents else {
        return false;
    };
    let mut cadence = newest.duration_since(previous);
    if let Some(older) = older {
        cadence = cadence.max(previous.duration_since(older));
    }
    cadence <= SLOWEST_CADENCE && newest.elapsed() < cadence + cadence / 2
}

/// Asks Windows to repaint the window now that an update from the
/// application has landed. GPUI draws a dirty window at the next vsync tick,
/// which is up to a frame away from a change that is already applied; the
/// repaint request draws it at once, at most once per 4 ms. By default it
/// fires unless the window is presenting at a frame cadence, the
/// sign of a burst or a stream that paints at every tick and would render
/// the extra frame for nothing; a lone frame just before the update, the
/// hover or the press of the click itself, does not hold it back, so a
/// click on a quiet window gets the early frame (17 to 20 ms sooner on
/// the display). `GPUIDART_DRAW_ON_UPDATE=0` turns it off and `always`
/// fires it after every update, which on a burst of thirty clicks a second
/// rendered one present per click the display never took.
#[cfg(windows)]
fn draw_now(
    cx: &mut gpui::AsyncApp,
    handle: gpui::WindowHandle<gpui_kit::component::Root>,
    last: &Cell<Option<Instant>>,
) {
    use raw_window_handle::{HasWindowHandle, RawWindowHandle};
    #[derive(Clone, Copy, PartialEq)]
    enum Policy {
        Never,
        Idle,
        Always,
    }
    static POLICY: std::sync::OnceLock<Policy> = std::sync::OnceLock::new();
    let policy =
        *POLICY.get_or_init(
            || match std::env::var("GPUIDART_DRAW_ON_UPDATE").as_deref() {
                Ok("0") => Policy::Never,
                Ok("always") => Policy::Always,
                _ => Policy::Idle,
            },
        );
    if policy == Policy::Never {
        return;
    }
    if last
        .get()
        .is_some_and(|at| at.elapsed() < Duration::from_millis(4))
    {
        return;
    }
    #[link(name = "user32")]
    unsafe extern "system" {
        fn RedrawWindow(
            hwnd: *mut std::ffi::c_void,
            rect: *const std::ffi::c_void,
            region: *mut std::ffi::c_void,
            flags: u32,
        ) -> i32;
    }
    const RDW_INVALIDATE: u32 = 0x0001;
    let requested = cx.update_window(handle.into(), |_, window, _| {
        if let Ok(raw) = window.window_handle() {
            if let RawWindowHandle::Win32(win32) = raw.as_raw() {
                if policy == Policy::Idle
                    && painting_every_tick(gpui_windows::last_presents(win32.hwnd.get()))
                {
                    return false;
                }
                unsafe {
                    RedrawWindow(
                        win32.hwnd.get() as *mut std::ffi::c_void,
                        std::ptr::null(),
                        std::ptr::null_mut(),
                        RDW_INVALIDATE,
                    );
                }
                return true;
            }
        }
        false
    });
    if let Ok(true) = requested {
        last.set(Some(Instant::now()));
    }
}

#[cfg(not(windows))]
fn draw_now(
    _: &mut gpui::AsyncApp,
    _: gpui::WindowHandle<gpui_kit::component::Root>,
    _: &Cell<Option<Instant>>,
) {
}

fn dismiss_sheet(cx: &mut gpui::AsyncApp, handle: gpui::WindowHandle<gpui_kit::component::Root>) {
    let _ = cx.update_window(handle.into(), |_, window, cx| {
        if window.has_active_sheet(cx) {
            window.close_sheet(cx);
        }
    });
}

/// Opens a secondary window with its own view and reports the outcome to
/// Dart. Every event from that view carries the window ID.
fn open_secondary(
    cx: &mut gpui::AsyncApp,
    windows: &Rc<RefCell<Windows>>,
    events: &Events,
    open: crate::datasets::WindowOpen,
) {
    let request = open.request;
    let id = open.id;
    let reject = |message: String| {
        events.emit(Event::WindowRejected {
            request,
            window: id,
            message,
        });
    };
    if windows.borrow().by_id.contains_key(&id) {
        reject("Window ID is already open".into());
        return;
    }
    let tagged = events.for_window(id);
    let initial = open.initial;
    let opened = cx.update(|cx| {
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
        let handle = cx.open_window(options, |window, cx| {
            let view = cx.new(|cx| DartView::new(initial, tagged, window, cx));
            content = Some(view.clone());
            cx.new(|cx| gpui_kit::component::Root::new(view, window, cx))
        });
        handle.map(|handle| (handle, content))
    });
    let (handle, view) = match opened {
        Ok((handle, Some(view))) => (handle, view),
        Ok((_, None)) => {
            reject("Window opened without view content".into());
            return;
        }
        Err(error) => {
            reject(error.to_string());
            return;
        }
    };
    if let Some(message) = cx.update(|cx| view.read(cx).failure.clone()) {
        let _ = handle.update(cx, |_, window, _| window.remove_window());
        reject(message);
        return;
    }
    windows.borrow_mut().insert(id, handle, view);
    events.emit(Event::WindowOpened {
        request,
        window: id,
    });
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
    let application = gpui_kit::application().with_assets(gpui_kit::assets::Assets);
    trace.point("native.app_built", initial_key, None, None);
    application.run(move |cx| {
        trace.point("native.app_callback", initial_key, None, None);
        if let Some(before_quit) = before_quit {
            cx.on_app_quit(move |_| {
                before_quit();
                std::future::ready(())
            })
            .detach();
        }
        gpui_kit::init(cx);
        trace.point("native.kit_init", initial_key, None, None);
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
        let window_started = trace.start();
        let opened = cx.open_window(options, |window, cx| {
            let view = cx.new(|cx| {
                let mut view = DartView::new(initial, events.clone(), window, cx);
                if trace.enabled() {
                    view.trace = Some(trace.clone());
                }
                view
            });
            content = Some(view.clone());
            cx.new(|cx| gpui_kit::component::Root::new(view, window, cx))
        });
        trace.complete(
            "native.window_create",
            initial_key,
            window_started,
            None,
            Some(if opened.is_ok() { 0 } else { -1 }),
        );
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
        let windows = Rc::new(RefCell::new(Windows::default()));
        windows.borrow_mut().insert(0, handle, view.clone());
        let closing = windows.clone();
        let closed_events = events.clone();
        cx.on_window_closed(move |cx, window_id| {
            match closing.borrow_mut().remove_by_window_id(window_id) {
                // The main window owns the application.
                Some(0) => cx.quit(),
                Some(window) => {
                    closed_events.emit(Event::WindowClosed { window });
                    if cx.windows().is_empty() {
                        cx.quit();
                    }
                }
                None => {
                    if cx.windows().is_empty() {
                        cx.quit();
                    }
                }
            }
        })
        .detach();
        events.emit(Event::Ready);
        events.emit(Event::Applied {
            revision: view.read(cx).snapshot.revision,
            native_apply_us: 0,
            pending_views: view.read(cx).pending_views(),
        });
        let last_draw = Cell::new(None::<Instant>);
        cx.spawn(async move |cx| {
            while let Ok(command) = receiver.recv().await {
                trace.point("native.dequeue", command.trace_key(), None, None);
                let _dispatch = trace.dispatch(command.trace_key());
                // A failing update on the main window means the
                // application is quitting; on a secondary window it means
                // that window closed first and its command is dropped.
                match command {
                    Command::Publish(window, snapshot) => {
                        let Some((handle, view)) = windows.borrow().get(window) else {
                            events.for_window(window).emit(Event::Rejected {
                                revision: snapshot.revision,
                                message: "Unknown window".into(),
                            });
                            continue;
                        };
                        if cx
                            .update_window(handle.into(), |_, w, cx| {
                                view.update(cx, |view, cx| view.publish(snapshot, w, cx))
                            })
                            .is_err()
                            && window == 0
                        {
                            break;
                        }
                        draw_now(cx, handle, &last_draw);
                    }
                    Command::Update(window, update) => {
                        let Some((handle, view)) = windows.borrow().get(window) else {
                            events.for_window(window).emit(Event::Rejected {
                                revision: update.revision,
                                message: "Unknown window".into(),
                            });
                            continue;
                        };
                        if cx
                            .update_window(handle.into(), |_, w, cx| {
                                view.update(cx, |view, cx| view.apply_update(update, w, cx))
                            })
                            .is_err()
                            && window == 0
                        {
                            break;
                        }
                        draw_now(cx, handle, &last_draw);
                    }
                    Command::Close | Command::CloseWindow(0) => {
                        // An open sheet holds Kit's focus trap; dismiss it
                        // before the application quits so teardown does not
                        // wait on it.
                        let handles = windows.borrow().handles();
                        for handle in handles {
                            dismiss_sheet(cx, handle);
                        }
                        break;
                    }
                    Command::CloseWindow(window) => {
                        // Removing the window runs the close observer,
                        // which borrows the registry: hold no borrow here.
                        let target = windows.borrow().get(window);
                        if let Some((handle, _)) = target {
                            dismiss_sheet(cx, handle);
                            let _ = handle.update(cx, |_, w, _| w.remove_window());
                        }
                    }
                    Command::OpenWindow(open) => open_secondary(cx, &windows, &events, open),
                    Command::Dataset(window, update, parse_us) => {
                        let Some((handle, view)) = windows.borrow().get(window) else {
                            events.for_window(window).emit(Event::DatasetRejected {
                                request: update.request,
                                message: "Unknown window".into(),
                            });
                            continue;
                        };
                        if handle
                            .update(cx, |_, _, cx| {
                                view.update(cx, |view, cx| {
                                    view.update_dataset(update, parse_us, cx)
                                })
                            })
                            .is_err()
                            && window == 0
                        {
                            break;
                        }
                        draw_now(cx, handle, &last_draw);
                    }
                    Command::Diagnostic(window, request) => {
                        let Some((handle, view)) = windows.borrow().get(window) else {
                            events.for_window(window).emit(Event::Diagnostic {
                                request: request.id(),
                                data: json!({"error": "Unknown window"}),
                            });
                            continue;
                        };
                        let tagged = if window == 0 {
                            events.clone()
                        } else {
                            events.for_window(window)
                        };
                        // Keyboard dispatch may update the Root (Tab/modal
                        // handlers), so do not borrow it through handle.update.
                        if cx
                            .update_window(handle.into(), |_, w, cx| {
                                crate::diagnostics::handle(request, &view, &tagged, w, cx)
                            })
                            .is_err()
                            && window == 0
                        {
                            break;
                        }
                    }
                    Command::Input(window, request) => {
                        let Some((handle, view)) = windows.borrow().get(window) else {
                            events.for_window(window).emit(Event::InputResult {
                                request: request.request,
                                id: request.id.clone(),
                                status: crate::input_control::Status::Missing,
                                state: None,
                            });
                            continue;
                        };
                        if handle
                            .update(cx, |_, w, cx| {
                                view.update(cx, |view, cx| view.input_command(request, w, cx))
                            })
                            .is_err()
                            && window == 0
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

#[cfg(test)]
#[path = "ui/tooltip_tests.rs"]
mod tooltip_tests;

#[cfg(test)]
#[path = "ui/radio_tests.rs"]
mod radio_tests;

#[cfg(test)]
#[path = "ui/charts_tests.rs"]
mod charts_tests;

#[cfg(all(test, windows))]
mod repaint_tests {
    use super::painting_every_tick;
    use std::time::{Duration, Instant};

    fn ago(ms: u64) -> Option<Instant> {
        Some(Instant::now() - Duration::from_millis(ms))
    }

    #[test]
    fn a_window_presenting_at_every_tick_is_busy() {
        assert!(painting_every_tick([ago(5), ago(22), ago(39)]));
        assert!(painting_every_tick([ago(3), ago(10), ago(17)]));
    }

    #[test]
    fn a_lone_frame_before_the_update_does_not_make_it_busy() {
        assert!(!painting_every_tick([ago(2), ago(202), ago(212)]));
        assert!(!painting_every_tick([ago(2), None, None]));
        assert!(!painting_every_tick([None, None, None]));
    }

    #[test]
    fn a_cadence_that_stopped_is_idle_again() {
        assert!(!painting_every_tick([ago(300), ago(317), ago(334)]));
    }

    #[test]
    fn a_repaint_between_two_ticks_keeps_the_tick_cadence() {
        assert!(painting_every_tick([ago(12), ago(21), ago(38)]));
    }
}
