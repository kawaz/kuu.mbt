import { describe, it, expect, beforeAll } from "vitest";
import { loadKuu, type KuuParseFn, type KuuSchema } from "../src/kuu-bridge.js";
import { getParser } from "./setup.js";

describe("kuu-bridge", () => {
  let parse: KuuParseFn;

  beforeAll(async () => {
    parse = await getParser();
  });

  it("should parse a simple flag", () => {
    const schema: KuuSchema = {
      opts: [{ kind: "flag", name: "verbose", shorts: "v" }],
    };
    const result = parse(schema, ["--verbose"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.verbose).toBe(true);
    }
  });

  it("should parse a string option", () => {
    const schema: KuuSchema = {
      opts: [{ kind: "string", name: "name", default: "world" }],
    };
    const result = parse(schema, ["--name", "kuu"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.name).toBe("kuu");
    }
  });

  it("should return default when option not provided", () => {
    const schema: KuuSchema = {
      opts: [{ kind: "string", name: "name", default: "world" }],
    };
    const result = parse(schema, []);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.values.name).toBe("world");
    }
  });

  it("should return error for unknown option", () => {
    const schema: KuuSchema = {
      opts: [{ kind: "flag", name: "verbose" }],
    };
    const result = parse(schema, ["--unknown"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "error" in result) {
      expect(result.error).toContain("unknown");
    }
  });

  it("should parse a subcommand", () => {
    const schema: KuuSchema = {
      opts: [
        {
          kind: "command",
          name: "serve",
          opts: [{ kind: "int", name: "port", default: 8080 }],
        },
      ],
    };
    const result = parse(schema, ["serve", "--port", "3000"]);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.command?.name).toBe("serve");
      expect(result.command?.values.port).toBe(3000);
    }
  });

  it("should handle help request", () => {
    const schema: KuuSchema = {
      description: "Test CLI",
      opts: [{ kind: "flag", name: "verbose" }],
    };
    const result = parse(schema, ["--help"]);
    expect(result.ok).toBe(false);
    if (!result.ok && "help_requested" in result) {
      expect(result.help_requested).toBe(true);
      expect(result.help).toContain("Test CLI");
    }
  });
});
