import { dirname, join } from 'node:path';

process.env.NAPI_RS_NATIVE_LIBRARY_PATH = join(dirname(process.execPath), 'gpuix-native.win32-x64-msvc.node');
await import('./app');
