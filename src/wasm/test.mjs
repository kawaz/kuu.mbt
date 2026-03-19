#!/usr/bin/env node
// Test script for kuu WASM bridge.
// Usage: node test.mjs

import { readFile } from "node:fs/promises";
import { strictEqual, deepStrictEqual } from "node:assert";

const wasmPath = new URL(
  "../../_build/wasm-gc/release/build/wasm/wasm.wasm",
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
  strictEqual(r.kind, "UnknownOption");
  strictEqual(r.tip, undefined); // no options to suggest
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
      { kind: "unknown_kind_xyz", name: "flag1" },
    ],
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "unknown opt kind: unknown_kind_xyz");
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

// Test 14: Non-object element in opts
{
  const r = test("Non-object element in opts", {
    opts: [
      { kind: "flag", name: "verbose" },
      "not-an-object",
    ],
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "each element in 'opts' must be an object");
}

// Test 15: opts is not an array
{
  const r = test("opts is not an array", {
    opts: "not-an-array",
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "'opts' must be an array");
}

// Test 16: opts is a number (not an array)
{
  const r = test("opts is a number", {
    opts: 42,
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "'opts' must be an array");
}

// Test 17: Flag with variations
{
  const r = test("Flag with variations", {
    opts: [
      {
        kind: "flag", name: "wall",
        variation_false: "no",
        variation_toggle: "toggle",
        variation_true: "force",
        variation_reset: "reset",
        variation_unset: "unset",
      },
    ],
    args: ["--force-wall"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.wall, true);
}

// Test 18: Flag variation_false (--no-wall)
{
  const r = test("Flag variation_false", {
    opts: [
      {
        kind: "flag", name: "wall", default: true,
        variation_false: "no",
      },
    ],
    args: ["--no-wall"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.wall, false);
}

// Test 19: String opt with variation_reset
{
  const r = test("String opt variation_reset", {
    opts: [
      {
        kind: "string", name: "color", default: "auto",
        variation_reset: "reset",
      },
    ],
    args: ["--color", "always", "--reset-color"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.color, "auto");
}

// Test 20: Count with variation_unset
{
  const r = test("Count variation_unset", {
    opts: [
      {
        kind: "count", name: "verbose", shorts: "v",
        variation_unset: "no",
      },
    ],
    args: ["-vvv", "--no-verbose"],
  });
  strictEqual(r.ok, true);
  // After unset, the value returns to default (0)
  // Note: get() returns Some(default) since parsing completed (parsed=true)
  strictEqual(r.values.verbose, 0);
}

// Test 21: string with implicit_value
{
  const r = test("String implicit_value", {
    opts: [
      { kind: "string", name: "color", default: "auto", implicit_value: "always" },
    ],
    args: ["--color"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.color, "always");
}

// Test 22: int with implicit_value
{
  const r = test("Int implicit_value", {
    opts: [
      { kind: "int", name: "verbosity", default: 0, implicit_value: 3 },
    ],
    args: ["--verbosity"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.verbosity, 3);
}

// Test 23: dashdash kind
{
  const r = test("Dashdash kind", {
    opts: [
      { kind: "flag", name: "verbose" },
      { kind: "dashdash" },
    ],
    args: ["--verbose", "--", "extra1", "extra2"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.verbose, true);
  deepStrictEqual(r.values["--"], ["extra1", "extra2"]);
}

// Test 24: require_cmd at top level
{
  const r = test("Require cmd top level", {
    opts: [
      { kind: "command", name: "sub1", opts: [] },
    ],
    require_cmd: true,
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error.includes("subcommand required"), true);
  strictEqual(r.kind, "MissingSubcommand");
}

// Test 25: require_cmd inside command
{
  const r = test("Require cmd inside command", {
    opts: [
      {
        kind: "command", name: "parent",
        require_cmd: true,
        opts: [
          { kind: "command", name: "child", opts: [] },
        ],
      },
    ],
    args: ["parent"],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error.includes("subcommand required"), true);
  strictEqual(r.kind, "MissingSubcommand");
}

// Test 26: exclusive constraint
{
  const r = test("Exclusive constraint", {
    opts: [
      { kind: "flag", name: "shared" },
      { kind: "flag", name: "static" },
    ],
    exclusive: [["shared", "static"]],
    args: ["--shared", "--static"],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error.includes("mutually exclusive"), true);
  strictEqual(r.kind, "ArgumentConflict");
}

// Test 27: required constraint
{
  const r = test("Required constraint", {
    opts: [
      { kind: "string", name: "filename", default: "" },
      { kind: "string", name: "output", default: "" },
    ],
    required: ["filename"],
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error.includes("required option missing"), true);
  strictEqual(r.kind, "MissingRequired");
}

// Test 28: command aliases
{
  const r = test("Command aliases", {
    opts: [
      {
        kind: "command", name: "checkout", aliases: ["co"],
        opts: [
          { kind: "positional", name: "branch" },
        ],
      },
    ],
    args: ["co", "main"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.command.name, "checkout");
  strictEqual(r.command.values.branch, "main");
}

// Test 29: serial kind
{
  const r = test("Serial kind", {
    opts: [
      { kind: "serial", opts: [
        { kind: "positional", name: "src" },
        { kind: "positional", name: "dst" },
      ]},
    ],
    args: ["a.txt", "b.txt"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.src, "a.txt");
  strictEqual(r.values.dst, "b.txt");
}

// Test 30: post filter trim
{
  const r = test("Post filter trim", {
    opts: [
      { kind: "string", name: "name", default: "", post: "trim" },
    ],
    args: ["--name", "  hello  "],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.name, "hello");
}

// Test 31: post filter non_empty
{
  const r = test("Post filter non_empty", {
    opts: [
      { kind: "string", name: "name", default: "fallback", post: "non_empty" },
    ],
    args: ["--name", ""],
  });
  strictEqual(r.ok, false);
  strictEqual(r.kind, "InvalidValue");
  // non_empty should reject empty strings
}

// Test 32: post filter in_range
{
  const r = test("Post filter in_range", {
    opts: [
      { kind: "int", name: "v", default: 0, post: { in_range: [0, 9] } },
    ],
    args: ["--v", "5"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.v, 5);
}

// Test 33: post filter in_range error
{
  const r = test("Post filter in_range error", {
    opts: [
      { kind: "int", name: "v", default: 0, post: { in_range: [0, 9] } },
    ],
    args: ["--v", "10"],
  });
  strictEqual(r.ok, false);
  strictEqual(r.kind, "InvalidValue");
}

// Test 34: float kind basic
{
  const r = test("Float kind basic", {
    opts: [
      { kind: "float", name: "rate", default: 1.0, description: "Rate" },
    ],
    args: ["--rate", "3.14"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.rate, 3.14);
}

// Test 35: float kind default
{
  const r = test("Float kind default", {
    opts: [
      { kind: "float", name: "rate", default: 2.5 },
    ],
    args: [],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.rate, 2.5);
}

// Test 36: float kind with float_in_range post filter
{
  const r = test("Float kind with float_in_range post", {
    opts: [
      { kind: "float", name: "rate", default: 0.0, post: { float_in_range: [0.0, 1.0] } },
    ],
    args: ["--rate", "0.5"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.rate, 0.5);
}

// Test 37: float kind with float_in_range error
{
  const r = test("Float kind float_in_range error", {
    opts: [
      { kind: "float", name: "rate", default: 0.0, post: { float_in_range: [0.0, 1.0] } },
    ],
    args: ["--rate", "1.5"],
  });
  strictEqual(r.ok, false);
  strictEqual(r.kind, "InvalidValue");
}

// Test 38: append_float kind
{
  const r = test("Append float kind", {
    opts: [
      { kind: "append_float", name: "score", description: "Scores" },
    ],
    args: ["--score", "1.5", "--score", "2.7"],
  });
  strictEqual(r.ok, true);
  deepStrictEqual(r.values.score, [1.5, 2.7]);
}

// Test 39: append_float kind empty
{
  const r = test("Append float kind empty", {
    opts: [
      { kind: "append_float", name: "score" },
    ],
    args: [],
  });
  strictEqual(r.ok, true);
  deepStrictEqual(r.values.score, []);
}

// Test 40: float kind invalid value
{
  const r = test("Float kind invalid value", {
    opts: [
      { kind: "float", name: "rate", default: 0.0 },
    ],
    args: ["--rate", "abc"],
  });
  strictEqual(r.ok, false);
  strictEqual(r.kind, "InvalidValue");
}

// Test 41: float kind with implicit_value
{
  const r = test("Float implicit_value", {
    opts: [
      { kind: "float", name: "threshold", default: 0.0, implicit_value: 0.5 },
    ],
    args: ["--threshold"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.threshold, 0.5);
}

// Test 42: boolean kind basic
{
  const r = test("Boolean kind basic", {
    opts: [
      { kind: "boolean", name: "debug", description: "Debug mode" },
    ],
    args: ["--debug", "true"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.debug, true);
}

// Test 43: boolean kind false
{
  const r = test("Boolean kind false", {
    opts: [
      { kind: "boolean", name: "debug" },
    ],
    args: ["--debug", "off"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.debug, false);
}

// Test 44: boolean kind default
{
  const r = test("Boolean kind default", {
    opts: [
      { kind: "boolean", name: "debug" },
    ],
    args: [],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.debug, false);
}

// Test 45: boolean kind invalid
{
  const r = test("Boolean kind invalid", {
    opts: [
      { kind: "boolean", name: "debug" },
    ],
    args: ["--debug", "maybe"],
  });
  strictEqual(r.ok, false);
  strictEqual(r.kind, "InvalidValue");
}

// === env (environment variables) tests ===

// Test 46: env sets value when CLI arg not provided
{
  const r = test("Env sets value", {
    opts: [
      { kind: "string", name: "host", default: "localhost", env: "HOST" },
    ],
    args: [],
    env: { HOST: "env-host.example.com" },
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.host, "env-host.example.com");
}

// Test 47: CLI arg overrides env
{
  const r = test("CLI overrides env", {
    opts: [
      { kind: "string", name: "host", default: "localhost", env: "HOST" },
    ],
    args: ["--host", "cli-host"],
    env: { HOST: "env-host" },
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.host, "cli-host");
}

// Test 48: env not provided uses default
{
  const r = test("Env absent uses default", {
    opts: [
      { kind: "string", name: "host", default: "localhost", env: "HOST" },
    ],
    args: [],
    env: {},
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.host, "localhost");
}

// Test 49: env with flag (true/1)
{
  const r = test("Env flag true", {
    opts: [
      { kind: "flag", name: "verbose", env: "VERBOSE" },
    ],
    args: [],
    env: { VERBOSE: "1" },
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.verbose, true);
}

// Test 50: env without env field in schema (no effect)
{
  const r = test("Env field absent in schema", {
    opts: [
      { kind: "string", name: "host", default: "localhost" },
    ],
    args: [],
    env: { HOST: "should-not-apply" },
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.host, "localhost");
}

// === at_least_one tests ===

// Test 51: at_least_one passes when one is set
{
  const r = test("At least one passes", {
    opts: [
      { kind: "flag", name: "json" },
      { kind: "flag", name: "csv" },
    ],
    at_least_one: [["json", "csv"]],
    args: ["--json"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.json, true);
}

// Test 52: at_least_one error when none set
{
  const r = test("At least one error", {
    opts: [
      { kind: "flag", name: "json" },
      { kind: "flag", name: "csv" },
    ],
    at_least_one: [["json", "csv"]],
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error.includes("at least one required"), true);
  strictEqual(r.kind, "AtLeastOneRequired");
}

// Test 53: at_least_one passes when all set
{
  const r = test("At least one all set", {
    opts: [
      { kind: "flag", name: "json" },
      { kind: "flag", name: "csv" },
    ],
    at_least_one: [["json", "csv"]],
    args: ["--json", "--csv"],
  });
  strictEqual(r.ok, true);
}

// === requires tests ===

// Test 54: requires passes when both set
{
  const r = test("Requires passes", {
    opts: [
      { kind: "string", name: "key_file", default: "" },
      { kind: "string", name: "output", default: "" },
    ],
    requires: [{ source: "key_file", target: "output" }],
    args: ["--key_file", "id_rsa", "--output", "result.txt"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.key_file, "id_rsa");
  strictEqual(r.values.output, "result.txt");
}

// Test 55: requires error when source set but target not
{
  const r = test("Requires error", {
    opts: [
      { kind: "string", name: "key_file", default: "" },
      { kind: "string", name: "output", default: "" },
    ],
    requires: [{ source: "key_file", target: "output" }],
    args: ["--key_file", "id_rsa"],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error.includes("requires"), true);
  strictEqual(r.kind, "DependencyMissing");
}

// Test 56: requires passes when source not set
{
  const r = test("Requires passes source unset", {
    opts: [
      { kind: "string", name: "key_file", default: "" },
      { kind: "string", name: "output", default: "" },
    ],
    requires: [{ source: "key_file", target: "output" }],
    args: [],
  });
  strictEqual(r.ok, true);
}

// Test 57: requires with custom message
{
  const r = test("Requires custom msg", {
    opts: [
      { kind: "string", name: "key_file", default: "" },
      { kind: "string", name: "output", default: "" },
    ],
    requires: [{ source: "key_file", target: "output", msg: "--key_file requires --output to be specified" }],
    args: ["--key_file", "id_rsa"],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "--key_file requires --output to be specified");
  strictEqual(r.kind, "DependencyMissing");
}

// === deprecated tests ===

// Test 58: deprecated records warning when used
{
  const r = test("Deprecated records warning", {
    opts: [
      { kind: "string", name: "output", default: "" },
      { kind: "deprecated", name: "--out", target: "output", msg: "Use --output instead" },
    ],
    args: ["--out", "file.txt"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.output, "file.txt");
  strictEqual(r.deprecated_warnings.length, 1);
  strictEqual(r.deprecated_warnings[0].name, "--out");
  strictEqual(r.deprecated_warnings[0].msg, "Use --output instead");
}

// Test 59: deprecated not used - no warnings
{
  const r = test("Deprecated not used", {
    opts: [
      { kind: "string", name: "output", default: "" },
      { kind: "deprecated", name: "--out", target: "output", msg: "Use --output instead" },
    ],
    args: ["--output", "file.txt"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.output, "file.txt");
  strictEqual(r.deprecated_warnings, undefined);
}

// Test 60: deprecated target not found error
{
  const r = test("Deprecated target not found", {
    opts: [
      { kind: "deprecated", name: "--old", target: "nonexistent", msg: "gone" },
    ],
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.error, "deprecated target not found: nonexistent");
}

// Test 61: deprecated with flag target
{
  const r = test("Deprecated flag", {
    opts: [
      { kind: "flag", name: "verbose" },
      { kind: "deprecated", name: "--verb", target: "verbose", msg: "Use --verbose" },
    ],
    args: ["--verb"],
  });
  strictEqual(r.ok, true);
  strictEqual(r.values.verbose, true);
  strictEqual(r.deprecated_warnings.length, 1);
  strictEqual(r.deprecated_warnings[0].name, "--verb");
}

// === error tip/kind tests ===

// Test 62: tip field with typo suggestion
{
  const r = test("Error tip with typo", {
    opts: [
      { kind: "int", name: "port", default: 8080 },
    ],
    args: ["--prot"],
  });
  strictEqual(r.ok, false);
  strictEqual(r.kind, "UnknownOption");
  strictEqual(r.tip, "--port");
}

// Test 63: schema validation errors have no kind/tip
{
  const r = test("Schema error no kind", {
    opts: [
      { kind: "flag" },
    ],
    args: [],
  });
  strictEqual(r.ok, false);
  strictEqual(r.kind, undefined);
  strictEqual(r.tip, undefined);
}

console.log("\n--- All tests passed ---");
