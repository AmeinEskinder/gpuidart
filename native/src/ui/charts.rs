use super::*;
use crate::{
    datasets::Dataset,
    protocol::{ChartKind, ChartSpec},
};
use gpui_kit::component::chart::{BarChart, LineChart};
use serde::Serialize;

#[derive(Serialize)]
pub(super) struct Point {
    pub record: Option<String>,
    pub source: usize,
    pub label: String,
    pub value: f64,
}

// Equal display labels still occupy distinct bands/points.
#[derive(Clone, PartialEq, Eq, Hash)]
struct AxisKey {
    source: usize,
    label: String,
}
impl From<AxisKey> for SharedString {
    fn from(key: AxisKey) -> Self {
        key.label.into()
    }
}
impl Point {
    fn axis(&self) -> AxisKey {
        AxisKey {
            source: self.source,
            label: self.label.clone(),
        }
    }
}

pub(super) struct RetainedChart {
    pub spec: ChartSpec,
    pub revision: u64,
    pub points: Rc<Vec<Rc<Point>>>,
    pub view_rows: usize,
    pub omitted: usize,
    pub excluded: usize,
    pub projections: u64,
}

impl RetainedChart {
    fn project(spec: ChartSpec, data: &Dataset, projections: u64) -> Self {
        let (candidates, view_rows) = if let Some(view) = &spec.view {
            let index = view.compute_index(&data.data);
            let count = index.len();
            (
                index
                    .into_iter()
                    .skip(count.saturating_sub(spec.max_points))
                    .collect::<Vec<_>>(),
                count,
            )
        } else {
            let count = data.data.rows.len();
            (
                (count.saturating_sub(spec.max_points)..count).collect::<Vec<_>>(),
                count,
            )
        };
        let excluded = view_rows - candidates.len();
        let mut omitted = 0;
        let points = candidates
            .into_iter()
            .filter_map(|source| {
                let row = &data.data.rows[source];
                let value = row[spec.value_column]
                    .parse::<f64>()
                    .ok()
                    .filter(|v| v.is_finite() && v.abs() <= 1e12);
                let Some(value) = value else {
                    omitted += 1;
                    return None;
                };
                Some(Rc::new(Point {
                    record: data.data.ids.as_ref().map(|ids| ids[source].clone()),
                    source,
                    label: row[spec.label_column].chars().take(128).collect(),
                    value,
                }))
            })
            .collect();
        Self {
            spec,
            revision: data.revision,
            points: Rc::new(points),
            view_rows,
            omitted,
            excluded,
            projections,
        }
    }

    fn summary(&self) -> String {
        let kind = match self.spec.series {
            ChartKind::Line => "Line",
            ChartKind::Bar => "Bar",
        };
        let range = match (self.points.first(), self.points.last()) {
            (Some(first), Some(last)) => {
                let min = self
                    .points
                    .iter()
                    .map(|p| p.value)
                    .fold(f64::INFINITY, f64::min);
                let max = self
                    .points
                    .iter()
                    .map(|p| p.value)
                    .fold(f64::NEG_INFINITY, f64::max);
                format!(
                    "First {}: {}; last {}: {}; range {} to {}.",
                    first.label, first.value, last.label, last.value, min, max
                )
            }
            _ => "No valid points.".into(),
        };
        format!(
            "{kind} chart. {} points from {} view rows. {} invalid values omitted; {} earlier rows excluded. {range}",
            self.points.len(),
            self.view_rows,
            self.omitted,
            self.excluded
        )
    }
}

impl DartView {
    pub(super) fn reconcile_charts(&mut self) -> Result<(), String> {
        let mut mounted = HashSet::new();
        let mut error = None;
        self.snapshot.root.visit(&mut |node| {
            let Node::Chart { id, chart, .. } = node else {
                return;
            };
            mounted.insert(id.clone());
            let Some(data) = self.datasets.entries.get(&chart.dataset) else {
                error = Some(format!("Missing chart dataset: {}", chart.dataset));
                return;
            };
            let data = data.borrow();
            if self
                .charts
                .get(id)
                .is_some_and(|r| r.spec == *chart && r.revision == data.revision)
            {
                return;
            }
            let projections = self.charts.get(id).map_or(1, |r| r.projections + 1);
            self.charts.insert(
                id.clone(),
                RetainedChart::project(chart.clone(), &data, projections),
            );
        });
        self.charts.retain(|id, _| mounted.contains(id));
        error.map_or(Ok(()), Err)
    }

