import { View, div, uniform_list } from 'gpui-kit';
import { v_flex, h_flex } from 'gpui-base';
import { Button } from 'gpui-component';

export default class Comparison extends View {
  init() {
    this.rows = Array.from({ length: 100000 }, (_, id) => ({ ID: String(id), Instrument: `Instrument ${id}`, Price: (100 + id / 100).toFixed(2) }));
    this.updates = 0;
    this.cellsWritten = 0;
    this.cellBuilds = 0;
    this.visibleRange = [0, 0];
    this.viewBuilds = 0;
  }
  edit(count, cx) {
    this.updates++;
    this.cellsWritten += count;
    for (let row = 0; row < count; row++) this.rows[row].Price = `Tick ${String(this.updates).padStart(6, '0')}`;
    cx.notify();
  }
  render(cx) {
    this.viewBuilds++;
    return v_flex().size_full().p_5().gap_3()
      .bg(cx.theme().colors.background).text_color(cx.theme().colors.foreground)
      .child(div().child('GPUI comparison · 100,000 records'))
      .child(new Button('cell').primary().label('Update one cell').on_click((_, cx) => this.edit(1, cx)))
      .child(new Button('burst').primary().label('Update eight visible cells').on_click((_, cx) => this.edit(8, cx)))
      .child(new Button('report').primary().label('Save measurements').on_click(() => {
        console.log('BENCHMARK_RESULT ' + JSON.stringify({ implementation: 'shell', rows: this.rows.length, updates: this.updates, cells_written: this.cellsWritten, first_price: this.rows[0].Price, view_builds: this.viewBuilds, cell_builds: this.cellBuilds, visible_range: this.visibleRange }));
      }))
      .child(v_flex().w_full().h(320).border_1().border_color('#e4e4e7').rounded_md().overflow_hidden()
        .child(h_flex().h(32).flex_shrink_0().items_center().bg('#fafafa')
          .children(['ID', 'Instrument', 'Price'].map(value => div().w(200).flex_shrink_0().px(8).text_color('#737373').child(value))))
        .child(uniform_list('rows', this.rows.length, index => String(index), range => {
          this.visibleRange = [range.start, range.end];
          const result = [];
          for (let index = range.start; index < range.end; index++) {
            const row = this.rows[index];
            this.cellBuilds += 3;
            result.push(h_flex().w_full().h(32).items_center().border_b_1().border_color('#eeeeee').bg(index % 2 ? '#fafafa' : '#ffffff')
              .children([row.ID, row.Instrument, row.Price].map(value => div().w(200).flex_shrink_0().px(8).child(value))));
          }
          return result;
        }).h(286)));
  }
}
