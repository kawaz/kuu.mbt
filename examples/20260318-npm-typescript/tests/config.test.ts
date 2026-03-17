import { describe, it, expect, beforeAll } from "vitest";
import {
  loadKuu,
  type KuuParseFn,
  type KuuSchema,
} from "../src/kuu-bridge.js";

const configSchema: KuuSchema = {
  require_cmd: true,
  opts: [
    {
      kind: "command",
      name: "config",
      aliases: ["c"],
      description: "Manage configuration",
      require_cmd: true,
      opts: [
        {
          kind: "command",
          name: "set",
          description: "Set a config value",
          opts: [
            { kind: "positional", name: "key", description: "Config key" },
            { kind: "positional", name: "value", description: "Config value" },
          ],
        },
        {
          kind: "command",
          name: "get",
          description: "Get a config value",
          opts: [
            { kind: "positional", name: "key", description: "Config key" },
          ],
        },
        {
          kind: "command",
          name: "delete",
          description: "Delete a config value",
          opts: [
            { kind: "positional", name: "key", description: "Config key" },
          ],
        },
        {
          kind: "command",
          name: "list",
          description: "List all config",
          opts: [
            { kind: "flag", name: "json", description: "JSON output" },
          ],
        },
        {
          kind: "flag",
          name: "global",
          shorts: "g",
          description: "Use global config",
        },
      ],
    },
  ],
};

describe("npm config", () => {
  let parse: KuuParseFn;

  beforeAll(async () => {
    parse = await loadKuu();
  });

  it("npm config set registry https://registry.npmjs.org → config > set, key と value", () => {
    const result = parse(configSchema, [
      "config",
      "set",
      "registry",
      "https://registry.npmjs.org",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("config");
      expect(result.command?.command?.name).toBe("set");
      expect(result.command?.command?.values.key).toBe("registry");
      expect(result.command?.command?.values.value).toBe(
        "https://registry.npmjs.org",
      );
    }
  });

  it("npm config get registry → config > get, key='registry'", () => {
    const result = parse(configSchema, ["config", "get", "registry"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("config");
      expect(result.command?.command?.name).toBe("get");
      expect(result.command?.command?.values.key).toBe("registry");
    }
  });

  it("npm config delete registry → config > delete, key='registry'", () => {
    const result = parse(configSchema, ["config", "delete", "registry"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("config");
      expect(result.command?.command?.name).toBe("delete");
      expect(result.command?.command?.values.key).toBe("registry");
    }
  });

  it("npm config list → config > list", () => {
    const result = parse(configSchema, ["config", "list"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("config");
      expect(result.command?.command?.name).toBe("list");
    }
  });

  it("npm config list --json → config > list + json フラグ", () => {
    const result = parse(configSchema, ["config", "list", "--json"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("config");
      expect(result.command?.command?.name).toBe("list");
      expect(result.command?.command?.values.json).toBe(true);
    }
  });

  it("npm c set foo bar → エイリアス 'c' で config コマンド", () => {
    const result = parse(configSchema, ["c", "set", "foo", "bar"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("config");
      expect(result.command?.command?.name).toBe("set");
      expect(result.command?.command?.values.key).toBe("foo");
      expect(result.command?.command?.values.value).toBe("bar");
    }
  });

  it("npm config --global set registry https://... → global フラグ（サブコマンド前）", () => {
    const result = parse(configSchema, [
      "config",
      "--global",
      "set",
      "registry",
      "https://registry.npmjs.org",
    ]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("config");
      expect(result.command?.values.global).toBe(true);
      expect(result.command?.command?.name).toBe("set");
      expect(result.command?.command?.values.key).toBe("registry");
      expect(result.command?.command?.values.value).toBe(
        "https://registry.npmjs.org",
      );
    }
  });

  it("npm config --help → ヘルプ表示", () => {
    const result = parse(configSchema, ["config", "--help"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "help_requested" in result) {
      expect(result.help_requested).toBe(true);
      expect(result.help).toContain("Manage configuration");
    }
  });
});
