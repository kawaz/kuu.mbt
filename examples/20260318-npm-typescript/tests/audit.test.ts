import { describe, it, expect, beforeAll } from "vitest";
import { type KuuParseFn, type KuuSchema } from "../src/kuu-bridge.js";
import { auditCommand } from "../src/schema.js";
import { getParser } from "./setup.js";

const auditSchema: KuuSchema = { require_cmd: true, opts: [auditCommand] };

describe("npm audit", () => {
  let parse: KuuParseFn;

  beforeAll(async () => {
    parse = await getParser();
  });

  it("npm audit → command=audit (サブコマンドなしでもOK)", () => {
    const result = parse(auditSchema, ["audit"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("audit");
      expect(result.command?.command).toBeUndefined();
    }
  });

  it("npm audit fix → audit の中の fix サブコマンド", () => {
    const result = parse(auditSchema, ["audit", "fix"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("audit");
      expect(result.command?.command?.name).toBe("fix");
    }
  });

  it("npm audit signatures → audit の中の signatures サブコマンド", () => {
    const result = parse(auditSchema, ["audit", "signatures"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("audit");
      expect(result.command?.command?.name).toBe("signatures");
    }
  });

  it("npm audit --audit-level high → choices で audit-level 指定", () => {
    const result = parse(auditSchema, ["audit", "--audit-level", "high"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("audit");
      expect(result.command?.values["audit-level"]).toBe("high");
    }
  });

  it("npm audit --audit-level invalid → choices 制約違反エラー", () => {
    const result = parse(auditSchema, ["audit", "--audit-level", "invalid"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "error" in result) {
      expect(result.error).toBeTruthy();
    }
  });

  it("npm audit fix --dry-run → fix サブコマンド + dry-run フラグ", () => {
    const result = parse(auditSchema, ["audit", "fix", "--dry-run"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("audit");
      expect(result.command?.command?.name).toBe("fix");
      expect(result.command?.command?.values["dry-run"]).toBe(true);
    }
  });

  it("npm audit fix --force → fix + force フラグ", () => {
    const result = parse(auditSchema, ["audit", "fix", "--force"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("audit");
      expect(result.command?.command?.name).toBe("fix");
      expect(result.command?.command?.values.force).toBe(true);
    }
  });

  it("npm audit --omit dev --omit optional → 複数 omit", () => {
    const result = parse(auditSchema, [
      "audit",
      "--omit",
      "dev",
      "--omit",
      "optional",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("audit");
      expect(result.command?.values.omit).toEqual(["dev", "optional"]);
    }
  });
});
