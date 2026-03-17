import { describe, it, expect, beforeAll } from "vitest";
import { type KuuParseFn } from "../src/kuu-bridge.js";
import { npmSchema } from "../src/schema.js";
import { getParser } from "./setup.js";

describe("npm install", () => {
  let parse: KuuParseFn;

  beforeAll(async () => {
    parse = await getParser();
  });

  it("npm install (引数なし) → 成功、packages は空配列", () => {
    const result = parse(npmSchema, ["install"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("install");
      expect(result.command?.values.packages).toEqual([]);
    }
  });

  it('npm i express → エイリアス "i" で install コマンド、packages に "express"', () => {
    const result = parse(npmSchema, ["i", "express"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("install");
      expect(result.command?.values.packages).toEqual(["express"]);
    }
  });

  it("npm install express lodash → 複数パッケージ", () => {
    const result = parse(npmSchema, ["install", "express", "lodash"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("install");
      expect(result.command?.values.packages).toEqual(["express", "lodash"]);
    }
  });

  it("npm install --save-dev typescript → save-dev フラグ true", () => {
    const result = parse(npmSchema, ["install", "--save-dev", "typescript"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("install");
      expect(result.command?.values["save-dev"]).toBe(true);
      expect(result.command?.values.packages).toEqual(["typescript"]);
    }
  });

  it("npm install -D typescript → shorts で save-dev", () => {
    const result = parse(npmSchema, ["install", "-D", "typescript"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("install");
      expect(result.command?.values["save-dev"]).toBe(true);
      expect(result.command?.values.packages).toEqual(["typescript"]);
    }
  });

  it("npm install --save-exact --save-dev typescript → 複数フラグ", () => {
    const result = parse(npmSchema, [
      "install",
      "--save-exact",
      "--save-dev",
      "typescript",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("install");
      expect(result.command?.values["save-exact"]).toBe(true);
      expect(result.command?.values["save-dev"]).toBe(true);
      expect(result.command?.values.packages).toEqual(["typescript"]);
    }
  });

  it("npm install --omit dev --omit optional → append_string で複数値", () => {
    const result = parse(npmSchema, [
      "install",
      "--omit",
      "dev",
      "--omit",
      "optional",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("install");
      expect(result.command?.values.omit).toEqual(["dev", "optional"]);
    }
  });

  it("npm install --global typescript → global フラグ", () => {
    const result = parse(npmSchema, ["install", "--global", "typescript"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("install");
      expect(result.command?.values.global).toBe(true);
      expect(result.command?.values.packages).toEqual(["typescript"]);
    }
  });

  it("npm install --save --save-dev → exclusive 制約違反でエラー", () => {
    const result = parse(npmSchema, ["install", "--save", "--save-dev"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "error" in result) {
      expect(result.error).toBeTruthy();
    }
  });

  it("npm install --help → ヘルプ表示", () => {
    const result = parse(npmSchema, ["install", "--help"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "help_requested" in result) {
      expect(result.help_requested).toBe(true);
      expect(result.help).toContain("Install packages");
      expect(result.help).toContain("--save-dev");
    }
  });
});