    pub(super) fn update_charts(&mut self, dataset: &str, touched: Option<&HashSet<usize>>) {
        for retained in self
            .charts
            .values_mut()
            .filter(|r| r.spec.dataset == dataset)
        {
            let Some(data) = self.datasets.entries.get(dataset) else {
                continue;
            };
            let data = data.borrow();
            let spec = &retained.spec;
            let changed = touched.is_none_or(|columns| {
                columns.contains(&spec.label_column)
                    || columns.contains(&spec.value_column)
                    || spec
                        .view
                        .as_ref()
                        .is_some_and(|v| v.referenced_columns().iter().any(|c| columns.contains(c)))
            });
            if changed {
                *retained = RetainedChart::project(spec.clone(), &data, retained.projections + 1);
            } else {
                retained.revision = data.revision;
            }
        }
    }

    pub(super) fn inspect_charts(&self) -> Value {
        self.charts
            .iter()
            .map(|(id, r)| {
                (
                    id.clone(),
                    json!({
                        "dataset":r.spec.dataset,"revision":r.revision,"points":r.points,
                        "view_rows":r.view_rows,"omitted":r.omitted,"excluded":r.excluded,
                        "projections":r.projections,"summary":r.summary(),
                    }),
                )
            })
            .collect::<serde_json::Map<_, _>>()
            .into()
    }

    pub(super) fn chart_element(
        &self,
        node: &Node,
        colors: &ThemeColor,
    ) -> Result<AnyElement, String> {
        let id = node.id();
        let retained = self
            .charts
            .get(id)
            .ok_or_else(|| format!("Missing chart: {id}"))?;
        let name = accessible_name(node);
        let summary = retained.summary();
        let plot_id = SharedString::from(json!([id, "plot"]).to_string());
        let plot = if retained.points.is_empty() {
            div().child("No valid chart data").into_any_element()
        } else {
            match retained.spec.series {
                ChartKind::Line => LineChart::new(retained.points.iter().cloned())
                    .id(plot_id)
                    .name(name.clone())
                    .x(|p| p.axis())
                    .y(|p| p.value)
                    .linear()
                    .dot()
                    .y_axis(true)
                    .stroke(colors.primary)
                    .interactive(false)
                    .into_any_element(),
                ChartKind::Bar => {
                    let color = colors.primary;
                    BarChart::new(retained.points.iter().cloned())
                        .id(plot_id)
                        .name(name.clone())
                        .band(|p| p.axis())
                        .value(|p| p.value)
                        .fill(move |_, _, _, _| color)
                        .value_axis(true)
                        .interactive(false)
                        .into_any_element()
                }
            }
        };
        let points = retained.points.clone();
        let chart_id = id.to_owned();
        let dataset = retained.spec.dataset.clone();
        Ok(apply_node_style(
            div()
                .id(SharedString::from(id.to_owned()))
                .test_support()
                .accessibility_id(id.to_owned())
                .role(Role::Group)
                .aria_label(name)
                .aria_description(summary.clone())
                .a11y_synthetic_children(move |tree| {
                    for point in points.iter() {
                        let key = json!([
                            chart_id,
                            dataset,
                            point
                                .record
                                .as_ref()
                                .map_or_else(|| json!(point.source), |id| json!(id))
                        ])
                        .to_string();
                        let node_id = tree.synthetic_node_id(SharedString::from(key.clone()));
                        let mut alternative = gpui::accesskit::Node::new(Role::Label);
                        alternative.set_author_id(key);
                        alternative.set_value(format!("{}: {}", point.label, point.value));
                        tree.push_child(node_id, alternative);
                    }
                })
                .flex()
                .flex_col()
                .w_full()
                .gap_2()
                .child(div().w_full().h(px(retained.spec.height)).child(plot))
                .child(
                    div()
                        .id(SharedString::from(json!([id, "summary"]).to_string()))
                        .test_support()
                        .role(Role::Label)
                        .aria_value(summary.clone())
                        .accessibility_id(json!([id, "summary"]).to_string())
                        .text_color(colors.muted_foreground)
                        .child(summary),
                ),
            node,
            colors,
        )
        .into_any_element())
    }
}
