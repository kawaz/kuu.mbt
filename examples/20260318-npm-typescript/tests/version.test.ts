import { describe, it, expect, beforeAll } from "vitest";
import { type KuuParseFn, type KuuSchema } from "../src/kuu-bridge.js";
import { versionCommand } from "../src/schema.js";
import { getParser } from "./setup.js";

const versionSchema: KuuSchema = { require_cmd: true, opts: [versionCommand] };

describe("npm version", () => {
  let parse: KuuParseFn;

  beforeAll(async () => {
    parse = await getParser();
  });

  it("npm version patch → command=version, release='patch'", () => {
    const result = parse(versionSchema, ["version", "patch"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("version");
      expect(result.command?.values.release).toBe("patch");
    }
  });

  it("npm version minor → release='minor'", () => {
    const result = parse(versionSchema, ["version", "minor"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("version");
      expect(result.command?.values.release).toBe("minor");
    }
  });

  it("npm version major → release='major'", () => {
    const result = parse(versionSchema, ["version", "major"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("version");
      expect(result.command?.values.release).toBe("major");
    }
  });

  it("npm version 1.2.3 → 明示的バージョン指定", () => {
    const result = parse(versionSchema, ["version", "1.2.3"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("version");
      expect(result.command?.values.release).toBe("1.2.3");
    }
  });

  it("npm version premajor --preid beta → preid='beta'", () => {
    const result = parse(versionSchema, ["version", "premajor", "--preid", "beta"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("version");
      expect(result.command?.values.release).toBe("premajor");
      expect(result.command?.values.preid).toBe("beta");
    }
  });

  it("npm version patch --no-git-tag-version → git-tag-version=false (variation)", () => {
    const result = parse(versionSchema, ["version", "patch", "--no-git-tag-version"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("version");
      expect(result.command?.values.release).toBe("patch");
      expect(result.command?.values["git-tag-version"]).toBe(false);
    }
  });

  it("npm version patch --allow-same-version → allow-same-version=true", () => {
    const result = parse(versionSchema, ["version", "patch", "--allow-same-version"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("version");
      expect(result.command?.values.release).toBe("patch");
      expect(result.command?.values["allow-same-version"]).toBe(true);
    }
  });

  it("npm version --help → ヘルプ表示", () => {
    const result = parse(versionSchema, ["version", "--help"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "help_requested" in result) {
      expect(result.help_requested).toBe(true);
      expect(result.help).toContain("Bump a package version");
      expect(result.help).toContain("--preid");
    }
  });
});
