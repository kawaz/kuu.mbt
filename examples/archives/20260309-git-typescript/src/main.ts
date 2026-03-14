// mygit — kuu WASM bridge を使った git CLI 引数パーサのデモ
// 実際の git 操作は行わず、パース結果を整形表示する

import { loadKuu, type KuuCommandResult } from "./kuu-wasm.ts";
import { opts, description } from "./git-schema.ts";

/**
 * コマンド結果を再帰的に整形表示する
 */
function formatCommand(cmd: KuuCommandResult, indent = ""): string {
  const lines: string[] = [];
  lines.push(`${indent}command: ${cmd.name}`);

  for (const [key, value] of Object.entries(cmd.values)) {
    // デフォルト値（false, 0, 空文字列, 空配列）は表示しない
    if (value === false || value === 0 || value === "" || value === null) continue;
    if (Array.isArray(value) && value.length === 0) continue;

    lines.push(`${indent}  ${key}: ${formatValue(value)}`);
  }

  if (cmd.command) {
    lines.push(formatCommand(cmd.command, indent + "  "));
  }

  return lines.join("\n");
}

/**
 * 値を表示用にフォーマットする
 */
function formatValue(value: unknown): string {
  if (Array.isArray(value)) {
    return value.map(String).join(", ");
  }
  return String(value);
}

// グローバルオプションのデフォルト値マップを構築
const globalDefaults = new Map<string, unknown>();
for (const opt of opts) {
  if (opt.kind !== "command") {
    globalDefaults.set(opt.name, opt.default ?? getKindDefault(opt.kind));
  }
}

function getKindDefault(kind: string): unknown {
  switch (kind) {
    case "flag": return false;
    case "count": return 0;
    case "string": return "";
    case "int": return 0;
    case "append_string":
    case "append_int": return [];
    default: return null;
  }
}

async function main() {
  try {
    const args = process.argv.slice(2);

    // WASM をロード
    const kuuParse = await loadKuu();

    // パース実行
    const result = kuuParse({
      version: 1,
      description,
      opts,
      args,
    });

    if (result.ok) {
      // 成功: パース結果を表示
      const lines: string[] = [];

      // デフォルト値でないグローバルオプションのみ表示
      const nonDefaultGlobals = Object.entries(result.values).filter(
        ([key, value]) => {
          const defaultVal = globalDefaults.get(key);
          if (Array.isArray(defaultVal) && Array.isArray(value)) {
            return value.length > 0;
          }
          return value !== defaultVal && value !== null;
        }
      );

      if (nonDefaultGlobals.length > 0) {
        lines.push("Global options:");
        for (const [key, value] of nonDefaultGlobals) {
          lines.push(`  ${key}: ${formatValue(value)}`);
        }
        lines.push("");
      }

      if (result.command) {
        lines.push(formatCommand(result.command));
      } else {
        // サブコマンドなしで実行された場合
        lines.push("(no subcommand specified)");
        lines.push('Run with --help for usage information.');
      }

      console.log(lines.join("\n"));
    } else if (result.help_requested) {
      // ヘルプ表示
      console.log(result.help);
    } else {
      // エラー
      console.error(`error: ${result.error ?? "unknown error"}`);
      console.error("");
      console.error("Run with --help for more information.");
      process.exit(1);
    }
  } catch (e) {
    console.error(`error: ${(e as Error).message}`);
    process.exit(1);
  }
}

main();
