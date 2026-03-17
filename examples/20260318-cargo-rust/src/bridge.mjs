#!/usr/bin/env node
// kuu WASM bridge for Rust integration.
// Reads JSON from stdin, calls kuu_parse, writes JSON to stdout.

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Resolve WASM path relative to workspace root (../../../ from examples/20260318-cargo-rust/src/)
const wasmPath = resolve(
  __dirname,
  "../../../_build/wasm-gc/release/build/src/wasm/wasm.wasm"
);

const wasmBytes = await readFile(wasmPath);
const { instance } = await WebAssembly.instantiate(wasmBytes, {}, {
  builtins: ["js-string"],
  importedStringConstants: "_",
});

const { kuu_parse } = instance.exports;

// Read all stdin
const chunks = [];
for await (const chunk of process.stdin) {
  chunks.push(chunk);
}
const input = Buffer.concat(chunks).toString("utf-8");

const result = kuu_parse(input);
process.stdout.write(result + "\n");
