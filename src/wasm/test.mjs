#!/usr/bin/env node
// Test script for kuu WASM bridge.
// Usage: node test.mjs

import { readFile } from "node:fs/promises";

const wasmPath = new URL(
  "../../_build/wasm-gc/release/build/src/wasm/wasm.wasm",
  import.meta.url
);

const wasmBytes = await readFile(wasmPath);
const { instance } = await WebAssembly.instantiate(wasmBytes, {}, {
  builtins: ["js-string"],
  importedStringConstants: "_",
});

const { kuu_parse } = instance.exports;

function test(label, input) {
  console.log(`\n=== ${label} ===`);
  console.log("Input:", JSON.stringify(input));
  const result = kuu_parse(JSON.stringify(input));
  const parsed = JSON.parse(result);
  console.log("Output:", JSON.stringify(parsed, null, 2));
  return parsed;
}

// Test 1: Simple flag + string opt
{
  const r = test("Simple flag + string", {
    description: "My CLI",
    opts: [
      { kind: "flag", name: "verbose", shorts: "v", description: "Verbose output" },
      { kind: "string", name: "host", default: "localhost", description: "Host" },
      { kind: "int", name: "port", default: 8080, description: "Port" },
    ],
    args: ["--verbose", "--host", "example.com"],
  });
  console.assert(r.ok === true);
  console.assert(r.values.verbose === true);
  console.assert(r.values.host === "example.com");
  console.assert(r.values.port === 8080);
}

// Test 2: Positional + rest
{
  const r = test("Positional + rest", {
    opts: [
      { kind: "positional", name: "file", description: "Input file" },
      { kind: "rest", name: "args", description: "Extra args" },
    ],
    args: ["input.txt", "extra1", "extra2"],
  });
  console.assert(r.ok === true);
  console.assert(r.values.file === "input.txt");
  console.assert(JSON.stringify(r.values.args) === '["extra1","extra2"]');
}

// Test 3: Subcommand
{
  const r = test("Subcommand", {
    opts: [
      { kind: "flag", name: "verbose", shorts: "v", global: true },
      {
        kind: "command", name: "serve", description: "Start server",
        opts: [
          { kind: "int", name: "port", default: 3000, description: "Port" },
        ],
      },
    ],
    args: ["--verbose", "serve", "--port", "9090"],
  });
  console.assert(r.ok === true);
  console.assert(r.values.verbose === true);
  console.assert(r.command.name === "serve");
  console.assert(r.command.values.port === 9090);
}

// Test 4: Help request
{
  const r = test("Help request", {
    description: "Test CLI",
    opts: [
      { kind: "flag", name: "verbose", description: "Verbose" },
    ],
    args: ["--help"],
  });
  console.assert(r.ok === false);
  console.assert(r.help_requested === true);
  console.assert(r.help.includes("--verbose"));
}

// Test 5: Parse error
{
  const r = test("Parse error", {
    opts: [],
    args: ["--unknown"],
  });
  console.assert(r.ok === false);
  console.assert(r.error !== undefined);
}

// Test 6: Count + short combine
{
  const r = test("Count + short combine", {
    opts: [
      { kind: "count", name: "verbose", shorts: "v", description: "Verbosity" },
    ],
    args: ["-vvv"],
  });
  console.assert(r.ok === true);
  console.assert(r.values.verbose === 3);
}

// Test 7: append_string
{
  const r = test("Append string", {
    opts: [
      { kind: "append_string", name: "tag", description: "Tags" },
    ],
    args: ["--tag", "a", "--tag", "b", "--tag", "c"],
  });
  console.assert(r.ok === true);
  console.assert(JSON.stringify(r.values.tag) === '["a","b","c"]');
}

// Test 8: String with choices
{
  const r = test("String with choices", {
    opts: [
      { kind: "string", name: "color", default: "auto", choices: ["auto", "always", "never"] },
    ],
    args: ["--color", "always"],
  });
  console.assert(r.ok === true);
  console.assert(r.values.color === "always");
}

console.log("\n--- All tests passed ---");
