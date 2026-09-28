use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ChartKind {
    Line,
    Bar,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChartSpec {
    pub series: ChartKind,
    pub dataset: String,
    pub label_column: usize,
    pub value_column: usize,
    pub max_points: usize,
    pub height: f32,
    pub view: Option<TableView>,
}

impl ChartSpec {
    pub fn validate(&self) -> Result<(), String> {
        if self.dataset.is_empty()
            || self.dataset.len() > 256
            || self.label_column >= 64
            || self.value_column >= 64
            || !(1..=512).contains(&self.max_points)
            || !self.height.is_finite()
            || !(80.0..=1024.0).contains(&self.height)
        {
            return Err("Invalid chart dataset, column, point limit or height".into());
        }
        if let Some(view) = &self.view {
            view.validate()?;
        }
        Ok(())
    }
}
