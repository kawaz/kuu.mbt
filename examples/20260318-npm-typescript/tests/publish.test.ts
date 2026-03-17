import { describe, it, expect, beforeAll } from "vitest";
import {
  loadKuu,
  type KuuParseFn,
  type KuuSchema,
} from "../src/kuu-bridge.js";

const publishSchema: KuuSchema = {
  require_cmd: true,
  opts: [
    {
      kind: "command",
      name: "publish",
      description: "Publish a package",
      opts: [
        {
          kind: "positional",
          name: "tarball",
          description: "Package tarball or directory",
        },
        {
          kind: "string",
          name: "tag",
          default: "latest",
          description: "Distribution tag",
        },
        {
          kind: "string",
          name: "access",
          choices: ["public", "restricted"],
          description: "Access level",
        },
        {
          kind: "flag",
          name: "dry-run",
          description: "Do everything except publish",
        },
        {
          kind: "string",
          name: "otp",
          description: "One-time password",
        },
      ],
    },
  ],
};

describe("npm publish", () => {
  let parse: KuuParseFn;

  beforeAll(async () => {
    parse = await loadKuu();
  });

  it("npm publish → デフォルト値で成功", () => {
    const result = parse(publishSchema, ["publish"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("publish");
      expect(result.command?.values.tag).toBe("latest");
      expect(result.command?.values["dry-run"]).toBe(false);
    }
  });

  it("npm publish --access public → access='public'", () => {
    const result = parse(publishSchema, ["publish", "--access", "public"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.values.access).toBe("public");
    }
  });

  it("npm publish --access restricted → access='restricted'", () => {
    const result = parse(publishSchema, ["publish", "--access", "restricted"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.values.access).toBe("restricted");
    }
  });

  it("npm publish --access invalid → choices 制約違反でエラー", () => {
    const result = parse(publishSchema, ["publish", "--access", "invalid"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "error" in result) {
      expect(result.error).toMatch(/must be one of/i);
    }
  });

  it("npm publish --tag beta → tag='beta'", () => {
    const result = parse(publishSchema, ["publish", "--tag", "beta"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.values.tag).toBe("beta");
    }
  });

  it("npm publish --dry-run → dry-run=true", () => {
    const result = parse(publishSchema, ["publish", "--dry-run"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.values["dry-run"]).toBe(true);
    }
  });

  it("npm publish --otp 123456 → otp='123456'", () => {
    const result = parse(publishSchema, ["publish", "--otp", "123456"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.values.otp).toBe("123456");
    }
  });

  it("npm publish ./my-package → positional で tarball パス", () => {
    const result = parse(publishSchema, ["publish", "./my-package"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.values.tarball).toBe("./my-package");
    }
  });

  it("npm publish --dry-run --tag next --access public → 複数オプション同時", () => {
    const result = parse(publishSchema, [
      "publish",
      "--dry-run",
      "--tag",
      "next",
      "--access",
      "public",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.values["dry-run"]).toBe(true);
      expect(result.command?.values.tag).toBe("next");
      expect(result.command?.values.access).toBe("public");
    }
  });
});
