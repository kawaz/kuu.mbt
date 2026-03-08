#!/usr/bin/env node
// Test script for kuu WASM bridge.
// Usage: node test.mjs

import { readFile } from "node:fs/promises";
import { strictEqual, deepStrictEqual } from "node:assert";

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
  strictEqual(r.ok, true);
  strictEqual(r.values.verbose, true);
  strictEqual(r.values.host, "example.com");
  strictEqual(r.values.port, 8080);
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
  strictEqual(r.ok, true);
  strictEqual(r.values.file, "input.txt");
  deepStrictEqual(r.values.args, ["extra1", "extra2"]);
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
  strictEqual(r.ok, true);
  strictEqual(r.values.verbose, true);
  strictEqual(r.command.name, "serve");
  strictEqual(r.command.values.port, 9090);
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
  strictEqual(r.ok, false);
  strictEqual(r.help_requested, true);
  strictEqual(r.help.includes("--verbose"), true);
}

// Test 5: Parse error
{
  const r = test("Parse error", {
    opts: [],
    args: ["--unknown"],
  });
  strictEqual(r.ok, false);
  strictEqual(typeof r.error, "string");
}

// Test 6: Count + short combine
{
  const r = test("Count + short combine", {
    opts: [
      { kind: "count", name: "verbose", shorts: "v", description: "Verbosity" },
    ],
    args: ["-vvv"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.verbose, 3);
}

// Test 7: append_string
{
  const r = test("Append string", {
    opts: [
      { kind: "append_string", name: "tag", description: "Tags" },
    ],
    args: ["--tag", "a", "--tag", "b", "--tag", "c"],
  });
  strictEqual(r.ok, true);
  deepStrictEqual(r.values.tag, ["a", "b", "c"]);
}

// Test 8: String with choices
{
  const r = test("String with choices", {
    opts: [
      { kind: "string", name: "color", default: "auto", choices: ["auto", "always", "never"] },
    ],
    args: ["--color", "always"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.color, "always");
}

// Test 9: Explicit version 1 (should succeed)
{
  const r = test("Version 1 explicit", {
    version: 1,
    opts: [
      { kind: "flag", name: "verbose", description: "Verbose" },
    ],
    args: ["--verbose"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.verbose, true);
}

// Test 10: Unsupported version
{
  const r = test("Unsupported version", {
    version: 2,
    opts: [],
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "unsupported schema version: 2");
}

// Test 11: Unknown opt kind
{
  const r = test("Unknown opt kind", {
    opts: [
      { kind: "boolean", name: "flag1" },
    ],
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "unknown opt kind: boolean");
}

// Test 12: Missing name in opt
{
  const r = test("Missing name in opt", {
    opts: [
      { kind: "flag" },
    ],
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "opt definition missing 'name'");
}

// Test 13: Non-string in args
{
  const r = test("Non-string in args", {
    opts: [],
    args: ["--verbose", 42],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "args must be an array of strings");
}

console.log("\n--- All tests passed ---");
