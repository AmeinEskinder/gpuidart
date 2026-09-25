import solidPlugin from '@gpuix/solid/bun-plugin';
import { copyFileSync } from 'node:fs';

const result = await Bun.build({
  entrypoints: ['./main.ts'], target: 'bun',
  compile: { outfile: './dist/gpui-solid-comparison.exe' },
  plugins: [solidPlugin], minify: true,
});
if (!result.success) throw new AggregateError(result.logs, 'Solid benchmark build failed');
copyFileSync('./node_modules/@gpuix/native-win32-x64-msvc/gpuix-native.win32-x64-msvc.node', './dist/gpuix-native.win32-x64-msvc.node');
