import { describe, it, expect } from "vitest";
import kuu, { KuuParseError, KuuHelpRequested } from "../src/index.js";

describe("kuu TypeScript DX PoC", () => {
  // ------------------------------------------------------------------
  // Basic combinators
  // ------------------------------------------------------------------

  describe("flag", () => {
    it("parses --verbose as true", async () => {
      const p = kuu.parser({
        opts: {
          verbose: kuu.flag({ description: "Verbose output" }),
        },
      });
      const r = await p.parse(["--verbose"]);
      expect(r.verbose).toBe(true);
    });

    it("defaults to false when not specified", async () => {
      const p = kuu.parser({
        opts: {
          verbose: kuu.flag(),
        },
      });
      const r = await p.parse([]);
      expect(r.verbose).toBe(false);
    });
  });

  describe("string", () => {
    it("parses --host value", async () => {
      const p = kuu.parser({
        opts: {
          host: kuu.string({ default: "localhost" }),
        },
      });
      const r = await p.parse(["--host", "example.com"]);
      expect(r.host).toBe("example.com");
    });

    it("uses default when not specified", async () => {
      const p = kuu.parser({
        opts: {
          host: kuu.string({ default: "localhost" }),
        },
      });
      const r = await p.parse([]);
      expect(r.host).toBe("localhost");
    });
  });

  describe("int", () => {
    it("parses --port 8080", async () => {
      const p = kuu.parser({
        opts: {
          port: kuu.int({ default: 3000 }),
        },
      });
      const r = await p.parse(["--port", "8080"]);
      expect(r.port).toBe(8080);
    });

    it("uses default when not specified", async () => {
      const p = kuu.parser({
        opts: {
          port: kuu.int({ default: 3000 }),
        },
      });
      const r = await p.parse([]);
      expect(r.port).toBe(3000);
    });
  });

  describe("float", () => {
    it("parses --rate 3.14", async () => {
      const p = kuu.parser({
        opts: {
          rate: kuu.float({ default: 1.0 }),
        },
      });
      const r = await p.parse(["--rate", "3.14"]);
      expect(r.rate).toBe(3.14);
    });
  });

  describe("count", () => {
    it("counts -vvv as 3", async () => {
      const p = kuu.parser({
        opts: {
          verbose: kuu.count({ shorts: "v" }),
        },
      });
      const r = await p.parse(["-vvv"]);
      expect(r.verbose).toBe(3);
    });
  });

  describe("boolean", () => {
    it("parses --debug true", async () => {
      const p = kuu.parser({
        opts: {
          debug: kuu.boolean(),
        },
      });
      const r = await p.parse(["--debug", "true"]);
      expect(r.debug).toBe(true);
    });

    it("parses --debug off", async () => {
      const p = kuu.parser({
        opts: {
          debug: kuu.boolean(),
        },
      });
      const r = await p.parse(["--debug", "off"]);
      expect(r.debug).toBe(false);
    });
  });

  // ------------------------------------------------------------------
  // Append combinators
  // ------------------------------------------------------------------

  describe("appendString", () => {
    it("collects repeated --tag values", async () => {
      const p = kuu.parser({
        opts: {
          tag: kuu.appendString(),
        },
      });
      const r = await p.parse(["--tag", "a", "--tag", "b"]);
      expect(r.tag).toEqual(["a", "b"]);
    });
  });

  describe("appendInt", () => {
    it("collects repeated --id values", async () => {
      const p = kuu.parser({
        opts: {
          id: kuu.appendInt(),
        },
      });
      const r = await p.parse(["--id", "1", "--id", "2", "--id", "3"]);
      expect(r.id).toEqual([1, 2, 3]);
    });
  });

  // ------------------------------------------------------------------
  // Positional and rest
  // ------------------------------------------------------------------

  describe("positional", () => {
    it("captures positional argument", async () => {
      const p = kuu.parser({
        opts: {
          file: kuu.positional({ description: "Input file" }),
        },
      });
      const r = await p.parse(["input.txt"]);
      expect(r.file).toBe("input.txt");
    });

    it("returns empty string when not provided", async () => {
      const p = kuu.parser({
        opts: {
          file: kuu.positional(),
        },
      });
      const r = await p.parse([]);
      // positional defaults to "" when not consumed
      expect(r.file).toBe("");
    });
  });

  describe("rest", () => {
    it("captures remaining arguments", async () => {
      const p = kuu.parser({
        opts: {
          args: kuu.rest(),
        },
      });
      const r = await p.parse(["a", "b", "c"]);
      expect(r.args).toEqual(["a", "b", "c"]);
    });
  });

  // ------------------------------------------------------------------
  // Combined schema
  // ------------------------------------------------------------------

  describe("combined schema", () => {
    it("parses mixed options", async () => {
      const p = kuu.parser({
        description: "My CLI",
        opts: {
          verbose: kuu.flag({ shorts: "v" }),
          host: kuu.string({ default: "localhost" }),
          port: kuu.int({ default: 8080 }),
        },
      });
      const r = await p.parse(["--verbose", "--host", "example.com", "--port", "9090"]);
      expect(r.verbose).toBe(true);
      expect(r.host).toBe("example.com");
      expect(r.port).toBe(9090);
    });
  });

  // ------------------------------------------------------------------
  // Subcommands
  // ------------------------------------------------------------------

  describe("subcommands", () => {
    it("parses a subcommand with options", async () => {
      const p = kuu.parser({
        opts: {
          verbose: kuu.flag({ shorts: "v", global: true }),
          serve: kuu.sub({
            description: "Start server",
            opts: {
              port: kuu.int({ default: 3000 }),
              dir: kuu.positional({ description: "Directory" }),
            },
          }),
        },
      });
      const r = await p.parse(["--verbose", "serve", "--port", "9090", "."]);
      expect(r.verbose).toBe(true);
      expect(r.serve).toBeDefined();
      expect(r.serve?.port).toBe(9090);
      expect(r.serve?.dir).toBe(".");
    });

    it("returns undefined for unmatched subcommand", async () => {
      const p = kuu.parser({
        opts: {
          verbose: kuu.flag(),
          serve: kuu.sub({
            opts: {
              port: kuu.int({ default: 3000 }),
            },
          }),
        },
      });
      const r = await p.parse(["--verbose"]);
      expect(r.verbose).toBe(true);
      expect(r.serve).toBeUndefined();
    });

    it("parses nested subcommands", async () => {
      const p = kuu.parser({
        opts: {
          remote: kuu.sub({
            description: "Manage remotes",
            requireCmd: true,
            opts: {
              add: kuu.sub({
                description: "Add a remote",
                opts: {
                  name: kuu.positional(),
                  url: kuu.positional(),
                },
              }),
            },
          }),
        },
      });
      const r = await p.parse(["remote", "add", "origin", "https://github.com/x/y"]);
      expect(r.remote).toBeDefined();
      expect(r.remote?.add).toBeDefined();
      expect(r.remote?.add?.name).toBe("origin");
      expect(r.remote?.add?.url).toBe("https://github.com/x/y");
    });
  });

  // ------------------------------------------------------------------
  // Constraints
  // ------------------------------------------------------------------

  describe("constraints", () => {
    it("rejects mutually exclusive options", async () => {
      const p = kuu.parser({
        opts: {
          shared: kuu.flag(),
          static: kuu.flag(),
        },
        exclusive: [["shared", "static"]],
      });
      await expect(p.parse(["--shared", "--static"])).rejects.toThrow(KuuParseError);
    });

    it("rejects missing required options", async () => {
      const p = kuu.parser({
        opts: {
          output: kuu.string({ default: "" }),
        },
        required: ["output"],
      });
      await expect(p.parse([])).rejects.toThrow(KuuParseError);
    });
  });

  // ------------------------------------------------------------------
  // Environment variables
  // ------------------------------------------------------------------

  describe("environment variables", () => {
    it("reads value from env when CLI arg not provided", async () => {
      const p = kuu.parser({
        opts: {
          host: kuu.string({ default: "localhost", env: "HOST" }),
        },
      });
      const r = await p.parse([], { HOST: "env-host.example.com" });
      expect(r.host).toBe("env-host.example.com");
    });

    it("CLI arg overrides env", async () => {
      const p = kuu.parser({
        opts: {
          host: kuu.string({ default: "localhost", env: "HOST" }),
        },
      });
      const r = await p.parse(["--host", "cli-host"], { HOST: "env-host" });
      expect(r.host).toBe("cli-host");
    });
  });

  // ------------------------------------------------------------------
  // Error handling
  // ------------------------------------------------------------------

  describe("errors", () => {
    it("throws KuuParseError on unknown option", async () => {
      const p = kuu.parser({
        opts: {
          port: kuu.int({ default: 8080 }),
        },
      });
      try {
        await p.parse(["--unknown"]);
        expect.fail("should have thrown");
      } catch (e) {
        expect(e).toBeInstanceOf(KuuParseError);
        expect((e as KuuParseError).kind).toBe("UnknownOption");
      }
    });

    it("throws KuuParseError with tip for typo", async () => {
      const p = kuu.parser({
        opts: {
          port: kuu.int({ default: 8080 }),
        },
      });
      try {
        await p.parse(["--prot"]);
        expect.fail("should have thrown");
      } catch (e) {
        expect(e).toBeInstanceOf(KuuParseError);
        expect((e as KuuParseError).tip).toBe("--port");
      }
    });

    it("throws KuuHelpRequested on --help", async () => {
      const p = kuu.parser({
        description: "Test CLI",
        opts: {
          verbose: kuu.flag({ description: "Verbose output" }),
        },
      });
      try {
        await p.parse(["--help"]);
        expect.fail("should have thrown");
      } catch (e) {
        expect(e).toBeInstanceOf(KuuHelpRequested);
        expect((e as KuuHelpRequested).helpText).toContain("--verbose");
      }
    });
  });

  // ------------------------------------------------------------------
  // Completions
  // ------------------------------------------------------------------

  describe("completions", () => {
    it("generates bash completion script", async () => {
      const p = kuu.parser({
        opts: {
          verbose: kuu.flag({ shorts: "v", description: "Verbose" }),
          host: kuu.string({ default: "localhost", description: "Host" }),
        },
      });
      const script = await p.completions("bash", "myapp");
      expect(script).toContain("complete -F _myapp myapp");
      expect(script).toContain("--verbose");
      expect(script).toContain("--host");
    });

    it("generates zsh completion script", async () => {
      const p = kuu.parser({
        opts: {
          verbose: kuu.flag({ shorts: "v", description: "Verbose" }),
        },
      });
      const script = await p.completions("zsh", "myapp");
      expect(script).toContain("#compdef myapp");
      expect(script).toContain("--verbose");
    });

    it("generates fish completion script", async () => {
      const p = kuu.parser({
        opts: {
          verbose: kuu.flag({ shorts: "v", description: "Verbose" }),
        },
      });
      const script = await p.completions("fish", "myapp");
      expect(script).toContain("complete -c myapp");
      expect(script).toContain("-l verbose");
    });
  });

  // ------------------------------------------------------------------
  // Design roadmap example (from DESIGN-roadmap.md)
  // ------------------------------------------------------------------

  describe("roadmap example shape", () => {
    it("matches the design in DESIGN-roadmap.md", async () => {
      const p = kuu.parser({
        opts: {
          verbose: kuu.count({ shorts: "v", global: true }),
          port: kuu.int({ default: 8080 }),
          host: kuu.string({ default: "localhost" }),
          serve: kuu.sub({
            opts: {
              dir: kuu.positional(),
            },
          }),
        },
      });

      const r = await p.parse(["-vvv", "--port", "9090", "serve", "/var/www"]);
      expect(r.verbose).toBe(3);
      expect(r.port).toBe(9090);
      expect(r.host).toBe("localhost");
      expect(r.serve).toBeDefined();
      expect(r.serve?.dir).toBe("/var/www");
    });
  });
});
