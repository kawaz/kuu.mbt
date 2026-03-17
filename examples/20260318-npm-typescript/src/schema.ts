import type { KuuSchema, KuuOpt } from "./kuu-bridge.js";

// --- Global Options ---

const globalOpts: KuuOpt[] = [
  {
    kind: "string",
    name: "registry",
    description: "Registry URL",
    env: "NPM_CONFIG_REGISTRY",
    global: true,
  },
  {
    kind: "flag",
    name: "json",
    description: "Output JSON",
    global: true,
  },
  {
    kind: "append_string",
    name: "workspace",
    shorts: "w",
    description: "Run in the context of a workspace",
    global: true,
  },
  {
    kind: "flag",
    name: "workspaces",
    description: "Enable running across all workspaces",
    global: true,
  },
  {
    kind: "string",
    name: "loglevel",
    description: "Log verbosity level",
    choices: ["silent", "error", "warn", "notice", "http", "info", "verbose", "silly"],
    default: "notice",
    global: true,
  },
];

// --- install ---

export const installCommand: KuuOpt = {
  kind: "command",
  name: "install",
  aliases: ["i", "add"],
  description: "Install packages",
  opts: [
    { kind: "rest", name: "packages" },
    { kind: "flag", name: "save", shorts: "S", description: "Save to dependencies" },
    { kind: "flag", name: "save-dev", shorts: "D", description: "Save to devDependencies" },
    { kind: "flag", name: "save-optional", shorts: "O", description: "Save to optionalDependencies" },
    { kind: "flag", name: "save-exact", shorts: "E", description: "Save exact version" },
    { kind: "flag", name: "global", shorts: "g", description: "Install globally" },
    {
      kind: "append_string",
      name: "omit",
      description: "Omit package types",
      choices: ["dev", "optional", "peer"],
    },
  ],
  exclusive: [["save", "save-dev", "save-optional"]],
};

// --- run ---

export const runCommand: KuuOpt = {
  kind: "command",
  name: "run",
  aliases: ["run-script"],
  description: "Run a script",
  opts: [
    { kind: "positional", name: "script", description: "Script name" },
    { kind: "dashdash" },
    { kind: "flag", name: "if-present", description: "Don't error if script is missing" },
    { kind: "string", name: "script-shell", description: "Shell to use for scripts" },
  ],
};

// --- publish ---

export const publishCommand: KuuOpt = {
  kind: "command",
  name: "publish",
  description: "Publish a package",
  opts: [
    { kind: "positional", name: "tarball", description: "Package tarball or directory" },
    { kind: "string", name: "tag", default: "latest", description: "Distribution tag" },
    {
      kind: "string",
      name: "access",
      choices: ["public", "restricted"],
      description: "Access level",
    },
    { kind: "flag", name: "dry-run", description: "Do everything except publish" },
    { kind: "string", name: "otp", description: "One-time password" },
  ],
};

// --- audit ---

export const auditCommand: KuuOpt = {
  kind: "command",
  name: "audit",
  description: "Run a security audit",
  opts: [
    {
      kind: "command",
      name: "fix",
      description: "Fix vulnerabilities",
      opts: [
        { kind: "flag", name: "dry-run", description: "Only report, don't fix" },
        { kind: "flag", name: "force", shorts: "f", description: "Force fix" },
      ],
    },
    {
      kind: "command",
      name: "signatures",
      description: "Verify registry signatures",
    },
    {
      kind: "string",
      name: "audit-level",
      description: "Minimum vulnerability level",
      choices: ["info", "low", "moderate", "high", "critical", "none"],
    },
    {
      kind: "append_string",
      name: "omit",
      description: "Omit package types",
      choices: ["dev", "optional", "peer"],
    },
  ],
};

// --- config ---

export const configCommand: KuuOpt = {
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
      opts: [{ kind: "positional", name: "key", description: "Config key" }],
    },
    {
      kind: "command",
      name: "delete",
      description: "Delete a config value",
      opts: [{ kind: "positional", name: "key", description: "Config key" }],
    },
    {
      kind: "command",
      name: "list",
      description: "List all config",
    },
    { kind: "flag", name: "global", shorts: "g", description: "Use global config" },
  ],
};

// --- version ---

export const versionCommand: KuuOpt = {
  kind: "command",
  name: "version",
  description: "Bump a package version",
  opts: [
    { kind: "positional", name: "release", description: "Version or release type" },
    { kind: "string", name: "preid", description: "Prerelease identifier" },
    { kind: "flag", name: "allow-same-version", description: "Allow same version" },
    {
      kind: "flag",
      name: "git-tag-version",
      default: true,
      description: "Tag version in git",
      variation_false: "no",
    },
    {
      kind: "flag",
      name: "commit-hooks",
      default: true,
      description: "Run git commit hooks",
      variation_false: "no",
    },
    { kind: "flag", name: "sign-git-tag", description: "Sign git tag" },
  ],
};

// --- Full Schema ---

export const npmSchema: KuuSchema = {
  version: 1,
  description: "npm - JavaScript Package Manager",
  require_cmd: true,
  opts: [
    ...globalOpts,
    installCommand,
    runCommand,
    publishCommand,
    auditCommand,
    configCommand,
    versionCommand,
  ],
};
