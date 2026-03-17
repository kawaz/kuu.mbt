import type { KuuCommandResult } from "./kuu-bridge.js";
import { loadKuu } from "./kuu-bridge.js";
import { npmSchema } from "./schema.js";

function formatValues(values: Record<string, unknown>, indent = ""): string {
  const lines: string[] = [];
  for (const [key, value] of Object.entries(values)) {
    if (Array.isArray(value)) {
      lines.push(`${indent}${key}: [${value.join(", ")}]`);
    } else {
      lines.push(`${indent}${key}: ${value}`);
    }
  }
  return lines.join("\n");
}

function formatCommand(cmd: KuuCommandResult, depth = 0): string {
  const indent = "  ".repeat(depth);
  const lines: string[] = [];
  lines.push(`${indent}command: ${cmd.name}`);
  const valueStr = formatValues(cmd.values, indent + "  ");
  if (valueStr) lines.push(valueStr);
  if (cmd.command) {
    lines.push(formatCommand(cmd.command, depth + 1));
  }
  return lines.join("\n");
}

async function main() {
  try {
    const args = process.argv.slice(2);
    const parse = await loadKuu();
    const result = parse(npmSchema, args);

    if (result.ok) {
      console.log("Parse successful!");
      const globalStr = formatValues(result.values, "  ");
      if (globalStr) {
        console.log("globals:");
        console.log(globalStr);
      }
      if (result.command) {
        console.log(formatCommand(result.command));
      }
    } else if ("help_requested" in result && result.help_requested) {
      console.log(result.help);
    } else if ("error" in result) {
      console.error(`Error: ${result.error}`);
      if (result.help) {
        console.error("\n" + result.help);
      }
      process.exitCode = 1;
    }
  } catch (error) {
    console.error(
      `Fatal: ${error instanceof Error ? error.message : String(error)}`,
    );
    process.exitCode = 1;
  }
}

main();
