// Run a WASI command module (built by wasm/build_*.sh) under node, the way
// a browser runtime would: the current directory is preopened as "." and,
// with --share <dir>, <dir> as /share (where nextpnr's EXTERNAL_CHIPDB_ROOT
// points).
//   node wasm/run_wasi.mjs [--share <dir>] <module.wasm> <args...>
import { readFile } from "node:fs/promises";
import { WASI } from "node:wasi";
import process from "node:process";

const argv = process.argv.slice(2);
const preopens = { ".": process.cwd() };
if (argv[0] === "--share") { preopens["/share"] = argv[1]; argv.splice(0, 2); }
const [mod, ...args] = argv;
const wasi = new WASI({ version: "preview1", args: [mod, ...args], env: {}, preopens, returnOnExit: true });
const t0 = Date.now();
const instance = await WebAssembly.instantiate(await WebAssembly.compile(await readFile(mod)), wasi.getImportObject());
const code = wasi.start(instance);
const mem = instance.exports.memory.buffer.byteLength;
process.stderr.write(`[run_wasi] exit ${code}, ${(Date.now() - t0) / 1000} s, memory ${(mem / 2 ** 20).toFixed(0)} MiB\n`);
process.exit(code);
