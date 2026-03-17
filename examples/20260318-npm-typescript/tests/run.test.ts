import { describe, it, expect, beforeAll } from "vitest";
import { type KuuParseFn, type KuuSchema } from "../src/kuu-bridge.js";
import { runCommand } from "../src/schema.js";
import { getParser } from "./setup.js";

const runSchema: KuuSchema = { require_cmd: true, opts: [runCommand] };

describe("npm run", () => {
  let parse: KuuParseFn;

  beforeAll(async () => {
    parse = await getParser();
  });

  it("npm run test → command=run, script='test'", () => {
    const result = parse(runSchema, ["run", "test"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("run");
      expect(result.command?.values.script).toBe("test");
    }
  });

  it("npm run build -- --watch → dashdash 後の引数が '--' キーに入る", () => {
    const result = parse(runSchema, ["run", "build", "--", "--watch"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("run");
      expect(result.command?.values.script).toBe("build");
      expect(result.command?.values["--"]).toEqual(["--watch"]);
    }
  });

  it("npm run test -- --coverage --verbose → 複数の dashdash 引数", () => {
    const result = parse(runSchema, [
      "run",
      "test",
      "--",
      "--coverage",
      "--verbose",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("run");
      expect(result.command?.values.script).toBe("test");
      expect(result.command?.values["--"]).toEqual(["--coverage", "--verbose"]);
    }
  });

  it("npm run start --if-present → if-present フラグ", () => {
    const result = parse(runSchema, ["run", "start", "--if-present"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("run");
      expect(result.command?.values.script).toBe("start");
      expect(result.command?.values["if-present"]).toBe(true);
    }
  });

  it("npm run-script lint → エイリアス 'run-script' で run コマンド", () => {
    const result = parse(runSchema, ["run-script", "lint"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("run");
      expect(result.command?.values.script).toBe("lint");
    }
  });

  it("npm run (スクリプト名なし) → positional なしでもパース成功", () => {
    const result = parse(runSchema, ["run"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("run");
      expect(result.command?.values.script).toBe("");
    }
  });

  it("npm run test --if-present -- --arg → オプション + dashdash 複合", () => {
    const result = parse(runSchema, [
      "run",
      "test",
      "--if-present",
      "--",
      "--arg",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("run");
      expect(result.command?.values.script).toBe("test");
      expect(result.command?.values["if-present"]).toBe(true);
      expect(result.command?.values["--"]).toEqual(["--arg"]);
    }
  });

  it("npm run test -- → dashdash のみ、引数なし", () => {
    const result = parse(runSchema, ["run", "test", "--"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("run");
      expect(result.command?.values.script).toBe("test");
      expect(result.command?.values["--"]).toEqual([]);
    }
  });

  it("npm run test --help → ヘルプ表示", () => {
    const result = parse(runSchema, ["run", "test", "--help"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "help_requested" in result) {
      expect(result.help_requested).toBe(true);
      expect(result.help).toContain("Run a script");
    }
  });
});
