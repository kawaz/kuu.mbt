// kuu WASM bridge — stdin から JSON を受け取り、kuu_parse の結果を stdout に出力する
// Python 等の非 V8 言語から kuu WASM bridge を利用するための薄いブリッジ

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const wasmPath = resolve(
  __dirname,
  "../../../_build/wasm-gc/release/build/src/wasm/wasm.wasm"
);

async function main() {
  // stdin から JSON を読み取る
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  const inputJson = Buffer.concat(chunks).toString("utf-8");

  // WASM をロード
  let wasmBytes;
  try {
    wasmBytes = await readFile(wasmPath);
  } catch (e) {
    if (e.code === "ENOENT") {
      process.stderr.write(`WASM module not found: ${wasmPath}\nRun 'just build-wasm' to build the WASM module first.\n`);
      process.exit(1);
    }
    throw e;
  }

  const { instance } = await WebAssembly.instantiate(wasmBytes, {}, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });

  const resultJson = instance.exports.kuu_parse(inputJson);
  process.stdout.write(resultJson);
}

main().catch((e) => {
  process.stderr.write(e.message + "\n");
  process.exit(1);
});
