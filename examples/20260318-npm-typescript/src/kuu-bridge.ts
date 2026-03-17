import { readFile } from "node:fs/promises";

// --- Types ---

export type OptKind =
  | "flag"
  | "string"
  | "int"
  | "count"
  | "positional"
  | "rest"
  | "dashdash"
  | "append_string"
  | "append_int"
  | "serial"
  | "command";

export interface KuuOpt {
  kind: OptKind;
  name?: string;
  shorts?: string;
  description?: string;
  default?: unknown;
  choices?: readonly string[];
  global?: boolean;
  env?: string;
  aliases?: readonly string[];
  implicit_value?: unknown;
  required?: string[];
  exclusive?: string[][];
  require_cmd?: boolean;
  opts?: KuuOpt[];
  post?: Record<string, unknown>;
  variation_false?: string;
  variation_toggle?: string;
  variation_true?: string;
  variation_reset?: string;
  variation_unset?: string;
}

export interface KuuSchema {
  version?: number;
  description?: string;
  opts: KuuOpt[];
  exclusive?: string[][];
  required?: string[];
  require_cmd?: boolean;
}

export interface KuuCommandResult {
  name: string;
  values: Record<string, unknown>;
  command?: KuuCommandResult;
}

export interface KuuSuccessResult {
  ok: true;
  values: Record<string, unknown>;
  command?: KuuCommandResult;
}

export interface KuuHelpResult {
  ok: false;
  help_requested: true;
  help: string;
}

export interface KuuErrorResult {
  ok: false;
  error: string;
  help?: string;
}

export type KuuResult = KuuSuccessResult | KuuHelpResult | KuuErrorResult;

// --- Bridge ---

export type KuuParseFn = (schema: KuuSchema, args: string[]) => KuuResult;

export async function loadKuu(wasmPath?: string): Promise<KuuParseFn> {
  const resolvedPath =
    wasmPath ??
    process.env.WASM_PATH ??
    new URL(
      "../../_build/wasm-gc/release/build/src/wasm/wasm.wasm",
      import.meta.url,
    ).pathname;

  const wasmBytes = await readFile(resolvedPath);
  const { instance } = await WebAssembly.instantiate(
    wasmBytes,
    {},
    // @ts-expect-error -- WASM-GC builtins not yet in TS types
    { builtins: ["js-string"], importedStringConstants: "_" },
  );

  const kuu_parse = instance.exports.kuu_parse as (json: string) => string;

  return (schema: KuuSchema, args: string[]): KuuResult => {
    const input = { ...schema, args };
    return JSON.parse(kuu_parse(JSON.stringify(input)));
  };
}
