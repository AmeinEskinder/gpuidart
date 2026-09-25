use gpui_kit::base::ScrollbarHandle;
use gpui_kit::component::{
    ActiveTheme, StyledExt,
    button::{Button, ButtonVariants},
    table::{Column, DataTable, TableDelegate, TableState},
};
use gpui_kit::*;
use serde_json::json;
use std::{cell::Cell, rc::Rc};

const ROWS: usize = 100_000;

struct Rows {
    data: Vec<[String; 3]>,
    cells_built: Rc<Cell<u64>>,
}

impl TableDelegate for Rows {
    fn columns_count(&self, _: &App) -> usize {
        3
    }
    fn rows_count(&self, _: &App) -> usize {
        self.data.len()
    }
    fn column(&self, index: usize, _: &App) -> Column {
        Column::new(
            format!("column-{index}"),
            ["ID", "Instrument", "Price"][index],
        )
        .width(px(200.))
    }
    fn render_td(
        &mut self,
        row: usize,
        col: usize,
        _: &mut Window,
        _: &mut Context<TableState<Self>>,
    ) -> impl IntoElement {
        self.cells_built.set(self.cells_built.get() + 1);
        div().child(self.data[row][col].clone())
    }
}

struct Benchmark {
    table: Entity<TableState<Rows>>,
    updates: u64,
    cells_written: u64,
    cells_built: Rc<Cell<u64>>,
    output: String,
}

impl Benchmark {
    fn edit(&mut self, count: usize, cx: &mut Context<Self>) {
        self.updates += 1;
        self.cells_written += count as u64;
        let value = format!("Tick {:06}", self.updates);
        self.table.update(cx, |table, cx| {
            for row in 0..count {
                table.delegate_mut().data[row][2] = value.clone();
            }
            cx.notify();
        });
    }

    fn report(&self, window: &mut Window, cx: &mut Context<Self>) {
        let frames = window.frame_duration_snapshot();
        let input = window.input_latency_snapshot();
        macro_rules! histogram {
            ($h:expr) => {{ let h = $h; json!({"samples": h.len(), "p50_us": h.value_at_quantile(0.5) as f64 / 1000., "p95_us": h.value_at_quantile(0.95) as f64 / 1000., "p99_us": h.value_at_quantile(0.99) as f64 / 1000.}) }};
        }
        let table = self.table.read(cx);
        let report = json!({
            "implementation": "rust", "rows": ROWS, "updates": self.updates,
            "cells_written": self.cells_written, "cells_built": self.cells_built.get(),
            "first_price": table.delegate().data[0][2],
            "visible_rows": table.visible_range().rows(),
            "scroll_y": f32::from(table.vertical_scroll_handle.offset().y),
            "draw": histogram!(frames.draw_duration_histogram),
            "dirty_to_present_submit": histogram!(frames.dirty_to_present_histogram),
            "present_interval": histogram!(frames.present_interval_histogram),
            "input_to_frame": histogram!(input.latency_histogram),
            "scope": "cumulative since window creation; includes startup and warmup"
        });
        std::fs::write(&self.output, serde_json::to_vec_pretty(&report).unwrap()).unwrap();
        cx.quit();
    }
}

impl Render for Benchmark {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .id("comparison")
            .size_full()
            .p_5()
            .bg(cx.theme().background)
            .text_color(cx.theme().foreground)
            .child(
                div()
                    .v_flex()
                    .gap_3()
                    .w_full()
                    .child(div().child("GPUI comparison · 100,000 records"))
                    .child(
                        Button::new("cell")
                            .primary()
                            .label("Update one cell")
                            .on_click(cx.listener(|view, _, _, cx| view.edit(1, cx))),
                    )
                    .child(
                        Button::new("burst")
                            .primary()
                            .label("Update eight visible cells")
                            .on_click(cx.listener(|view, _, _, cx| view.edit(8, cx))),
                    )
                    .child(
                        Button::new("report")
                            .primary()
                            .label("Save measurements")
                            .on_click(cx.listener(|view, _, window, cx| view.report(window, cx))),
                    )
                    .child(
                        div()
                            .w_full()
                            .h(px(320.))
                            .child(DataTable::new(&self.table).stripe(true).bordered(true)),
                    ),
            )
    }
}

fn main() {
    let output = std::env::args().nth(1).expect("output JSON path");
    gpui_kit::application()
        .with_assets(gpui_kit::assets::Assets)
        .run(move |cx| {
            gpui_kit::init(cx);
            cx.open_window(
                WindowOptions {
                    window_bounds: Some(WindowBounds::centered(size(px(860.), px(650.)), cx)),
                    titlebar: Some(TitlebarOptions {
                        title: Some("GPUI comparison · Rust".into()),
                        ..Default::default()
                    }),
                    ..Default::default()
                },
                |window, cx| {
                    let cells_built = Rc::new(Cell::new(0));
                    let table = cx.new(|cx| {
                        TableState::new(
                            Rows {
                                data: (0..ROWS)
                                    .map(|i| {
                                        [
                                            i.to_string(),
                                            format!("Instrument {i}"),
                                            format!("{:.2}", 100. + i as f64 / 100.),
                                        ]
                                    })
                                    .collect(),
                                cells_built: cells_built.clone(),
                            },
                            window,
                            cx,
                        )
                    });
                    let view = cx.new(|_| Benchmark {
                        table,
                        updates: 0,
                        cells_written: 0,
                        cells_built,
                        output,
                    });
                    cx.new(|cx| gpui_kit::component::Root::new(view, window, cx))
                },
            )
            .expect("open comparison window");
            cx.on_window_closed(|cx, _| {
                if cx.windows().is_empty() {
                    cx.quit();
                }
            })
            .detach();
        });
}
