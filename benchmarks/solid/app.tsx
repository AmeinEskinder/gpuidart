import { createSignal, For } from 'solid-js';
import { createStore } from 'solid-js/store';
import { render, useGpuixRequired, type StyleDesc } from '@gpuix/solid';
import { writeFileSync } from 'node:fs';

const output = process.argv[2];
if (!output) throw new Error('Expected output JSON path');
const ROWS = 100_000;
const WINDOW = 32;
const text: StyleDesc = { color: '#18181b', fontSize: 16, fontFamily: 'Segoe UI' };
const button: StyleDesc = { height: 32, flexShrink: 0, backgroundColor: '#18181b', borderRadius: 6, display: 'flex', alignItems: 'center', justifyContent: 'center', userSelect: 'none' };
const cell: StyleDesc = { ...text, width: 200, flexShrink: 0, paddingLeft: 8 };

function App() {
  const renderer = useGpuixRequired();
  const [rows, setRows] = createStore(Array.from({ length: ROWS }, (_, id) => ({ id: String(id), instrument: `Instrument ${id}`, price: (100 + id / 100).toFixed(2) })));
  const [start, setStart] = createSignal(0);
  let updates = 0;
  let cellsWritten = 0;
  let rowComponentsCreated = 0;
  let getListId: (() => number) | undefined;

  function edit(count: number) {
    updates++;
    cellsWritten += count;
    for (let row = 0; row < count; row++) setRows(row, 'price', `Tick ${String(updates).padStart(6, '0')}`);
  }
  function report() {
    writeFileSync(output, JSON.stringify({
      implementation: 'solid', rows: ROWS, updates, cells_written: cellsWritten,
      first_price: rows[0].price, row_components_created: rowComponentsCreated,
      mounted_window: { start: start(), count: Math.min(WINDOW, ROWS - start()) },
      scroll_offset: getListId === undefined ? null : renderer.getScrollOffset?.(getListId()),
      draw_overlay: renderer.getDebugFrameOverlayStats?.(),
      scope: 'GPUIX overlay last 1000 draws; p90/p99 are not p95',
    }, null, 2));
    process.exit(0);
  }
  return <div style={{ height: '100%', padding: 20, backgroundColor: '#ffffff', display: 'flex', flexDirection: 'column', gap: 12, fontSize: 16, lineHeight: 26 }}>
    <text style={{ ...text, height: 26, flexShrink: 0 }}>GPUI comparison · 100,000 records</text>
    <div style={button} onClick={() => edit(1)}><text style={{ ...text, color: '#fafafa' }}>Update one cell</text></div>
    <div style={button} onClick={() => edit(8)}><text style={{ ...text, color: '#fafafa' }}>Update eight visible cells</text></div>
    <div style={button} onClick={report}><text style={{ ...text, color: '#fafafa' }}>Save measurements</text></div>
    <div style={{ height: 320, flexShrink: 0, borderWidth: 1, borderColor: '#e4e4e7', borderRadius: 6, overflow: 'hidden' }}>
      <div style={{ height: 32, display: 'flex', flexDirection: 'row', alignItems: 'center', backgroundColor: '#f4f4f5' }}>
        <text style={{ ...cell, color: '#737373' }}>ID</text><text style={{ ...cell, color: '#737373' }}>Instrument</text><text style={{ ...cell, color: '#737373' }}>Price</text>
      </div>
      <virtual-list ref={(node) => { getListId = () => node.id; }} itemCount={ROWS} windowStart={start()} estimatedItemHeight={32} overdraw={32}
        onVisibleRange={(event) => setStart(Math.min(ROWS - WINDOW, Math.max(0, Math.floor(event.startIndex ?? 0) - 4)))}
        style={{ height: 286, lineHeight: 26 }}>
        <For each={rows.slice(start(), start() + WINDOW)}>{(row) => {
          rowComponentsCreated++;
          return <div style={{ width: '100%', height: 32, display: 'flex', flexDirection: 'row', alignItems: 'center', borderBottomWidth: 1, borderColor: '#eeeeee', backgroundColor: Number(row.id) % 2 === 0 ? '#ffffff' : '#fafafa' }}>
            <text style={cell}>{row.id}</text><text style={cell}>{row.instrument}</text><text style={cell}>{row.price}</text>
          </div>;
        }}</For>
      </virtual-list>
    </div>
  </div>;
}
render(() => <App />, { title: 'GPUI comparison · Solid', width: 860, height: 650, focus: false });
