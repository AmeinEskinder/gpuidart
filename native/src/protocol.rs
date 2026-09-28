use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize};

mod apply;
pub use apply::{Touched, TreeIndex, apply_in_place, get as node_by_id, rollback};
mod charts;
pub use charts::{ChartKind, ChartSpec};
mod menus;
pub use menus::{MenuEntry, MenuSpec};
pub(crate) use menus::{validate_button_menus, validate_button_menus_shallow};
mod navigation;
pub use navigation::ChoiceOption;
mod semantics;
mod theme;
pub use semantics::{SemanticRole, Semantics};
pub use theme::{ThemeMode, ThemeSpec};

pub const MAX_MESSAGE_BYTES: usize = 16 * 1024 * 1024;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Snapshot {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub menus: Vec<MenuSpec>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub theme: Option<ThemeSpec>,
    pub revision: u64,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub actions: Vec<ActionBinding>,
    pub root: Node,
}

/// A key binding declared by the application: `name` fires as an `action`
/// event when `keys` is pressed while focus is inside `context`.
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ActionBinding {
    pub name: String,
    pub keys: String,
    /// `"global"` or the ID of a node present in the same snapshot.
    pub context: String,
}

/// Modifiers plus one named key; the closed grammar of `ActionBinding::keys`.
/// `meta` is the platform meta key: cmd on macOS, the windows key on Windows,
/// super on Linux. `ctrl` always means the literal control key.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct KeystrokeSpec {
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    pub meta: bool,
    pub key: String,
}

