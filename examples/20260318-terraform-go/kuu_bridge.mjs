#!/usr/bin/env node
// kuu WASM bridge for Go integration.
// Reads JSON schema from stdin, calls kuu_parse, writes JSON result to stdout.
// Protocol: one JSON object per line (NDJSON).

import { readFile } from "node:fs/promises";
import { createInterface } from "node:readline";

const wasmPath = new URL(
  "../../../main/_build/wasm-gc/release/build/src/wasm/wasm.wasm",
  import.meta.url
);

const wasmBytes = await readFile(wasmPath);
const { instance } = await WebAssembly.instantiate(wasmBytes, {}, {
  builtins: ["js-string"],
  importedStringConstants: "_",
});

const { kuu_parse } = instance.exports;

process.on('SIGTERM', () => process.exit(0));

const rl = createInterface({ input: process.stdin });

for await (const line of rl) {
  if (!line.trim()) continue;
  try {
    const result = kuu_parse(line);
    if (typeof result !== "string") {
      process.stdout.write(JSON.stringify({ ok: false, error: "kuu_parse returned non-string: " + typeof result }) + "\n");
      continue;
    }
    process.stdout.write(result + "\n");
  } catch (err) {
    process.stdout.write(JSON.stringify({ ok: false, error: err.message }) + "\n");
  }
}
