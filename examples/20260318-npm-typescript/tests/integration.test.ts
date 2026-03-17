import { describe, it, expect, beforeAll } from "vitest";
import { loadKuu, type KuuParseFn } from "../src/kuu-bridge.js";
import { npmSchema } from "../src/schema.js";

describe("npm CLI integration (full schema)", () => {
  let parse: KuuParseFn;

  beforeAll(async () => {
    parse = await loadKuu();
  });

  // --- Global options ---

  it("グローバル --json が install で有効", () => {
    const result = parse(npmSchema, ["--json", "install", "express"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.json).toBe(true);
      expect(result.command?.name).toBe("install");
    }
  });

  it("グローバル --workspace が複数指定可能", () => {
    const result = parse(npmSchema, [
      "-w", "packages/core",
      "-w", "packages/cli",
      "install",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.workspace).toEqual(["packages/core", "packages/cli"]);
      expect(result.command?.name).toBe("install");
    }
  });

  it("グローバル --loglevel に choices 制約", () => {
    const result = parse(npmSchema, ["--loglevel", "verbose", "install"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.loglevel).toBe("verbose");
    }
  });

  it("グローバル --loglevel の不正値はエラー", () => {
    const result = parse(npmSchema, ["--loglevel", "debug", "install"]);
    expect(result.ok).toBe(false);
  });

  // --- Cross-command tests ---

  it("npm run test -- --coverage with global --json", () => {
    const result = parse(npmSchema, ["--json", "run", "test", "--", "--coverage"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.json).toBe(true);
      expect(result.command?.name).toBe("run");
      expect(result.command?.values.script).toBe("test");
      expect(result.command?.values["--"]).toEqual(["--coverage"]);
    }
  });

  it("npm audit fix --dry-run with global --json", () => {
    const result = parse(npmSchema, ["--json", "audit", "fix", "--dry-run"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.json).toBe(true);
      expect(result.command?.name).toBe("audit");
      expect(result.command?.command?.name).toBe("fix");
      expect(result.command?.command?.values["dry-run"]).toBe(true);
    }
  });

  it("npm c set registry https://example.com with global -w", () => {
    const result = parse(npmSchema, [
      "-w", "my-pkg",
      "c", "set", "registry", "https://example.com",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.workspace).toEqual(["my-pkg"]);
      expect(result.command?.name).toBe("config");
      expect(result.command?.command?.name).toBe("set");
      expect(result.command?.command?.values.key).toBe("registry");
      expect(result.command?.command?.values.value).toBe("https://example.com");
    }
  });

  it("npm version patch --no-commit-hooks with global --registry", () => {
    const result = parse(npmSchema, [
      "--registry", "https://registry.example.com",
      "version", "patch", "--no-commit-hooks",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.registry).toBe("https://registry.example.com");
      expect(result.command?.name).toBe("version");
      expect(result.command?.values.release).toBe("patch");
      expect(result.command?.values["commit-hooks"]).toBe(false);
    }
  });

  // --- Help ---

  it("npm --help でトップレベルヘルプ", () => {
    const result = parse(npmSchema, ["--help"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "help_requested" in result) {
      expect(result.help).toContain("npm");
      expect(result.help).toContain("install");
      expect(result.help).toContain("run");
      expect(result.help).toContain("publish");
      expect(result.help).toContain("audit");
      expect(result.help).toContain("config");
      expect(result.help).toContain("version");
    }
  });

  it("引数なしはエラー (require_cmd)", () => {
    const result = parse(npmSchema, []);
    expect(result.ok).toBe(false);
  });
});