impl KeystrokeSpec {
    pub fn parse(source: &str) -> Result<Self, String> {
        let mut spec = Self {
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
            key: String::new(),
        };
        let parts: Vec<&str> = source.split('+').collect();
        let Some((key, modifiers)) = parts.split_last() else {
            return Err("Empty key binding".into());
        };
        for modifier in modifiers {
            let flag = match *modifier {
                "ctrl" => &mut spec.ctrl,
                "alt" => &mut spec.alt,
                "shift" => &mut spec.shift,
                "meta" => &mut spec.meta,
                _ => return Err(format!("Unknown modifier in key binding: {source}")),
            };
            if *flag {
                return Err(format!("Duplicate modifier in key binding: {source}"));
            }
            *flag = true;
        }
        let named = matches!(
            *key,
            "enter"
                | "escape"
                | "space"
                | "tab"
                | "up"
                | "down"
                | "left"
                | "right"
                | "home"
                | "end"
                | "pageup"
                | "pagedown"
                | "delete"
                | "backspace"
        ) || key
            .strip_prefix('f')
            .and_then(|n| n.parse::<u8>().ok())
            .is_some_and(|n| (1..=12).contains(&n));
        let printable = key.len() == 1 && {
            let byte = key.as_bytes()[0];
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b','
        };
        if !named && !printable {
            return Err(format!("Unknown key in key binding: {source}"));
        }
        if printable && !spec.ctrl && !spec.alt && !spec.shift && !spec.meta {
            return Err(format!(
                "Bare printable keys are owned by native text input; add a modifier: {source}"
            ));
        }
        spec.key = key.to_string();
        Ok(spec)
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Node {
    Column {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        #[serde(default)]
        children: Vec<Node>,
    },
    Row {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        #[serde(default)]
        children: Vec<Node>,
    },
    Text {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        text: String,
    },
    Chart {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        chart: ChartSpec,
    },
    Button {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        label: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        tooltip: Option<String>,
    },
    /// An on/off toggle. Like a checkbox, the shown value follows the user
    /// until the next publication.
    Switch {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        label: String,
        checked: bool,
        #[serde(default)]
        disabled: bool,
    },
    /// A determinate bar for `value` 0 to 100, or an indeterminate one when
    /// `value` is absent.
    Progress {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        value: Option<f32>,
    },
    Separator {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        #[serde(default)]
        vertical: bool,
        #[serde(default, skip_serializing_if = "String::is_empty")]
        label: String,
    },
    Checkbox {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        label: String,
        checked: bool,
        #[serde(default)]
        disabled: bool,
    },
    Slider {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        min: f32,
        max: f32,
        step: f32,
        number: f32,
        #[serde(default)]
        disabled: bool,
    },
    Tabs {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        options: Vec<ChoiceOption>,
        selected: String,
        #[serde(default)]
        disabled: bool,
    },
    RadioGroup {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        options: Vec<ChoiceOption>,
        selected: String,
        #[serde(default)]
        disabled: bool,
    },
    Select {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        options: Vec<SelectOption>,
        selected: Option<String>,
        #[serde(default)]
        placeholder: String,
        #[serde(default)]
        disabled: bool,
    },
    ConfirmDialog {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        label: String,
        title: String,
        message: String,
        confirm_label: String,
        cancel_label: String,
        #[serde(default)]
        disabled: bool,
    },
    Input {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        placeholder: String,
        #[serde(default, skip_serializing_if = "is_false")]
        controlled: bool,
    },
    Table {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        dataset: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        view: Option<TableView>,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        context_menu: Vec<MenuEntry>,
    },
    /// Children overlap in order. A child sits at the top left with its own
    /// size unless its style has `inset`; `width` and `height` of `full`
    /// cover the stack. The stack takes its size from its own style or its
    /// parent.
    Stack {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        #[serde(default)]
        children: Vec<Node>,
    },
    /// A bounded container whose content scrolls; the offset is retained by
    /// ID across publications.
    Scroll {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        #[serde(default)]
        axis: ScrollAxis,
        #[serde(default)]
        children: Vec<Node>,
    },
    /// A retained draw list painted natively inside the node's bounds.
    /// Coordinates are logical px from the node's top left.
    Canvas {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        commands: Vec<Draw>,
    },
    /// A virtualized list over one dataset column, in the order of an
    /// optional view; `list_select` carries the chosen record ID. The
    /// dataset must carry record IDs.
    List {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        dataset: String,
        column: usize,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        view: Option<TableView>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        selected: Option<String>,
    },
    /// A button that opens a native popup menu; `menu_select` carries the
    /// chosen item ID.
    MenuButton {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        semantics: Option<Semantics>,
        label: String,
        items: Vec<MenuEntry>,
    },
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum Draw {
    Rect {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        fill: Option<Color>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        stroke: Option<Color>,
        #[serde(default = "one")]
        stroke_width: f32,
        #[serde(default)]
        radius: f32,
    },
    Circle {
        cx: f32,
        cy: f32,
        radius: f32,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        fill: Option<Color>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        stroke: Option<Color>,
        #[serde(default = "one")]
        stroke_width: f32,
    },
    Line {
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
        color: Color,
        #[serde(default = "one")]
        width: f32,
    },
    Polyline {
        points: Vec<[f32; 2]>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        stroke: Option<Color>,
        #[serde(default = "one")]
        width: f32,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        fill: Option<Color>,
        #[serde(default)]
        close: bool,
    },
}

fn one() -> f32 {
    1.
}

impl Draw {
    fn validate(&self) -> Result<(), String> {
        fn coordinate(value: f32) -> Result<(), String> {
            if !value.is_finite() || value.abs() > 8192. {
                return Err("Canvas coordinates must be within 8192 px".into());
            }
            Ok(())
        }
        fn extent(value: f32, max: f32, what: &str) -> Result<(), String> {
            if !value.is_finite() || value < 0. || value > max {
                return Err(format!("Canvas {what} must be between 0 and {max}"));
            }
            Ok(())
        }
        match self {
            Self::Rect {
                x,
                y,
                width,
                height,
                stroke_width,
                radius,
                ..
            } => {
                coordinate(*x)?;
                coordinate(*y)?;
                extent(*width, 8192., "size")?;
                extent(*height, 8192., "size")?;
                extent(*stroke_width, 512., "stroke width")?;
                extent(*radius, 8192., "radius")
            }
            Self::Circle {
                cx,
                cy,
                radius,
                stroke_width,
                ..
            } => {
                coordinate(*cx)?;
                coordinate(*cy)?;
                extent(*radius, 8192., "radius")?;
                extent(*stroke_width, 512., "stroke width")
            }
            Self::Line {
                x1,
                y1,
                x2,
                y2,
                width,
                ..
            } => {
                for value in [x1, y1, x2, y2] {
                    coordinate(*value)?;
                }
                extent(*width, 512., "stroke width")
            }
            Self::Polyline {
                points,
                width,
                stroke,
                fill,
                ..
            } => {
                if points.len() < 2 || points.len() > 4096 {
                    return Err("Canvas polylines need 2 to 4096 points".into());
                }
                if stroke.is_none() && fill.is_none() {
                    return Err("Canvas polylines need a stroke or a fill".into());
                }
                for [x, y] in points {
                    coordinate(*x)?;
                    coordinate(*y)?;
                }
                extent(*width, 512., "stroke width")
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ScrollAxis {
    #[default]
    Vertical,
    Horizontal,
    Both,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SelectOption {
    pub id: String,
    pub label: String,
}

fn is_false(value: &bool) -> bool {
    !value
}

/// Presentation-only view of a table's dataset: filter, then sort. The
/// dataset itself is never reordered.
#[derive(Clone, Debug, Default, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TableView {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sort: Vec<SortKey>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub filter: Vec<FilterTerm>,
    /// Groups the filtered, sorted records and inserts a header row per
    /// group carrying the key, the count and native aggregates.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub group: Option<Grouping>,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Grouping {
    pub column: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub aggregates: Vec<Aggregate>,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Aggregate {
    pub column: usize,
    pub op: AggregateOp,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AggregateOp {
    Count,
    Sum,
    Avg,
    Min,
    Max,
}

/// One row of a table view: a record by source index, or a group header.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ViewEntry {
    Record(usize),
    Group(usize),
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct GroupSummary {
    pub column: usize,
    pub key: String,
    pub count: usize,
    /// Aggregate texts by column, in the grouping's order.
    pub aggregates: Vec<(usize, String)>,
}

/// The rows a table shows, in order, with the summaries its headers show.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ViewIndex {
    pub entries: Vec<ViewEntry>,
    pub groups: Vec<GroupSummary>,
}

impl ViewIndex {
    /// Every record in dataset order when there is no view.
    pub fn compute(view: Option<&TableView>, data: &TableData) -> Self {
        match view {
            Some(view) => view.compute_view(data),
            None => Self {
                entries: (0..data.rows.len()).map(ViewEntry::Record).collect(),
                groups: Vec::new(),
            },
        }
    }

    pub fn row_of(&self, entry: ViewEntry) -> Option<usize> {
        self.entries
            .iter()
            .position(|candidate| *candidate == entry)
    }

    /// Source indices of the records in view order.
    #[cfg(test)]
    pub fn records(&self) -> impl Iterator<Item = usize> + '_ {
        self.entries.iter().filter_map(|entry| match entry {
            ViewEntry::Record(source) => Some(*source),
            ViewEntry::Group(_) => None,
        })
    }
}

fn aggregate_text(op: AggregateOp, column: usize, members: &[usize], data: &TableData) -> String {
    if op == AggregateOp::Count {
        return members.len().to_string();
    }
    let values: Vec<f64> = members
        .iter()
        .filter_map(|&source| data.rows[source][column].parse::<f64>().ok())
        .filter(|value| value.is_finite())
        .collect();
    if values.is_empty() {
        return String::new();
    }
    let value = match op {
        AggregateOp::Count => unreachable!(),
        AggregateOp::Sum => values.iter().sum(),
        AggregateOp::Avg => values.iter().sum::<f64>() / values.len() as f64,
        AggregateOp::Min => values.iter().cloned().fold(f64::INFINITY, f64::min),
        AggregateOp::Max => values.iter().cloned().fold(f64::NEG_INFINITY, f64::max),
    };
    if value.fract() == 0. && value.abs() < 1e15 {
        format!("{}", value as i64)
    } else {
        format!("{value}")
    }
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SortKey {
    pub column: usize,
    pub direction: SortDirection,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SortDirection {
    Asc,
    Desc,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FilterTerm {
    pub column: usize,
    pub op: FilterOp,
    pub value: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FilterOp {
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    Contains,
}

impl TableView {
    fn validate(&self) -> Result<(), String> {
        if self.sort.len() > 4 || self.filter.len() > 8 {
            return Err("Table views allow at most 4 sort keys and 8 filter terms".into());
        }
        if self
            .group
            .as_ref()
            .is_some_and(|group| group.aggregates.len() > 8)
        {
            return Err("Table views allow at most 8 aggregates".into());
        }
        if self.referenced_columns().iter().any(|column| *column >= 64) {
            return Err("Table view column must be below 64".into());
        }
        Ok(())
    }

    /// Columns whose edits can change the view.
    pub fn referenced_columns(&self) -> HashSet<usize> {
        self.sort
            .iter()
            .map(|key| key.column)
            .chain(self.filter.iter().map(|term| term.column))
            .chain(self.group.iter().flat_map(|group| {
                std::iter::once(group.column)
                    .chain(group.aggregates.iter().map(|aggregate| aggregate.column))
            }))
            .collect()
    }

    /// The rows in order: filtered and sorted records, grouped under header
    /// rows in order of first appearance when a grouping is set.
    pub fn compute_view(&self, data: &TableData) -> ViewIndex {
        let records = self.compute_index(data);
        let Some(grouping) = &self.group else {
            return ViewIndex {
                entries: records.into_iter().map(ViewEntry::Record).collect(),
                groups: Vec::new(),
            };
        };
        let mut order: HashMap<&str, usize> = HashMap::new();
        let mut members: Vec<(String, Vec<usize>)> = Vec::new();
        for source in records {
            let key = data.rows[source][grouping.column].as_str();
            let group = *order.entry(key).or_insert_with(|| {
                members.push((key.to_owned(), Vec::new()));
                members.len() - 1
            });
            members[group].1.push(source);
        }
        let mut index = ViewIndex::default();
        for (group, (key, sources)) in members.into_iter().enumerate() {
            index.entries.push(ViewEntry::Group(group));
            index
                .entries
                .extend(sources.iter().map(|&source| ViewEntry::Record(source)));
            index.groups.push(GroupSummary {
                column: grouping.column,
                key,
                count: sources.len(),
                aggregates: grouping
                    .aggregates
                    .iter()
                    .map(|aggregate| {
                        (
                            aggregate.column,
                            aggregate_text(aggregate.op, aggregate.column, &sources, data),
                        )
                    })
                    .collect(),
            });
        }
        index
    }

    /// View row -> source row, filtered then stably sorted. The dataset is
    /// never reordered.
    pub fn compute_index(&self, data: &TableData) -> Vec<usize> {
        let mut index: Vec<usize> = (0..data.rows.len())
            .filter(|&row| {
                self.filter
                    .iter()
                    .all(|term| term.op.matches(&data.rows[row][term.column], &term.value))
            })
            .collect();
        if !self.sort.is_empty() {
            index.sort_by(|&a, &b| {
                for key in &self.sort {
                    let ordering =
                        compare_cells(&data.rows[a][key.column], &data.rows[b][key.column]);
                    let ordering = match key.direction {
                        SortDirection::Asc => ordering,
                        SortDirection::Desc => ordering.reverse(),
                    };
                    if ordering != std::cmp::Ordering::Equal {
                        return ordering;
                    }
                }
                std::cmp::Ordering::Equal
            });
        }
        index
    }
}

/// Compares two cell strings: numerically when both parse as finite `f64`,
/// lexically otherwise.
pub fn compare_cells(a: &str, b: &str) -> std::cmp::Ordering {
    let numeric = match (a.parse::<f64>(), b.parse::<f64>()) {
        (Ok(a), Ok(b)) if a.is_finite() && b.is_finite() => Some((a, b)),
        _ => None,
    };
    match numeric {
        Some((a, b)) => a.partial_cmp(&b).unwrap_or(std::cmp::Ordering::Equal),
        None => a.cmp(b),
    }
}

impl FilterOp {
    pub fn matches(self, cell: &str, value: &str) -> bool {
        match self {
            Self::Contains => return cell.contains(value),
            _ => {}
        }
        match compare_cells(cell, value) {
            std::cmp::Ordering::Less => {
                matches!(self, Self::Ne | Self::Lt | Self::Le)
            }
            std::cmp::Ordering::Equal => matches!(self, Self::Eq | Self::Le | Self::Ge),
            std::cmp::Ordering::Greater => {
                matches!(self, Self::Ne | Self::Gt | Self::Ge)
            }
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Style {
    /// Logical px: top, right, bottom, left.
    pub padding: Option<[f32; 4]>,
    pub gap: Option<f32>,
    pub width: Option<Size>,
    pub height: Option<Size>,
    pub align: Option<Align>,
    pub justify: Option<Justify>,
    pub background: Option<Color>,
    pub foreground: Option<Color>,
    pub border_color: Option<Color>,
    pub border_radius: Option<f32>,
    /// Logical px; text nodes only.
    pub font_size: Option<f32>,
    pub font_weight: Option<FontWeight>,
    /// Flex grow factor inside a row or column, 0 to 64. Positive values
    /// share the remaining space; 0 keeps the content size.
    pub flex: Option<f32>,
    pub min_width: Option<Size>,
    pub max_width: Option<Size>,
    pub min_height: Option<Size>,
    pub max_height: Option<Size>,
    /// Absolute placement inside the nearest stack, logical px from each edge.
    pub inset: Option<Inset>,
    /// A native timeline that interpolates this node's opacity or offset
    /// every frame without involving the application.
    pub animation: Option<NodeAnimation>,
    /// Keep this container's rendered subtree across frames until a change
    /// touches it. Needs a fixed pixel height.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub cached: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct NodeAnimation {
    pub duration_ms: u32,
    #[serde(default)]
    pub easing: Easing,
    #[serde(default)]
    pub repeat: bool,
    /// Changing the key restarts the animation on the next publication.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub key: String,
    /// From and to, 0 to 1.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opacity: Option<[f32; 2]>,
    /// From and to offsets in logical px, `[[x0, y0], [x1, y1]]`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub offset: Option<[[f32; 2]; 2]>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Easing {
    Linear,
    #[default]
    EaseInOut,
    EaseOutQuint,
    Bounce,
}

impl NodeAnimation {
    fn validate(&self) -> Result<(), String> {
        if !(1..=60_000).contains(&self.duration_ms) {
            return Err("Animation duration must be 1 to 60000 ms".into());
        }
        if self.key.len() > 64 {
            return Err("Animation key exceeds 64 UTF-8 bytes".into());
        }
        if self.opacity.is_none() && self.offset.is_none() {
            return Err("Animation needs an opacity or an offset range".into());
        }
        if let Some(opacity) = self.opacity {
            if opacity
                .iter()
                .any(|value| !value.is_finite() || !(0. ..=1.).contains(value))
            {
                return Err("Animation opacity must be between 0 and 1".into());
            }
        }
        if let Some(offset) = self.offset {
            if offset
                .iter()
                .flatten()
                .any(|value| !value.is_finite() || value.abs() > 8192.)
            {
                return Err("Animation offsets must be within 8192 px".into());
            }
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Inset {
    pub top: Option<f32>,
    pub right: Option<f32>,
    pub bottom: Option<f32>,
    pub left: Option<f32>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Size {
    Px(f32),
    Full,
    Fit,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Align {
    Start,
    Center,
    End,
    Stretch,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Justify {
    Start,
    Center,
    End,
    SpaceBetween,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FontWeight {
    Normal,
    Medium,
    Semibold,
    Bold,
}

/// Theme roles that exist in gpui-kit's `ThemeColor` at the pinned revision.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ThemeToken {
    Background,
    Foreground,
    Primary,
    PrimaryForeground,
    Secondary,
    SecondaryForeground,
    Muted,
    MutedForeground,
    Accent,
    AccentForeground,
    Danger,
    DangerForeground,
    Border,
    Success,
    Warning,
    Info,
}

impl ThemeToken {
    fn parse(name: &str) -> Result<Self, String> {
        Ok(match name {
            "background" => Self::Background,
            "foreground" => Self::Foreground,
            "primary" => Self::Primary,
            "primary_foreground" => Self::PrimaryForeground,
            "secondary" => Self::Secondary,
            "secondary_foreground" => Self::SecondaryForeground,
            "muted" => Self::Muted,
            "muted_foreground" => Self::MutedForeground,
            "accent" => Self::Accent,
            "accent_foreground" => Self::AccentForeground,
            "danger" => Self::Danger,
            "danger_foreground" => Self::DangerForeground,
            "border" => Self::Border,
            "success" => Self::Success,
            "warning" => Self::Warning,
            "info" => Self::Info,
            _ => return Err(format!("Unknown theme token: {name}")),
        })
    }

    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::Background => "background",
            Self::Foreground => "foreground",
            Self::Primary => "primary",
            Self::PrimaryForeground => "primary_foreground",
            Self::Secondary => "secondary",
            Self::SecondaryForeground => "secondary_foreground",
            Self::Muted => "muted",
            Self::MutedForeground => "muted_foreground",
            Self::Accent => "accent",
            Self::AccentForeground => "accent_foreground",
            Self::Danger => "danger",
            Self::DangerForeground => "danger_foreground",
            Self::Border => "border",
            Self::Success => "success",
            Self::Warning => "warning",
            Self::Info => "info",
        }
    }
}

/// `"token:<name>"` or `"#RRGGBB"` / `"#RRGGBBAA"`; hex is stored as 0xRRGGBBAA.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Color {
    Token(ThemeToken),
    Hex(u32),
}

impl Color {
    fn parse(value: &str) -> Result<Self, String> {
        if let Some(name) = value.strip_prefix("token:") {
            return Ok(Self::Token(ThemeToken::parse(name)?));
        }
        if let Some(hex) = value.strip_prefix('#') {
            let channel =
                u32::from_str_radix(hex, 16).map_err(|_| format!("Malformed color: {value}"))?;
            return match hex.len() {
                6 => Ok(Self::Hex(channel << 8 | 0xFF)),
                8 => Ok(Self::Hex(channel)),
                _ => Err(format!("Malformed color: {value}")),
            };
        }
        Err(format!("Malformed color: {value}"))
    }
}

impl<'de> Deserialize<'de> for Color {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = String::deserialize(deserializer)?;
        Self::parse(&value).map_err(serde::de::Error::custom)
    }
}

impl Serialize for Color {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::Token(token) => serializer.serialize_str(&format!("token:{}", token.name())),
            Self::Hex(value) => serializer.serialize_str(&format!("#{value:08X}")),
        }
    }
}

impl Style {
    fn validate(&self, text_node: bool) -> Result<(), String> {
        fn bounded(value: f32, max: f32, field: &str) -> Result<(), String> {
            if !value.is_finite() || value < 0. || value > max {
                return Err(format!("Style {field} must be between 0 and {max}"));
            }
            Ok(())
        }
        if let Some(padding) = self.padding {
            for edge in padding {
                bounded(edge, 512., "padding")?;
            }
        }
        if let Some(gap) = self.gap {
            bounded(gap, 512., "gap")?;
        }
        if let Some(radius) = self.border_radius {
            bounded(radius, 512., "border_radius")?;
        }
        for (field, size) in [
            ("width", self.width),
            ("height", self.height),
            ("min_width", self.min_width),
            ("max_width", self.max_width),
            ("min_height", self.min_height),
            ("max_height", self.max_height),
        ] {
            if let Some(Size::Px(value)) = size {
                bounded(value, 8192., field)?;
            }
        }
        if let Some(flex) = self.flex {
            bounded(flex, 64., "flex")?;
        }
        if let Some(inset) = self.inset {
            for edge in [inset.top, inset.right, inset.bottom, inset.left]
                .into_iter()
                .flatten()
            {
                bounded(edge, 8192., "inset")?;
            }
        }
        if let Some(animation) = &self.animation {
            animation.validate()?;
        }
        if let Some(size) = self.font_size {
            if !size.is_finite() || !(8. ..=96.).contains(&size) {
                return Err("Style font_size must be between 8 and 96".into());
            }
        }
        if !text_node && (self.font_size.is_some() || self.font_weight.is_some()) {
            return Err("Style font_size and font_weight apply to text nodes only".into());
        }
        Ok(())
    }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TableData {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<String>>,
    /// Stable record IDs parallel to `rows`. Present selects identity mode:
    /// selection survives sorting, filtering and cell edits by record ID.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ids: Option<Vec<String>>,
    /// Declarative cell formatting, evaluated for visible cells only. Set at
    /// upload and Replace; immutable across Edit.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub format: Option<DatasetFormat>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct DatasetFormat {
    /// Per-column specs keyed by column index.
    pub columns: HashMap<usize, ColumnFormat>,
}

// TableData sits inside the internally tagged `Change`, whose serde buffering
// cannot coerce JSON object keys to integers; parse them explicitly instead.
impl<'de> Deserialize<'de> for DatasetFormat {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Wire {
            columns: HashMap<String, ColumnFormat>,
        }
        let wire = Wire::deserialize(deserializer)?;
        let mut columns = HashMap::new();
        for (key, spec) in wire.columns {
            let index = key.parse::<usize>().map_err(|_| {
                serde::de::Error::custom(format!("Format column must be an index: {key}"))
            })?;
            columns.insert(index, spec);
        }
        Ok(Self { columns })
    }
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ColumnFormat {
    pub number: Option<NumberFormat>,
    /// First matching rule wins.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub rules: Vec<FormatRule>,
}

/// Fixed-point rendering with 0–6 decimals, no grouping.
#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct NumberFormat {
    pub decimals: u8,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FormatRule {
    pub when: FormatCondition,
    pub color: Option<Color>,
    pub icon: Option<CellIcon>,
}

/// Same comparison set as view filters.
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FormatCondition {
    pub op: FilterOp,
    pub value: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CellIcon {
    ArrowUp,
    ArrowDown,
    Dot,
    Warning,
}

/// The formatted rendering of one cell: the text plus the first matching
/// rule's color and icon.
pub struct FormattedCell {
    pub text: String,
    pub color: Option<Color>,
    pub icon: Option<CellIcon>,
}

impl ColumnFormat {
    /// Formats one raw cell value. A non-numeric value in a `number` column
    /// renders the raw string unchanged; rules still evaluate against it.
    pub fn apply(&self, raw: &str) -> FormattedCell {
        let text = match &self.number {
            Some(number) => match raw.parse::<f64>() {
                Ok(value) if value.is_finite() => {
                    format!("{:.*}", number.decimals as usize, value)
                }
                _ => raw.to_owned(),
            },
            None => raw.to_owned(),
        };
        let rule = self
            .rules
            .iter()
            .find(|rule| rule.when.op.matches(raw, &rule.when.value));
        FormattedCell {
            text,
            color: rule.and_then(|rule| rule.color),
            icon: rule.and_then(|rule| rule.icon),
        }
    }
}

impl Node {
    pub fn dataset(&self) -> Option<&str> {
        match self {
            Self::Table { dataset, .. } | Self::List { dataset, .. } => Some(dataset),
            Self::Chart { chart, .. } => Some(&chart.dataset),
            _ => None,
        }
    }

    pub fn id(&self) -> &str {
        match self {
            Self::Column { id, .. }
            | Self::Row { id, .. }
            | Self::Text { id, .. }
            | Self::Button { id, .. }
            | Self::Checkbox { id, .. }
            | Self::Slider { id, .. }
            | Self::Tabs { id, .. }
            | Self::RadioGroup { id, .. }
            | Self::Select { id, .. }
            | Self::ConfirmDialog { id, .. }
            | Self::Input { id, .. }
            | Self::Table { id, .. }
            | Self::Stack { id, .. }
            | Self::Scroll { id, .. }
            | Self::Switch { id, .. }
            | Self::Progress { id, .. }
            | Self::Separator { id, .. }
            | Self::Canvas { id, .. }
            | Self::MenuButton { id, .. }
            | Self::List { id, .. }
            | Self::Chart { id, .. } => id,
        }
    }

    pub fn style(&self) -> Option<&Style> {
        match self {
            Self::Column { style, .. }
            | Self::Row { style, .. }
            | Self::Text { style, .. }
            | Self::Button { style, .. }
            | Self::Checkbox { style, .. }
            | Self::Slider { style, .. }
            | Self::Tabs { style, .. }
            | Self::RadioGroup { style, .. }
            | Self::Select { style, .. }
            | Self::ConfirmDialog { style, .. }
            | Self::Input { style, .. }
            | Self::Table { style, .. }
            | Self::Stack { style, .. }
            | Self::Scroll { style, .. }
            | Self::Switch { style, .. }
            | Self::Progress { style, .. }
            | Self::Separator { style, .. }
            | Self::Canvas { style, .. }
            | Self::MenuButton { style, .. }
            | Self::List { style, .. }
            | Self::Chart { style, .. } => style.as_ref(),
        }
    }

    pub fn semantics(&self) -> Option<&Semantics> {
        match self {
            Self::Column { semantics, .. }
            | Self::Row { semantics, .. }
            | Self::Text { semantics, .. }
            | Self::Button { semantics, .. }
            | Self::Checkbox { semantics, .. }
            | Self::Slider { semantics, .. }
            | Self::Tabs { semantics, .. }
            | Self::RadioGroup { semantics, .. }
            | Self::Select { semantics, .. }
            | Self::ConfirmDialog { semantics, .. }
            | Self::Input { semantics, .. }
            | Self::Table { semantics, .. }
            | Self::Stack { semantics, .. }
            | Self::Scroll { semantics, .. }
            | Self::Switch { semantics, .. }
            | Self::Progress { semantics, .. }
            | Self::Separator { semantics, .. }
            | Self::Canvas { semantics, .. }
            | Self::MenuButton { semantics, .. }
            | Self::List { semantics, .. }
            | Self::Chart { semantics, .. } => semantics.as_ref(),
        }
    }

    pub fn find(&self, id: &str) -> Option<&Self> {
        if self.id() == id {
            return Some(self);
        }
        self.children()
            .and_then(|children| children.iter().find_map(|child| child.find(id)))
    }

    /// The children of a container kind; leaf kinds have none.
    pub fn children(&self) -> Option<&Vec<Node>> {
        match self {
            Self::Column { children, .. }
            | Self::Row { children, .. }
            | Self::Stack { children, .. }
            | Self::Scroll { children, .. } => Some(children),
            _ => None,
        }
    }

    pub fn visit(&self, f: &mut impl FnMut(&Node)) {
        f(self);
        if let Some(children) = self.children() {
            for child in children {
                child.visit(f);
            }
        }
    }
}

impl Snapshot {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > MAX_MESSAGE_BYTES {
            return Err("Snapshot exceeds 16 MiB".into());
        }
        let snapshot: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        snapshot.validate()?;
        Ok(snapshot)
    }

    pub fn validate(&self) -> Result<(), String> {
        if let Some(theme) = &self.theme {
            theme.colors()?;
        }
        if self.revision == 0 {
            return Err("Revision must be positive".into());
        }
        let mut ids = HashSet::new();
        validate_tree(&self.root, 0, &mut ids)?;
        menus::validate(&self.menus, &self.actions)?;
        menus::validate_button_menus(&self.root, &self.actions)?;
        self.validate_actions(&ids)
    }
}

/// Bindings name existing contexts, parse and do not repeat.
pub fn validate_bindings(actions: &[ActionBinding], ids: &HashSet<String>) -> Result<(), String> {
    if actions.len() > 256 {
        return Err("At most 256 action bindings per snapshot".into());
    }
    let mut names = HashSet::new();
    let mut keys = HashMap::new();
    for binding in actions {
        if binding.name.is_empty() {
            return Err("Action name must be nonempty".into());
        }
        if binding.context != "global" && !ids.contains(&binding.context) {
            return Err(format!(
                "Action context is not a node in this snapshot: {}",
                binding.context
            ));
        }
        let spec = KeystrokeSpec::parse(&binding.keys)?;
        if !names.insert((&binding.name, &binding.context)) {
            return Err(format!(
                "Duplicate action binding: {} in {}",
                binding.name, binding.context
            ));
        }
        if let Some(existing) = keys.insert((spec, &binding.context), &binding.name) {
            return Err(format!(
                "Keys {} in {} are bound to both {} and {}",
                binding.keys, binding.context, existing, binding.name
            ));
        }
    }
    Ok(())
}

/// Options carry stable IDs and visible labels; `selected` must name one.
fn validate_options(
    options: &[SelectOption],
    selected: Option<&String>,
    what: &str,
) -> Result<(), String> {
    if options.is_empty() || options.len() > 256 {
        return Err(format!(
            "{what} requires 1..256 options and a placeholder of at most 1024 UTF-8 bytes"
        ));
    }
    let mut keys = HashSet::new();
    for option in options {
        if option.id.is_empty()
            || option.id.len() > 256
            || !keys.insert(&option.id)
            || option.label.is_empty()
            || option.label.len() > 1024
        {
            return Err("Invalid or duplicate select option".into());
        }
    }
    if selected.is_some_and(|id| !keys.contains(id)) {
        return Err(format!("{what} selected ID is not an option"));
    }
    Ok(())
}

fn validate_tree(node: &Node, depth: usize, ids: &mut HashSet<String>) -> Result<(), String> {
    if depth > 32 || ids.len() >= 4096 {
        return Err("Snapshot is too large or deeply nested".into());
    }
    if node.id().is_empty() || !ids.insert(node.id().to_owned()) {
        return Err(format!("Empty or duplicate node ID: {}", node.id()));
    }
    if let Some(style) = node.style() {
        style.validate(matches!(node, Node::Text { .. }))?;
    }
    if let Some(semantics) = node.semantics() {
        semantics.validate(node)?;
    }
    if node.style().is_some_and(|style| style.cached) {
        let fixed = matches!(
            node.style().and_then(|style| style.height),
            Some(Size::Px(height)) if height > 0.
        );
        if node.children().is_none() || !fixed {
            return Err(format!(
                "Cached subtree {} needs a container with a fixed pixel height",
                node.id()
            ));
        }
    }
    if let Some(children) = node.children() {
        for child in children {
            validate_tree(child, depth + 1, ids)?;
        }
    }
    match node {
        Node::Table {
            dataset,
            view,
            context_menu,
            ..
        } => {
            if !context_menu.is_empty() {
                menus::validate_entries(context_menu)?;
            }
            if dataset.is_empty() {
                return Err("Table dataset ID must be nonempty".into());
            }
            if let Some(view) = view {
                view.validate()?;
            }
        }
        Node::Chart { chart, .. } => chart.validate()?,
        Node::List {
            dataset,
            column,
            view,
            selected,
            ..
        } => {
            if dataset.is_empty() {
                return Err("List dataset ID must be nonempty".into());
            }
            if *column >= 64 {
                return Err("List column must be below 64".into());
            }
            if let Some(view) = view {
                view.validate()?;
                if view.group.is_some() {
                    return Err("Lists do not group".into());
                }
            }
            if selected
                .as_ref()
                .is_some_and(|record| record.is_empty() || record.len() > 1024)
            {
                return Err("List selection must be a record ID of 1..1024 UTF-8 bytes".into());
            }
        }
        Node::Checkbox { label, .. } if label.len() > 1024 => {
            return Err("Checkbox label exceeds 1024 UTF-8 bytes".into());
        }
        Node::Slider {
            min,
            max,
            step,
            number,
            ..
        } => {
            if ![min, max, step, number].iter().all(|v| v.is_finite())
                || min.abs() > 1_000_000.
                || max.abs() > 1_000_000.
                || min >= max
                || *step <= 0.
                || *step > max - min
                || min + step <= *min
                || max - step >= *max
                || number < min
                || number > max
            {
                return Err("Invalid slider range, step or number".into());
            }
        }
        Node::Select {
            options,
            selected,
            placeholder,
            ..
        } => {
            if placeholder.len() > 1024 {
                return Err(
                    "Select requires 1..256 options and a placeholder of at most 1024 UTF-8 bytes"
                        .into(),
                );
            }
            validate_options(options, selected.as_ref(), "Select")?;
        }
        Node::Tabs {
            options, selected, ..
        }
        | Node::RadioGroup {
            options, selected, ..
        } => navigation::validate_choices(options, selected)?,
        Node::Switch { label, .. } if label.len() > 1024 => {
            return Err("Switch label exceeds 1024 UTF-8 bytes".into());
        }
        Node::Button {
            tooltip: Some(tooltip),
            ..
        } if tooltip.is_empty() || tooltip.len() > 1024 => {
            return Err("Tooltip requires 1..1024 UTF-8 bytes".into());
        }
        Node::Separator { label, .. } if label.len() > 1024 => {
            return Err("Separator label exceeds 1024 UTF-8 bytes".into());
        }
        Node::Canvas { commands, .. } => {
            if commands.len() > 4096 {
                return Err("Canvas allows at most 4096 commands".into());
            }
            for command in commands {
                command.validate()?;
            }
        }
        Node::MenuButton { label, items, .. } => {
            if label.is_empty() || label.len() > 1024 {
                return Err("Menu button label must contain 1..1024 UTF-8 bytes".into());
            }
            menus::validate_entries(items)?;
        }
        Node::Progress {
            value: Some(value), ..
        } if !value.is_finite() || !(0. ..=100.).contains(value) => {
            return Err("Progress value must be between 0 and 100".into());
        }
        Node::ConfirmDialog {
            label,
            title,
            message,
            confirm_label,
            cancel_label,
            ..
        } => {
            if [label, title, confirm_label, cancel_label]
                .iter()
                .any(|s| s.is_empty() || s.len() > 1024)
                || message.len() > 8192
            {
                return Err(
                    "Dialog labels must contain 1..1024 UTF-8 bytes; message at most 8192".into(),
                );
            }
        }
        _ => {}
    }
    Ok(())
}

impl Snapshot {
    fn validate_actions(&self, ids: &HashSet<String>) -> Result<(), String> {
        validate_bindings(&self.actions, ids)
    }
}

/// Operations against the applied description, submitted through `gd_update`.
/// The batch is atomic: any failing operation rejects the whole update and the
/// applied description stays as it was.
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Update {
    pub revision: u64,
    /// The applied revision this batch was computed against.
    pub base_revision: u64,
    pub ops: Vec<Op>,
    /// Replaces the bindings like a snapshot does; omission clears them.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub actions: Vec<ActionBinding>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub menus: Vec<MenuSpec>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub theme: Option<ThemeSpec>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum Op {
    /// Appends a subtree whose IDs are all new.
    Insert { parent: String, node: Node },
    /// Detaches an existing subtree and appends it to `parent`.
    Reparent { id: String, parent: String },
    /// Detaches and drops a subtree.
    Remove { id: String },
    /// Replaces a node's own fields. The kind stays and children are kept.
    Set { id: String, node: Node },
    /// Reorders a container's children; lists each current child exactly once.
    Children { id: String, children: Vec<String> },
}

const MAX_OPS: usize = 4096;

impl Update {
    /// The snapshot-level checks after operations applied: theme colors,
    /// bindings against the resulting IDs, and application menus.
    pub fn validate_globals(&self, ids: &HashSet<String>) -> Result<(), String> {
        if let Some(theme) = &self.theme {
            theme.colors()?;
        }
        validate_bindings(&self.actions, ids)?;
        menus::validate(&self.menus, &self.actions)
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > MAX_MESSAGE_BYTES {
            return Err("Update exceeds 16 MiB".into());
        }
        let update: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        update.validate()?;
        Ok(update)
    }

    /// Everything checkable without the applied description.
    pub fn validate(&self) -> Result<(), String> {
        if self.base_revision == 0 || self.revision <= self.base_revision {
            return Err("Update revision must follow a positive base revision".into());
        }
        if self.ops.len() > MAX_OPS {
            return Err("At most 4096 operations per update".into());
        }
        for op in &self.ops {
            match op {
                Op::Insert { parent, node } => {
                    if parent.is_empty() {
                        return Err("Insert parent ID must be nonempty".into());
                    }
                    validate_tree(node, 0, &mut HashSet::new())?;
                }
                Op::Set { id, node } => {
                    if node.id() != id {
                        return Err(format!("Set node ID differs from its target: {id}"));
                    }
                    if node.children().is_some_and(|children| !children.is_empty()) {
                        return Err("Set carries own fields only, not children".into());
                    }
                    validate_tree(node, 0, &mut HashSet::new())?;
                }
                Op::Reparent { id, parent } => {
                    if id.is_empty() || parent.is_empty() {
                        return Err("Reparent IDs must be nonempty".into());
                    }
                }
                Op::Remove { id } => {
                    if id.is_empty() {
                        return Err("Remove ID must be nonempty".into());
                    }
                }
                Op::Children { id, children } => {
                    if id.is_empty() || children.len() > MAX_OPS {
                        return Err("Invalid children order".into());
                    }
                }
            }
        }
        Ok(())
    }
}

impl Snapshot {
    /// Test helper: the description after `update`, through the in-place
    /// path the view uses.
    #[cfg(test)]
    pub fn apply(&self, update: &Update) -> Result<Snapshot, String> {
        let mut root = self.root.clone();
        let mut index = TreeIndex::of(&root);
        apply_in_place(&mut root, &mut index, update)?;
        update.validate_globals(&index.ids)?;
        menus::validate_button_menus(&root, &update.actions)?;
        Ok(Snapshot {
            menus: update.menus.clone(),
            theme: update.theme.clone(),
            revision: update.revision,
            actions: update.actions.clone(),
            root,
        })
    }
}

#[cfg(feature = "snapshot-experiment")]
pub(crate) fn find_mut<'a>(node: &'a mut Node, id: &str) -> Option<&'a mut Node> {
    if node.id() == id {
        return Some(node);
    }
    if let Some(children) = children_mut(node) {
        for child in children {
            if let Some(found) = find_mut(child, id) {
                return Some(found);
            }
        }
    }
    None
}

pub(crate) fn children_mut(node: &mut Node) -> Option<&mut Vec<Node>> {
    match node {
        Node::Column { children, .. }
        | Node::Row { children, .. }
        | Node::Stack { children, .. }
        | Node::Scroll { children, .. } => Some(children),
        _ => None,
    }
}

/// Removes and returns the node with `id` from below `node`. The root itself
/// is never detached.
#[cfg(feature = "snapshot-experiment")]
pub(crate) fn detach(node: &mut Node, id: &str) -> Option<Node> {
    if let Some(children) = children_mut(node) {
        if let Some(index) = children.iter().position(|child| child.id() == id) {
            return Some(children.remove(index));
        }
        for child in children {
            if let Some(found) = detach(child, id) {
                return Some(found);
            }
        }
    }
    None
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
    Diagnostic {
        request: u64,
        data: serde_json::Value,
    },
    Ready,
    Applied {
        revision: u64,
        native_apply_us: u64,
    },
    Rejected {
        revision: u64,
        message: String,
    },
    DatasetApplied {
        request: u64,
        id: String,
        revision: u64,
        parse_us: u64,
        apply_us: u64,
        work: crate::datasets::Work,
    },
    DatasetRejected {
        request: u64,
        message: String,
    },
    Click {
        revision: u64,
        id: String,
        #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
        debug_input_sequence: Option<u64>,
    },
    Input {
        revision: u64,
        id: String,
        value: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        input_state: Option<crate::input_control::State>,
    },
    InputResult {
        request: u64,
        id: String,
        status: crate::input_control::Status,
        state: Option<crate::input_control::State>,
    },
    CheckboxChange {
        revision: u64,
        id: String,
        checked: bool,
    },
    SwitchChange {
        revision: u64,
        id: String,
        checked: bool,
    },
    ListSelect {
        revision: u64,
        id: String,
        dataset: String,
        dataset_revision: u64,
        /// View row index, for debugging; consumers key on `record`.
        row: usize,
        record: String,
    },
    WindowOpened {
        request: u64,
        window: u32,
    },
    WindowRejected {
        request: u64,
        window: u32,
        message: String,
    },
    WindowClosed {
        window: u32,
    },
    /// An event from a secondary window. The host callback flattens it into
    /// the inner event plus a `window` field before it reaches Dart.
    InWindow {
        window: u32,
        event: Box<Event>,
    },
    SliderChange {
        revision: u64,
        id: String,
        number: f32,
    },
    TabChange {
        revision: u64,
        id: String,
        selected: String,
    },
    RadioChange {
        revision: u64,
        id: String,
        selected: String,
    },
    SelectChange {
        revision: u64,
        id: String,
        selected: Option<String>,
    },
    DialogResult {
        revision: u64,
        id: String,
        confirmed: bool,
    },
    Action {
        revision: u64,
        name: String,
        context: String,
    },
    RowAction {
        revision: u64,
        id: String,
        dataset: String,
        dataset_revision: u64,
        record: String,
        action: String,
    },
    TableSelection {
        revision: u64,
        id: String,
        dataset: String,
        dataset_revision: u64,
        /// View row index, for debugging; consumers key on `record`.
        row: Option<usize>,
        /// The selected record's stable ID; null when the dataset has no ids
        /// or the selection cleared.
        record: Option<String>,
    },
    Error {
        message: String,
    },
    Closed,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checkbox_validates_types_and_utf8_label_bound() {
        let mut node = serde_json::json!({"kind":"checkbox", "id":"c", "label":"é".repeat(512), "checked":false});
        let parse = |node: &serde_json::Value| {
            Snapshot::parse(
                &serde_json::to_vec(&serde_json::json!({"revision":1,"root":node})).unwrap(),
            )
        };
        assert!(parse(&node).is_ok());
        node["label"] = serde_json::json!("é".repeat(513));
        assert!(parse(&node).unwrap_err().contains("1024"));
        node["label"] = serde_json::json!("");
        node["checked"] = serde_json::json!("false");
        assert!(parse(&node).is_err());
        node["checked"] = serde_json::json!(true);
        node["disabled"] = serde_json::json!(1);
        assert!(parse(&node).is_err());
        node["disabled"] = serde_json::json!(true);
        assert!(parse(&node).is_ok());
        node["unknown"] = serde_json::json!(true);
        assert!(parse(&node).is_err());
    }

    #[test]
    fn slider_rejects_invalid_ranges_and_unrepresentable_steps() {
        let parse = |min: f64, max: f64, step: f64, number: f64| {
            Snapshot::parse(
                &serde_json::to_vec(&serde_json::json!({"revision":1,"root":{
                    "kind":"slider","id":"s","min":min,"max":max,"step":step,"number":number
                }}))
                .unwrap(),
            )
        };
        assert!(parse(-100., 100., 0.5, 25.).is_ok());
        assert!(parse(3., 8., 5., 3.).is_ok());
        for (min, max, step, number) in [
            (0., 0., 1., 0.),
            (5., 1., 1., 3.),
            (0., 10., 0., 5.),
            (0., 10., -1., 5.),
            (0., 10., 11., 5.),
            (0., 10., 1., 11.),
            (0., 10., 1., -1.),
            (-1_000_001., 10., 1., 5.),
            (0., 1_000_001., 1., 5.),
            (999_990., 1_000_000., 0.00001, 999_995.),
            (0., 10., f64::INFINITY, 5.),
            (0., 10., 1., f64::NAN),
        ] {
            assert!(
                parse(min, max, step, number).is_err(),
                "{min} {max} {step} {number}"
            );
        }
    }

    #[test]
    fn select_validates_option_identity_selection_and_bounds() {
        let node = serde_json::json!({"kind":"select","id":"choice",
            "options":[{"id":"light","label":"Light"},{"id":"dark","label":"Dark"}],"selected":"light"});
        let parse = |node: &serde_json::Value| {
            Snapshot::parse(
                &serde_json::to_vec(&serde_json::json!({"revision":1,"root":node})).unwrap(),
            )
        };
        assert!(parse(&node).is_ok());
        for (key, value) in [
            ("selected", serde_json::json!("missing")),
            ("selected", serde_json::json!(false)),
            ("options", serde_json::json!([])),
            ("options", serde_json::json!([{"id":"","label":"X"}])),
            ("options", serde_json::json!([{"id":"light","label":""}])),
            (
                "options",
                serde_json::json!([{"id":"light","label":"X"},{"id":"light","label":"Y"}]),
            ),
            (
                "options",
                serde_json::json!([{"id":"x".repeat(257),"label":"X"}]),
            ),
            (
                "options",
                serde_json::json!([{"id":"light","label":"é".repeat(513)}]),
            ),
            (
                "options",
                serde_json::json!(
                    (0..257)
                        .map(|i| serde_json::json!({"id":i.to_string(),"label":"X"}))
                        .collect::<Vec<_>>()
                ),
            ),
            ("placeholder", serde_json::json!("x".repeat(1025))),
            ("disabled", serde_json::json!("false")),
        ] {
            let mut invalid = node.clone();
            invalid[key] = value;
            assert!(parse(&invalid).is_err(), "{key}");
        }
        let mut empty_selection = node.clone();
        empty_selection["selected"] = serde_json::Value::Null;
        assert!(parse(&empty_selection).is_ok());
    }

    #[test]
    fn confirmation_dialog_validates_labels_message_and_types() {
        let node = serde_json::json!({"kind":"confirm_dialog","id":"reset","label":"Reset","title":"Reset preferences?","message":"Discard draft","confirm_label":"Reset","cancel_label":"Keep","disabled":false});
        let parse = |node: &serde_json::Value| {
            Snapshot::parse(
                &serde_json::to_vec(&serde_json::json!({"revision":1,"root":node})).unwrap(),
            )
        };
        assert!(parse(&node).is_ok());
        for key in ["label", "title", "confirm_label", "cancel_label"] {
            for bad in [
                serde_json::json!(""),
                serde_json::json!("é".repeat(513)),
                serde_json::json!(1),
            ] {
                let mut value = node.clone();
                value[key] = bad;
                assert!(parse(&value).is_err(), "{key}");
            }
        }
        let mut value = node.clone();
        value["message"] = serde_json::json!("é".repeat(4096));
        assert!(parse(&value).is_ok());
        value["message"] = serde_json::json!("é".repeat(4097));
        assert!(parse(&value).is_err());
        value = node.clone();
        value["disabled"] = serde_json::json!(1);
        assert!(parse(&value).is_err());
    }

    #[test]
    fn rejects_ambiguous_retained_identity() {
        let bytes = br#"{"revision":1,"root":{"kind":"column","id":"root","children":[{"kind":"input","id":"a","placeholder":""},{"kind":"button","id":"a","label":"Save"}]}}"#;
        assert!(Snapshot::parse(bytes).unwrap_err().contains("duplicate"));
    }

    #[test]
    fn rejects_inline_table_records() {
        let bytes = br#"{"revision":1,"root":{"kind":"table","id":"table","dataset":"quotes","data":{"columns":["A"],"rows":[["x"]]}}}"#;
        assert!(Snapshot::parse(bytes).is_err());
    }

    #[test]
    fn parses_valid_styles_on_every_node_kind() {
        let bytes = br##"{"revision":1,"root":{"kind":"column","id":"root",
            "style":{"padding":[16,8,16,8],"gap":12,"width":"full","align":"center","justify":"space_between","background":"token:muted","border_color":"#33415580","border_radius":8},
            "children":[
                {"kind":"text","id":"t","text":"Hi","style":{"foreground":"token:foreground","font_size":14,"font_weight":"semibold","width":{"px":320}}},
                {"kind":"button","id":"b","label":"Go","style":{"background":"#1D4ED8"}},
                {"kind":"input","id":"i","placeholder":"","style":{"height":{"px":40}}},
                {"kind":"row","id":"r","children":[],"style":{"gap":4,"align":"stretch"}},
                {"kind":"table","id":"tbl","dataset":"quotes","style":{"height":"fit"}}
            ]}}"##;
        let snapshot = Snapshot::parse(bytes).unwrap();
        let Node::Column {
            style, children, ..
        } = &snapshot.root
        else {
            unreachable!()
        };
        let style = style.as_ref().unwrap();
        assert_eq!(style.padding, Some([16., 8., 16., 8.]));
        assert_eq!(style.gap, Some(12.));
        assert!(matches!(style.width, Some(Size::Full)));
        assert_eq!(children.len(), 5);
        let Node::Text { style, .. } = &children[0] else {
            unreachable!()
        };
        let style = style.as_ref().unwrap();
        assert_eq!(style.foreground, Some(Color::Token(ThemeToken::Foreground)));
        assert_eq!(style.font_size, Some(14.));
        assert!(matches!(style.width, Some(Size::Px(320.))));
        let Node::Button { style, .. } = &children[1] else {
            unreachable!()
        };
        assert_eq!(
            style.as_ref().unwrap().background,
            Some(Color::Hex(0x1D4ED8FF))
        );
    }

    #[test]
    fn rejects_out_of_bounds_style_values() {
        for style in [
            r#""style":{"padding":[0,0,0,513]}"#,
            r#""style":{"padding":[0,0,-1,0]}"#,
            r#""style":{"gap":512.5}"#,
            r#""style":{"border_radius":1024}"#,
            r#""style":{"width":{"px":8193}}"#,
            r#""style":{"height":{"px":-4}}"#,
            r#""style":{"font_size":7}"#,
            r#""style":{"font_size":97}"#,
        ] {
            let node = if style.contains("font_size") {
                format!(r#"{{"kind":"text","id":"t","text":"x",{style}}}"#)
            } else {
                format!(r#"{{"kind":"column","id":"root","children":[],{style}}}"#)
            };
            let bytes = format!(r#"{{"revision":1,"root":{node}}}"#);
            assert!(
                Snapshot::parse(bytes.as_bytes()).is_err(),
                "must reject {style}"
            );
        }
    }

    #[test]
    fn accepts_boundary_style_values() {
        let bytes = br#"{"revision":1,"root":{"kind":"text","id":"t","text":"x",
            "style":{"padding":[512,512,512,512],"gap":0,"border_radius":512,"width":{"px":0},"height":{"px":8192},"font_size":96}}}"#;
        assert!(Snapshot::parse(bytes).is_ok());
    }

    #[test]
    fn rejects_unknown_theme_token() {
        let bytes = br#"{"revision":1,"root":{"kind":"column","id":"root","children":[],"style":{"background":"token:panel"}}}"#;
        assert!(Snapshot::parse(bytes).unwrap_err().contains("token"));
    }

    #[test]
    fn rejects_malformed_hex_colors() {
        for color in ["#12345", "#GGGGGG", "#1234567", "1D4ED8", ""] {
            let bytes = format!(
                r#"{{"revision":1,"root":{{"kind":"column","id":"root","children":[],"style":{{"background":"{color}"}}}}}}"#
            );
            assert!(
                Snapshot::parse(bytes.as_bytes()).is_err(),
                "must reject {color:?}"
            );
        }
    }

    #[test]
    fn rejects_font_style_on_non_text_nodes() {
        for tail in [
            r#""kind":"column","id":"root","children":[]"#,
            r#""kind":"row","id":"root","children":[]"#,
            r#""kind":"button","id":"root","label":"x""#,
            r#""kind":"input","id":"root","placeholder":"""#,
            r#""kind":"table","id":"root","dataset":"d""#,
        ] {
            for field in [r#""font_size":14"#, r#""font_weight":"bold""#] {
                let bytes = format!(r#"{{"revision":1,"root":{{{tail},"style":{{{field}}}}}}}"#);
                let Err(message) = Snapshot::parse(bytes.as_bytes()) else {
                    panic!("must reject {field} on {tail}");
                };
                assert!(message.contains("text nodes only"), "{message}");
            }
        }
    }

    #[test]
    fn rejects_unknown_style_fields() {
        let bytes =
            br#"{"revision":1,"root":{"kind":"text","id":"t","text":"x","style":{"opacity":0.5}}}"#;
        assert!(Snapshot::parse(bytes).is_err());
    }

    #[test]
    fn parses_valid_action_bindings() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"app.search","keys":"ctrl+f","context":"global"},
            {"name":"watchlist.add","keys":"ctrl+enter","context":"tbl"},
            {"name":"watchlist.add","keys":"ctrl+enter","context":"global"},
            {"name":"app.palette","keys":"meta+shift+p","context":"global"},
            {"name":"app.reload","keys":"f5","context":"global"}
        ],"root":{"kind":"table","id":"tbl","dataset":"d"}}"#;
        let snapshot = Snapshot::parse(bytes).unwrap();
        assert_eq!(snapshot.actions.len(), 5);
        // Same keys+name across nested contexts is legal (innermost wins).
        let spec = KeystrokeSpec::parse("shift+ctrl+f").unwrap();
        assert_eq!(spec, KeystrokeSpec::parse("ctrl+shift+f").unwrap());
        assert!(spec.ctrl && spec.shift && !spec.alt && !spec.meta && spec.key == "f");
        assert_eq!(
            KeystrokeSpec::parse("meta+shift+p").unwrap(),
            KeystrokeSpec {
                ctrl: false,
                alt: false,
                shift: true,
                meta: true,
                key: "p".into()
            }
        );
    }

    #[test]
    fn rejects_duplicate_action_name_and_context() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"app.search","keys":"ctrl+f","context":"global"},
            {"name":"app.search","keys":"ctrl+g","context":"global"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        assert!(Snapshot::parse(bytes).unwrap_err().contains("Duplicate"));
    }

    #[test]
    fn rejects_conflicting_keys_in_one_context() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"a","keys":"ctrl+f","context":"global"},
            {"name":"b","keys":"shift+ctrl+f","context":"global"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        let snapshot = Snapshot::parse(bytes);
        assert!(snapshot.is_ok(), "shift+ctrl+f differs from ctrl+f");
        let bytes = br#"{"revision":1,"actions":[
            {"name":"a","keys":"ctrl+f","context":"global"},
            {"name":"b","keys":"ctrl+f","context":"global"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        assert!(
            Snapshot::parse(bytes)
                .unwrap_err()
                .contains("bound to both")
        );
    }

    #[test]
    fn rejects_dangling_action_context() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"a","keys":"ctrl+f","context":"missing"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        assert!(Snapshot::parse(bytes).unwrap_err().contains("not a node"));
    }

    #[test]
    fn rejects_more_than_256_action_bindings() {
        let named = [
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q",
            "r", "s", "t", "u", "v", "w", "x", "y", "z", "enter", "escape", "space", "tab", "up",
            "down",
        ];
        let modifiers = [
            "ctrl+",
            "alt+",
            "shift+",
            "meta+",
            "ctrl+alt+",
            "ctrl+shift+",
            "ctrl+meta+",
            "alt+shift+",
            "alt+meta+",
        ];
        let action = |i: usize| {
            format!(
                r#"{{"name":"a{i}","keys":"{}{}","context":"global"}}"#,
                modifiers[i / named.len()],
                named[i % named.len()]
            )
        };
        let build = |count: usize| {
            format!(
                r#"{{"revision":1,"actions":[{}],"root":{{"kind":"text","id":"t","text":"x"}}}}"#,
                (0..count).map(action).collect::<Vec<_>>().join(",")
            )
        };
        assert!(
            Snapshot::parse(build(257).as_bytes())
                .unwrap_err()
                .contains("256")
        );
        assert!(Snapshot::parse(build(256).as_bytes()).is_ok());
    }

    #[test]
    fn rejects_bare_printable_keys_and_bad_grammar() {
        for keys in [
            "a",
            "7",
            "",
            "ctrl+",
            "+ctrl+f",
            "ctrl++f",
            "ctrl-ctrl-f",
            "ctrl+ctrl+f",
            "super+f",
            "ctrl+F",
            "ctrl+unknown",
            "ctrl+f13",
            "ctrl+page_up",
        ] {
            let bytes = format!(
                r#"{{"revision":1,"actions":[{{"name":"a","keys":"{keys}","context":"global"}}],"root":{{"kind":"text","id":"t","text":"x"}}}}"#
            );
            assert!(
                Snapshot::parse(bytes.as_bytes()).is_err(),
                "must reject keys {keys:?}"
            );
        }
        for keys in [
            "escape",
            "f12",
            "tab",
            "shift+tab",
            "alt+f4",
            "ctrl+alt+delete",
        ] {
            let bytes = format!(
                r#"{{"revision":1,"actions":[{{"name":"a","keys":"{keys}","context":"global"}}],"root":{{"kind":"text","id":"t","text":"x"}}}}"#
            );
            assert!(
                Snapshot::parse(bytes.as_bytes()).is_ok(),
                "must accept keys {keys:?}"
            );
        }
    }

    #[test]
    fn rejects_unknown_action_binding_fields() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"a","keys":"ctrl+f","context":"global","command":"x"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        assert!(Snapshot::parse(bytes).is_err());
    }

    #[test]
    fn parses_and_validates_table_views() {
        let bytes = br#"{"revision":1,"root":{"kind":"table","id":"t","dataset":"d",
            "view":{"sort":[{"column":1,"direction":"desc"}],"filter":[{"column":0,"op":"contains","value":"AC"}]}}}"#;
        let snapshot = Snapshot::parse(bytes).unwrap();
        let Node::Table { view, .. } = &snapshot.root else {
            unreachable!()
        };
        let view = view.as_ref().unwrap();
        assert_eq!(view.sort.len(), 1);
        assert_eq!(view.filter.len(), 1);

        for view in [
            // 5 sort keys
            r#""view":{"sort":[{"column":0,"direction":"asc"},{"column":1,"direction":"asc"},{"column":2,"direction":"asc"},{"column":3,"direction":"asc"},{"column":0,"direction":"desc"}]}"#,
            // 9 filter terms
            r#""view":{"filter":[{"column":0,"op":"eq","value":"1"},{"column":0,"op":"eq","value":"1"},{"column":0,"op":"eq","value":"1"},{"column":0,"op":"eq","value":"1"},{"column":0,"op":"eq","value":"1"},{"column":0,"op":"eq","value":"1"},{"column":0,"op":"eq","value":"1"},{"column":0,"op":"eq","value":"1"},{"column":0,"op":"eq","value":"1"}]}"#,
            r#""view":{"sort":[{"column":64,"direction":"asc"}]}"#,
            r#""view":{"filter":[{"column":64,"op":"eq","value":"x"}]}"#,
            r#""view":{"sort":[{"column":0,"direction":"up"}]}"#,
            r#""view":{"filter":[{"column":0,"op":"startswith","value":"x"}]}"#,
            r#""view":{"limit":10}"#,
            r#""view":{"sort":[{"column":0,"direction":"asc","nulls":"last"}]}"#,
        ] {
            let bytes = format!(
                r#"{{"revision":1,"root":{{"kind":"table","id":"t","dataset":"d",{view}}}}}"#
            );
            assert!(
                Snapshot::parse(bytes.as_bytes()).is_err(),
                "must reject {view}"
            );
        }
    }

    #[test]
    fn grouped_views_insert_headers_with_native_aggregates() {
        let data = TableData {
            columns: vec!["region".into(), "amount".into(), "note".into()],
            rows: vec![
                vec!["east".into(), "10".into(), "a".into()],
                vec!["west".into(), "2.5".into(), "b".into()],
                vec!["east".into(), "n/a".into(), "c".into()],
                vec!["east".into(), "5".into(), "d".into()],
                vec!["west".into(), "1".into(), "e".into()],
            ],
            ids: None,
            format: None,
        };
        let view: TableView = serde_json::from_value(serde_json::json!({
            "sort": [{"column": 1, "direction": "desc"}],
            "group": {"column": 0, "aggregates": [
                {"column": 1, "op": "sum"}, {"column": 1, "op": "avg"}, {"column": 1, "op": "count"},
                {"column": 1, "op": "min"}, {"column": 1, "op": "max"}, {"column": 2, "op": "sum"}
            ]}
        }))
        .unwrap();
        assert!(view.validate().is_ok());
        assert_eq!(view.referenced_columns(), [0, 1, 2].into_iter().collect());
        let index = view.compute_view(&data);
        // Descending by amount: the non-numeric cell sorts lexically above
        // the numbers, so "n/a" leads its group.
        assert_eq!(
            index.entries,
            [
                ViewEntry::Group(0),
                ViewEntry::Record(2),
                ViewEntry::Record(0),
                ViewEntry::Record(3),
                ViewEntry::Group(1),
                ViewEntry::Record(1),
                ViewEntry::Record(4),
            ],
            "sorted first, then grouped in order of first appearance"
        );
        assert_eq!(index.records().collect::<Vec<_>>(), [2, 0, 3, 1, 4]);
        assert_eq!(index.row_of(ViewEntry::Record(2)), Some(1));
        let east = &index.groups[0];
        assert_eq!((east.column, east.key.as_str(), east.count), (0, "east", 3));
        assert_eq!(
            east.aggregates,
            [
                (1, "15".into()),
                (1, "7.5".into()),
                (1, "3".into()),
                (1, "5".into()),
                (1, "10".into()),
                (2, String::new()),
            ],
            "non-numeric cells are ignored except by count"
        );
        assert_eq!(index.groups[1].aggregates[0], (1, "3.5".into()));
        let plain = ViewIndex::compute(None, &data);
        assert_eq!(plain.entries.len(), 5);
        assert!(plain.groups.is_empty());
        for invalid in [
            serde_json::json!({"group": {"column": 64}}),
            serde_json::json!({"group": {"column": 0, "aggregates": [{"column": 64, "op": "sum"}]}}),
            serde_json::json!({"group": {"column": 0, "aggregates": [{"column": 1, "op": "median"}]}}),
            serde_json::json!({"group": {"column": 0, "aggregates": (0..9).map(|_| serde_json::json!({"column": 1, "op": "sum"})).collect::<Vec<_>>()}}),
        ] {
            let parsed = serde_json::from_value::<TableView>(invalid.clone());
            assert!(
                parsed.is_err() || parsed.unwrap().validate().is_err(),
                "{invalid}"
            );
        }
    }

    #[test]
    fn view_index_filters_then_stably_sorts() {
        let data = TableData {
            columns: vec!["sym".into(), "price".into()],
            rows: vec![
                vec!["ACME".into(), "10.5".into()],
                vec!["BETO".into(), "3.2".into()],
                vec!["ALPHA".into(), "7".into()],
                vec!["APEX".into(), "9".into()],
            ],
            ids: None,
            format: None,
        };
        let view = TableView {
            sort: vec![SortKey {
                column: 1,
                direction: SortDirection::Desc,
            }],
            group: None,
            filter: vec![FilterTerm {
                column: 0,
                op: FilterOp::Contains,
                value: "A".into(),
            }],
        };
        // BETO (row 1) is filtered out; numeric sort: 10.5 > 9 > 7.
        assert_eq!(view.compute_index(&data), vec![0, 3, 2]);
        // Numeric comparison: lexically "10" < "9", numerically 9 < 10.
        assert_eq!(compare_cells("10", "9"), std::cmp::Ordering::Greater);
        assert_eq!(compare_cells("x", "9"), std::cmp::Ordering::Greater);
        assert!(FilterOp::Lt.matches("9", "10"));
        assert!(!FilterOp::Lt.matches("x", "9"));
        assert!(FilterOp::Eq.matches("10", "10.0"));
        assert!(FilterOp::Ne.matches("a", "b"));
        assert!(FilterOp::Ge.matches("10", "10"));

        // Equal sort keys keep source order (stable).
        let ties = TableData {
            columns: vec!["v".into()],
            rows: vec![vec!["2".into()], vec!["1".into()], vec!["2".into()]],
            ids: None,
            format: None,
        };
        let view = TableView {
            sort: vec![SortKey {
                column: 0,
                direction: SortDirection::Asc,
            }],
            group: None,
            filter: vec![],
        };
        assert_eq!(view.compute_index(&ties), vec![1, 0, 2]);
    }

    #[test]
    fn view_recompute_at_100k_records_is_measured() {
        let data = TableData {
            columns: vec!["sym".into(), "price".into()],
            rows: (0..100_000)
                .map(|i| vec![format!("S{i:06}"), format!("{}", (i * 7) % 10_000)])
                .collect(),
            ids: Some((0..100_000).map(|i| format!("S{i:06}")).collect()),
            format: None,
        };
        let view = TableView {
            sort: vec![SortKey {
                column: 1,
                direction: SortDirection::Desc,
            }],
            group: None,
            filter: vec![FilterTerm {
                column: 0,
                op: FilterOp::Contains,
                value: "3".into(),
            }],
        };
        let timer = std::time::Instant::now();
        let index = view.compute_index(&data);
        let elapsed = timer.elapsed();
        assert!(index.len() < 100_000 && !index.is_empty());
        let report = serde_json::json!({"records": 100_000, "view_rows": index.len(), "recompute_us": elapsed.as_micros() as u64});
        println!("VIEW_RECOMPUTE {report}");
        if let Ok(path) = std::env::var("GPUIDART_VIEW_RECOMPUTE_REPORT") {
            std::fs::write(path, serde_json::to_string_pretty(&report).unwrap()).unwrap();
        }
    }

    #[test]
    fn cell_formatting_numbers_rules_and_fallback() {
        let spec = ColumnFormat {
            number: Some(NumberFormat { decimals: 2 }),
            rules: vec![
                FormatRule {
                    when: FormatCondition {
                        op: FilterOp::Lt,
                        value: "0".into(),
                    },
                    color: Some(Color::Token(ThemeToken::Danger)),
                    icon: Some(CellIcon::ArrowDown),
                },
                FormatRule {
                    when: FormatCondition {
                        op: FilterOp::Gt,
                        value: "0".into(),
                    },
                    color: Some(Color::Token(ThemeToken::Success)),
                    icon: Some(CellIcon::ArrowUp),
                },
                // Never wins for positive numbers: first match wins.
                FormatRule {
                    when: FormatCondition {
                        op: FilterOp::Contains,
                        value: ".".into(),
                    },
                    color: Some(Color::Hex(0xFFFFFFFF)),
                    icon: None,
                },
            ],
        };
        let cell = spec.apply("10.567");
        assert_eq!(cell.text, "10.57");
        assert_eq!(cell.color, Some(Color::Token(ThemeToken::Success)));
        assert_eq!(cell.icon, Some(CellIcon::ArrowUp));
        let cell = spec.apply("-3.5");
        assert_eq!(cell.text, "-3.50");
        assert_eq!(cell.color, Some(Color::Token(ThemeToken::Danger)));
        assert_eq!(cell.icon, Some(CellIcon::ArrowDown));
        // Non-numeric values render raw; rules still evaluate against the raw
        // string, lexically ("n/a" > "0" so the gt rule matches).
        let cell = spec.apply("n/a");
        assert_eq!(cell.text, "n/a");
        assert_eq!(cell.color, Some(Color::Token(ThemeToken::Success)));
        // A value matching no rule gets no decoration.
        let cell = spec.apply("0");
        assert_eq!(cell.text, "0.00");
        assert!(cell.color.is_none());
        assert!(cell.icon.is_none());

        // First match wins even when a later rule matches more specifically.
        let precedence = ColumnFormat {
            number: None,
            rules: vec![
                FormatRule {
                    when: FormatCondition {
                        op: FilterOp::Contains,
                        value: "A".into(),
                    },
                    color: Some(Color::Token(ThemeToken::Danger)),
                    icon: None,
                },
                FormatRule {
                    when: FormatCondition {
                        op: FilterOp::Eq,
                        value: "ACME".into(),
                    },
                    color: Some(Color::Token(ThemeToken::Success)),
                    icon: None,
                },
            ],
        };
        assert_eq!(
            precedence.apply("ACME").color,
            Some(Color::Token(ThemeToken::Danger))
        );

        // decimals 0 rounds to the nearest integer; no grouping. Ties round
        // to even, per Rust's float formatting.
        let plain = ColumnFormat {
            number: Some(NumberFormat { decimals: 0 }),
            rules: vec![],
        };
        assert_eq!(plain.apply("1234.6").text, "1235");
        assert_eq!(plain.apply("1234.4").text, "1234");
        assert_eq!(plain.apply("2.5").text, "2");
        assert_eq!(plain.apply("-0.6").text, "-1");
    }

    #[test]
    fn cell_format_rejects_unknown_op_icon_color_and_fields() {
        for format in [
            r#"{"columns":{"1":{"rules":[{"when":{"op":"startswith","value":"x"}}]}}}"#,
            r#"{"columns":{"1":{"rules":[{"when":{"op":"lt","value":"0"},"icon":"spin"}]}}}"#,
            r#"{"columns":{"1":{"rules":[{"when":{"op":"lt","value":"0"},"color":"token:panel"}]}}}"#,
            r##"{"columns":{"1":{"rules":[{"when":{"op":"lt","value":"0"},"color":"#12345"}]}}}"##,
            r#"{"columns":{"1":{"number":{"decimals":2,"grouping":true}}}}"#,
            r#"{"columns":{"1":{"grouped":true}}}"#,
            r#"{"columns":{"x":{"number":{"decimals":2}}}}"#,
        ] {
            let data = format!(r#"{{"columns":["a","b"],"rows":[],"format":{format}}}"#);
            assert!(
                serde_json::from_str::<TableData>(&data).is_err(),
                "must reject {format}"
            );
        }
    }

    #[test]
    fn cell_formatter_cost_is_measured_at_100k_cells() {
        let spec = ColumnFormat {
            number: Some(NumberFormat { decimals: 2 }),
            rules: vec![
                FormatRule {
                    when: FormatCondition {
                        op: FilterOp::Lt,
                        value: "0".into(),
                    },
                    color: Some(Color::Token(ThemeToken::Danger)),
                    icon: Some(CellIcon::ArrowDown),
                },
                FormatRule {
                    when: FormatCondition {
                        op: FilterOp::Gt,
                        value: "0".into(),
                    },
                    color: Some(Color::Token(ThemeToken::Success)),
                    icon: Some(CellIcon::ArrowUp),
                },
            ],
        };
        let timer = std::time::Instant::now();
        let mut cells = 0usize;
        for i in 0..100_000i64 {
            let formatted = spec.apply(&format!("{i}"));
            std::hint::black_box(&formatted.text);
            cells += 1;
        }
        let per_cell = timer.elapsed().as_nanos() as u64 / cells as u64;
        let report = serde_json::json!({"cells": cells, "formatter_ns_per_cell": per_cell});
        println!("CELL_FORMATTER {report}");
        if let Ok(path) = std::env::var("GPUIDART_CELL_FORMATTER_REPORT") {
            std::fs::write(path, serde_json::to_string_pretty(&report).unwrap()).unwrap();
        }
    }

    #[test]
    fn nodes_without_style_behave_as_before() {
        let bytes = br#"{"revision":1,"root":{"kind":"text","id":"t","text":"x"}}"#;
        let snapshot = Snapshot::parse(bytes).unwrap();
        assert!(snapshot.root.style().is_none());
        let encoded = serde_json::to_value(&snapshot.root).unwrap();
        assert_eq!(
            encoded,
            serde_json::json!({"kind":"text","id":"t","text":"x"})
        );
    }

    #[test]
    fn stack_and_scroll_are_containers_with_layout_styles() {
        let snapshot = Snapshot::parse(
            br#"{"revision":1,"root":{"kind":"column","id":"root","children":[
                {"kind":"stack","id":"stack","style":{"height":{"px":200},"flex":1},"semantics":{"role":"group","label":"Layers"},"children":[
                    {"kind":"text","id":"under","text":"Under"},
                    {"kind":"text","id":"badge","text":"Badge","style":{"inset":{"top":8,"right":8}}}
                ]},
                {"kind":"scroll","id":"list","axis":"horizontal","style":{"max_height":{"px":300},"min_width":"full"},"children":[
                    {"kind":"text","id":"a","text":"A"}
                ]},
                {"kind":"scroll","id":"default","children":[]}
            ]}}"#,
        )
        .unwrap();
        let mut ids = Vec::new();
        snapshot
            .root
            .visit(&mut |node| ids.push(node.id().to_owned()));
        assert_eq!(
            ids,
            ["root", "stack", "under", "badge", "list", "a", "default"]
        );
        assert!(matches!(
            snapshot.root.children().unwrap()[1],
            Node::Scroll {
                axis: ScrollAxis::Horizontal,
                ..
            }
        ));
        assert!(matches!(
            snapshot.root.children().unwrap()[2],
            Node::Scroll {
                axis: ScrollAxis::Vertical,
                ..
            }
        ));
        let update = Update::parse(
            br#"{"revision":2,"base_revision":1,"ops":[
                {"op":"set","id":"list","node":{"kind":"scroll","id":"list","axis":"both"}},
                {"op":"reparent","id":"a","parent":"stack"}
            ]}"#,
        )
        .unwrap();
        let after = snapshot.apply(&update).unwrap();
        let list = &after.root.children().unwrap()[1];
        assert!(matches!(
            list,
            Node::Scroll {
                axis: ScrollAxis::Both,
                ..
            }
        ));
        assert_eq!(
            after.root.children().unwrap()[0].children().unwrap().len(),
            3
        );
        for invalid in [
            r#"{"kind":"text","id":"t","text":"x","style":{"flex":65}}"#,
            r#"{"kind":"text","id":"t","text":"x","style":{"flex":-1}}"#,
            r#"{"kind":"text","id":"t","text":"x","style":{"min_width":{"px":-1}}}"#,
            r#"{"kind":"text","id":"t","text":"x","style":{"max_height":{"px":9000}}}"#,
            r#"{"kind":"text","id":"t","text":"x","style":{"inset":{"top":-4}}}"#,
            r#"{"kind":"text","id":"t","text":"x","style":{"inset":{"middle":4}}}"#,
            r#"{"kind":"scroll","id":"s","axis":"diagonal","children":[]}"#,
            r#"{"kind":"stack","id":"s","semantics":{"role":"button"},"children":[]}"#,
        ] {
            let bytes = format!(r#"{{"revision":1,"root":{invalid}}}"#);
            assert!(Snapshot::parse(bytes.as_bytes()).is_err(), "{invalid}");
        }
    }

    #[test]
    fn switches_radio_groups_progress_and_separators_validate() {
        let snapshot = Snapshot::parse(
            br#"{"revision":1,"root":{"kind":"column","id":"root","children":[
                {"kind":"button","id":"save","label":"Save","tooltip":"Ctrl+S"},
                {"kind":"switch","id":"wifi","label":"Wi-Fi","checked":true,"semantics":{"role":"switch"}},
                {"kind":"radio_group","id":"mode","options":[{"id":"auto","label":"Automatic"},{"id":"manual","label":"Manual"}],"selected":"auto","semantics":{"role":"radio_group","label":"Mode"}},
                {"kind":"progress","id":"upload","value":42.5,"semantics":{"role":"progress_bar","label":"Upload"}},
                {"kind":"progress","id":"busy"},
                {"kind":"separator","id":"rule","label":"Advanced","semantics":{"role":"separator"}},
                {"kind":"separator","id":"vrule","vertical":true}
            ]}}"#,
        )
        .unwrap();
        let children = snapshot.root.children().unwrap();
        assert!(
            matches!(&children[0], Node::Button { tooltip, .. } if tooltip.as_deref() == Some("Ctrl+S"))
        );
        assert!(matches!(&children[4], Node::Progress { value: None, .. }));
        assert!(matches!(
            &children[6],
            Node::Separator { vertical: true, .. }
        ));
        for invalid in [
            format!(r#"{{"kind":"switch","id":"s","label":"{}","checked":false}}"#, "y".repeat(1025)),
            r#"{"kind":"switch","id":"s","label":"Wi-Fi"}"#.into(),
            r#"{"kind":"radio_group","id":"m","options":[],"selected":"a"}"#.into(),
            r#"{"kind":"radio_group","id":"m","options":[{"id":"a","label":"A"},{"id":"a","label":"B"}],"selected":"a"}"#.into(),
            r#"{"kind":"radio_group","id":"m","options":[{"id":"a","label":"A"}],"selected":"b"}"#.into(),
            r#"{"kind":"progress","id":"p","value":101}"#.into(),
            r#"{"kind":"progress","id":"p","value":-1}"#.into(),
            format!(r#"{{"kind":"separator","id":"r","label":"{}"}}"#, "y".repeat(1025)),
            format!(r#"{{"kind":"button","id":"b","label":"Go","tooltip":"{}"}}"#, "y".repeat(1025)),
            r#"{"kind":"switch","id":"s","label":"Wi-Fi","checked":true,"semantics":{"role":"checkbox"}}"#.into(),
            r#"{"kind":"progress","id":"p","semantics":{"role":"slider"}}"#.into(),
        ] {
            let bytes = format!(r#"{{"revision":1,"root":{invalid}}}"#);
            assert!(Snapshot::parse(bytes.as_bytes()).is_err(), "{invalid}");
        }
    }

    #[test]
    fn tabs_canvases_and_animations_validate() {
        let snapshot = Snapshot::parse(
            br##"{"revision":1,"root":{"kind":"column","id":"root","children":[
                {"kind":"tabs","id":"pages","options":[{"id":"first","label":"First"},{"id":"second","label":"Second"}],"selected":"second","semantics":{"role":"tab_list"}},
                {"kind":"canvas","id":"chart","style":{"width":{"px":200},"height":{"px":100}},"semantics":{"role":"image","label":"Chart"},"commands":[
                    {"op":"rect","x":0,"y":0,"width":50,"height":20,"fill":"token:primary","radius":4},
                    {"op":"circle","cx":80,"cy":50,"radius":10,"stroke":"#ff0000","stroke_width":2},
                    {"op":"line","x1":0,"y1":0,"x2":200,"y2":100,"color":"token:border"},
                    {"op":"polyline","points":[[0,100],[50,20],[100,80]],"stroke":"token:danger","width":3}
                ]},
                {"kind":"text","id":"fade","text":"Fading","style":{"animation":{"duration_ms":300,"opacity":[0,1],"repeat":true,"easing":"linear","key":"in"}}},
                {"kind":"text","id":"slide","text":"Sliding","style":{"animation":{"duration_ms":300,"offset":[[0,0],[100,0]]}}}
            ]}}"##,
        )
        .unwrap();
        let children = snapshot.root.children().unwrap();
        assert!(matches!(&children[0], Node::Tabs { selected, .. } if selected == "second"));
        assert!(matches!(&children[1], Node::Canvas { commands, .. } if commands.len() == 4));
        for invalid in [
            r#"{"kind":"tabs","id":"t","options":[{"id":"a","label":"A"}],"selected":"b"}"#.into(),
            r#"{"kind":"tabs","id":"t","options":[],"selected":"a"}"#.into(),
            r#"{"kind":"tabs","id":"t","options":[{"id":"a","label":"A"}],"selected":"a","variant":"pill"}"#.into(),
            r#"{"kind":"canvas","id":"c","commands":[{"op":"rect","x":0,"y":0,"width":-1,"height":1}]}"#.into(),
            r#"{"kind":"canvas","id":"c","commands":[{"op":"rect","x":9000,"y":0,"width":1,"height":1}]}"#.into(),
            r#"{"kind":"canvas","id":"c","commands":[{"op":"line","x1":0,"y1":0,"x2":1,"y2":1,"color":"token:border","width":600}]}"#.into(),
            r#"{"kind":"canvas","id":"c","commands":[{"op":"polyline","points":[[0,0]],"stroke":"token:border"}]}"#.into(),
            r#"{"kind":"canvas","id":"c","commands":[{"op":"polyline","points":[[0,0],[1,1]]}]}"#.into(),
            r#"{"kind":"canvas","id":"c","commands":[{"op":"triangle"}]}"#.into(),
            format!(
                r#"{{"kind":"canvas","id":"c","commands":[{}]}}"#,
                vec![r#"{"op":"rect","x":0,"y":0,"width":1,"height":1}"#; 4097].join(",")
            ),
            r#"{"kind":"text","id":"t","text":"x","style":{"animation":{"duration_ms":0,"opacity":[0,1]}}}"#.into(),
            r#"{"kind":"text","id":"t","text":"x","style":{"animation":{"duration_ms":100}}}"#.into(),
            r#"{"kind":"text","id":"t","text":"x","style":{"animation":{"duration_ms":100,"opacity":[0,2]}}}"#.into(),
            r#"{"kind":"text","id":"t","text":"x","style":{"animation":{"duration_ms":100,"offset":[[0,0],[9000,0]]}}}"#.into(),
            r#"{"kind":"text","id":"t","text":"x","style":{"animation":{"duration_ms":100,"opacity":[0,1],"easing":"elastic"}}}"#.into(),
            r#"{"kind":"canvas","id":"c","commands":[],"semantics":{"role":"button"}}"#.into(),
        ] {
            let bytes = format!(r#"{{"revision":1,"root":{invalid}}}"#);
            assert!(Snapshot::parse(bytes.as_bytes()).is_err(), "{invalid}");
        }
    }

    #[test]
    fn menu_buttons_take_application_menu_entries_bound_to_global_actions() {
        let snapshot = Snapshot::parse(
            br#"{"revision":1,"actions":[{"name":"file.open","keys":"ctrl+o","context":"global"},{"name":"view.wrap","keys":"alt+z","context":"global"}],"root":{"kind":"menu_button","id":"file","label":"File","semantics":{"role":"button"},"items":[
                {"kind":"action","id":"open","label":"Open","action":"file.open"},
                {"kind":"separator"},
                {"kind":"action","id":"wrap","label":"Word wrap","action":"view.wrap","checked":true,"disabled":true}
            ]}}"#,
        )
        .unwrap();
        let Node::MenuButton { items, .. } = &snapshot.root else {
            panic!("menu button");
        };
        assert_eq!(items.len(), 3);
        assert!(matches!(&items[1], MenuEntry::Separator));
        assert!(matches!(
            &items[2],
            MenuEntry::Action {
                checked: true,
                disabled: true,
                ..
            }
        ));
        let bound = r#""actions":[{"name":"file.open","keys":"ctrl+o","context":"global"}],"#;
        for (actions, invalid) in [
            (bound, r#"{"kind":"menu_button","id":"m","label":"","items":[{"kind":"action","id":"a","label":"A","action":"file.open"}]}"#.to_string()),
            (bound, r#"{"kind":"menu_button","id":"m","label":"File","items":[]}"#.into()),
            (bound, r#"{"kind":"menu_button","id":"m","label":"File","items":[{"kind":"action","id":"a","label":"A","action":"file.open"},{"kind":"action","id":"a","label":"B","action":"file.open"}]}"#.into()),
            (bound, r#"{"kind":"menu_button","id":"m","label":"File","items":[{"kind":"action","id":"","label":"A","action":"file.open"}]}"#.into()),
            (bound, r#"{"kind":"menu_button","id":"m","label":"File","items":[{"divider":true}]}"#.into()),
            ("", r#"{"kind":"menu_button","id":"m","label":"File","items":[{"kind":"action","id":"a","label":"A","action":"file.open"}]}"#.into()),
            (bound, format!(
                r#"{{"kind":"menu_button","id":"m","label":"File","items":[{}]}}"#,
                (0..65).map(|i| format!(r#"{{"kind":"action","id":"i{i}","label":"I","action":"file.open"}}"#)).collect::<Vec<_>>().join(",")
            )),
            (bound, r#"{"kind":"menu_button","id":"m","label":"File","items":[{"kind":"action","id":"a","label":"A","action":"file.open"}],"semantics":{"role":"switch"}}"#.into()),
        ] {
            let bytes = format!(r#"{{"revision":1,{actions}"root":{invalid}}}"#);
            assert!(Snapshot::parse(bytes.as_bytes()).is_err(), "{invalid}");
        }
    }

    #[test]
    fn lists_validate_dataset_column_view_and_selection() {
        let snapshot = Snapshot::parse(
            br#"{"revision":1,"root":{"kind":"list","id":"names","dataset":"people","column":1,"selected":"p2","semantics":{"role":"list"},"view":{"sort":[{"column":1,"direction":"asc"}]}}}"#,
        )
        .unwrap();
        let Node::List {
            column, selected, ..
        } = &snapshot.root
        else {
            panic!("list");
        };
        assert_eq!((*column, selected.as_deref()), (1, Some("p2")));
        for invalid in [
            r#"{"kind":"list","id":"l","dataset":"","column":0}"#,
            r#"{"kind":"list","id":"l","dataset":"d","column":64}"#,
            r#"{"kind":"list","id":"l","dataset":"d","column":0,"selected":""}"#,
            r#"{"kind":"list","id":"l","dataset":"d","column":0,"view":{"group":{"column":0}}}"#,
            r#"{"kind":"list","id":"l","dataset":"d","column":0,"semantics":{"role":"table"}}"#,
            r#"{"kind":"list","id":"l","dataset":"d","column":0,"children":[]}"#,
        ] {
            let bytes = format!(r#"{{"revision":1,"root":{invalid}}}"#);
            assert!(Snapshot::parse(bytes.as_bytes()).is_err(), "{invalid}");
        }
    }

    #[test]
    fn cached_subtrees_need_a_container_with_a_fixed_height() {
        let snapshot = Snapshot::parse(
            br#"{"revision":1,"root":{"kind":"column","id":"root","children":[
                {"kind":"column","id":"part","style":{"height":{"px":200},"cached":true},"children":[{"kind":"text","id":"t","text":"x"}]}
            ]}}"#,
        )
        .unwrap();
        let cached = snapshot.root.children().unwrap()[0].style().unwrap().cached;
        assert!(cached);
        for invalid in [
            r#"{"kind":"text","id":"t","text":"x","style":{"cached":true}}"#,
            r#"{"kind":"column","id":"c","style":{"cached":true},"children":[]}"#,
            r#"{"kind":"column","id":"c","style":{"height":"full","cached":true},"children":[]}"#,
        ] {
            let bytes = format!(r#"{{"revision":1,"root":{invalid}}}"#);
            assert!(Snapshot::parse(bytes.as_bytes()).is_err(), "{invalid}");
        }
    }

    fn applied() -> Snapshot {
        Snapshot::parse(
            br#"{"revision":4,"actions":[{"name":"save","keys":"ctrl+s","context":"name"}],"root":{"kind":"column","id":"root","children":[
                {"kind":"text","id":"a","text":"A"},
                {"kind":"input","id":"name","placeholder":"Name"},
                {"kind":"row","id":"r","children":[{"kind":"text","id":"c","text":"C"}]}
            ]}}"#,
        )
        .unwrap()
    }

    fn update(json: serde_json::Value) -> Result<Update, String> {
        Update::parse(&serde_json::to_vec(&json).unwrap())
    }

    #[test]
    fn update_parse_checks_shape_and_static_bounds() {
        assert!(update(serde_json::json!({"revision":5,"base_revision":4,"ops":[]})).is_ok());
        for invalid in [
            serde_json::json!({"revision":4,"base_revision":4,"ops":[]}),
            serde_json::json!({"revision":5,"base_revision":0,"ops":[]}),
            serde_json::json!({"revision":5,"base_revision":4,"ops":[],"extra":1}),
            serde_json::json!({"revision":5,"base_revision":4,"ops":[{"op":"paint","id":"a"}]}),
            serde_json::json!({"revision":5,"base_revision":4,"ops":[{"op":"set","id":"a","node":{"kind":"text","id":"b","text":"B"}}]}),
            serde_json::json!({"revision":5,"base_revision":4,"ops":[{"op":"set","id":"r","node":{"kind":"row","id":"r","children":[{"kind":"text","id":"x","text":"X"}]}}]}),
            serde_json::json!({"revision":5,"base_revision":4,"ops":[{"op":"insert","parent":"root","node":{"kind":"text","id":"","text":"X"}}]}),
            serde_json::json!({"revision":5,"base_revision":4,"ops":[{"op":"insert","parent":"root","node":{"kind":"checkbox","id":"x","label":"y".repeat(1025),"checked":true}}]}),
            serde_json::json!({"revision":5,"base_revision":4,"ops":[{"op":"remove","id":""}]}),
        ] {
            assert!(update(invalid.clone()).is_err(), "{invalid}");
        }
        let too_many = serde_json::json!({"revision":5,"base_revision":4,"ops":(0..4097).map(|i| serde_json::json!({"op":"remove","id":format!("n{i}")})).collect::<Vec<_>>()});
        assert!(update(too_many).is_err());
    }

    #[test]
    fn apply_runs_every_operation_and_leaves_the_original() {
        let before = applied();
        let batch = update(serde_json::json!({
            "revision":5,"base_revision":4,
            "actions":[{"name":"save","keys":"ctrl+enter","context":"global"}],
            "ops":[
                {"op":"insert","parent":"root","node":{"kind":"row","id":"r2","children":[{"kind":"text","id":"d","text":"D"}]}},
                {"op":"reparent","id":"name","parent":"r2"},
                {"op":"remove","id":"c"},
                {"op":"set","id":"a","node":{"kind":"text","id":"a","text":"A2","style":{"gap":4}}},
                {"op":"set","id":"r2","node":{"kind":"row","id":"r2","style":{"gap":8}}},
                {"op":"children","id":"root","children":["r2","r","a"]}
            ]
        }))
        .unwrap();
        let after = before.apply(&batch).unwrap();
        assert_eq!(after.revision, 5);
        assert_eq!(after.actions.len(), 1);
        assert_eq!(after.actions[0].keys, "ctrl+enter");
        let expected = Snapshot::parse(
            br#"{"revision":5,"root":{"kind":"column","id":"root","children":[
                {"kind":"row","id":"r2","style":{"gap":8},"children":[
                    {"kind":"text","id":"d","text":"D"},
                    {"kind":"input","id":"name","placeholder":"Name"}
                ]},
                {"kind":"row","id":"r","children":[]},
                {"kind":"text","id":"a","text":"A2","style":{"gap":4}}
            ]}}"#,
        )
        .unwrap();
        assert_eq!(
            serde_json::to_value(&after.root).unwrap(),
            serde_json::to_value(&expected.root).unwrap()
        );
        assert_eq!(
            serde_json::to_value(&before.root).unwrap(),
            serde_json::to_value(&applied().root).unwrap()
        );
        assert_eq!(before.revision, 4);
    }

    #[test]
    fn apply_rejects_bad_targets_and_resulting_descriptions() {
        let before = applied();
        for (ops, expected) in [
            (
                serde_json::json!([{"op":"insert","parent":"root","node":{"kind":"text","id":"a","text":"dup"}}]),
                "existing node ID",
            ),
            (
                serde_json::json!([{"op":"insert","parent":"missing","node":{"kind":"text","id":"x","text":"X"}}]),
                "parent is missing",
            ),
            (
                serde_json::json!([{"op":"insert","parent":"a","node":{"kind":"text","id":"x","text":"X"}}]),
                "no children",
            ),
            (
                serde_json::json!([{"op":"reparent","id":"root","parent":"r"}]),
                "missing or the root",
            ),
            (
                serde_json::json!([{"op":"reparent","id":"r","parent":"c"}]),
                "inside the moved subtree",
            ),
            (
                serde_json::json!([{"op":"remove","id":"missing"}]),
                "missing or the root",
            ),
            (
                serde_json::json!([{"op":"set","id":"a","node":{"kind":"button","id":"a","label":"A"}}]),
                "changes the kind",
            ),
            (
                serde_json::json!([{"op":"children","id":"root","children":["a","name"]}]),
                "every child once",
            ),
            (
                serde_json::json!([{"op":"children","id":"root","children":["a","name","name"]}]),
                "not a child",
            ),
            (
                serde_json::json!([{"op":"remove","id":"name"}]),
                "Action context",
            ),
        ] {
            let batch = update(serde_json::json!({"revision":5,"base_revision":4,"ops":ops,"actions":[{"name":"save","keys":"ctrl+s","context":"name"}]})).unwrap();
            let error = before.apply(&batch).unwrap_err();
            assert!(error.contains(expected), "{ops}: {error}");
        }
        // Thirty-three levels parse on their own and exceed the bound once
        // they hang below the root.
        let mut deep = serde_json::json!({"kind":"text","id":"leaf","text":"x"});
        for depth in 0..32 {
            deep = serde_json::json!({"kind":"column","id":format!("d{depth}"),"children":[deep]});
        }
        let batch = update(serde_json::json!({"revision":5,"base_revision":4,"ops":[{"op":"insert","parent":"root","node":deep}]})).unwrap();
        assert!(before.apply(&batch).unwrap_err().contains("deeply nested"));
        assert_eq!(
            serde_json::to_value(&before.root).unwrap(),
            serde_json::to_value(&applied().root).unwrap()
        );
    }
}
