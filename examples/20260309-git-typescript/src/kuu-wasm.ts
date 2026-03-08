// kuu WASM bridge ローダー
// kuu_parse 関数を WASM から読み込み、TypeScript から利用可能にする

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// --- 入力スキーマ型 ---

export interface KuuOpt {
  kind:
    | "flag"
    | "string"
    | "int"
    | "count"
    | "append_string"
    | "append_int"
    | "positional"
    | "rest"
    | "command";
  name: string;
  description?: string;
  shorts?: string;
  global?: boolean;
  hidden?: boolean;
  aliases?: string[];
  default?: boolean | string | number;
  choices?: string[];
  opts?: KuuOpt[]; // command のネスト用
}

export interface KuuInput {
  version?: number;
  description?: string;
  opts: KuuOpt[];
  args: string[];
}

// --- 出力型 ---

export interface KuuCommandResult {
  name: string;
  values: Record<string, unknown>;
  command?: KuuCommandResult;
}

export interface KuuSuccess {
  ok: true;
  values: Record<string, unknown>;
  command?: KuuCommandResult;
}

export interface KuuError {
  ok: false;
  error?: string;
  help_requested?: boolean;
  help?: string;
}

export type KuuResult = KuuSuccess | KuuError;

// --- WASM ローダー ---

/**
 * kuu WASM モジュールをロードし、パース関数を返す。
 * Node.js v25+ の WebAssembly.instantiate で js-string builtins を使用。
 */
export async function loadKuu(): Promise<(input: KuuInput) => KuuResult> {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  const wasmPath = resolve(
    __dirname,
    "../../../_build/wasm-gc/release/build/src/wasm/wasm.wasm"
  );

  let wasmBytes: Buffer;
  try {
    wasmBytes = await readFile(wasmPath);
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === 'ENOENT') {
      throw new Error(
        `WASM module not found: ${wasmPath}\n` +
        `Run 'just build-wasm' to build the WASM module first.`
      );
    }
    throw e;
  }

  // Node.js v25 の js-string builtins を使用して WASM をインスタンス化
  const { instance } = await WebAssembly.instantiate(wasmBytes, {}, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  } as any);

  const exports = instance.exports as {
    kuu_parse: (input: string) => string;
  };

  return (input: KuuInput): KuuResult => {
    const inputJson = JSON.stringify({
      version: input.version ?? 1,
      ...input,
    });
    const resultJson = exports.kuu_parse(inputJson);
    return JSON.parse(resultJson) as KuuResult;
  };
}
