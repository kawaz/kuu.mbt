#!/usr/bin/env bun
// kuu WASM bridge — reads JSON schema+args from stdin, writes parse result to stdout.
import { readFile } from "node:fs/promises";

const wasmPath = new URL("./kuu.wasm", import.meta.url);
const wasmBytes = await readFile(wasmPath);
const { instance } = await WebAssembly.instantiate(wasmBytes, {}, {
  builtins: ["js-string"],
  importedStringConstants: "_",
});
const { kuu_parse } = instance.exports;

// Read all of stdin
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const input = Buffer.concat(chunks).toString("utf-8");

const result = kuu_parse(input);
process.stdout.write(result + "\n");
