/**
 * @kawaz/kuu — TypeScript DX layer for kuu CLI parser.
 *
 * Provides a declarative schema DSL that maps to the kuu WASM bridge's JSON protocol.
 * Type inference ensures parse results are fully typed.
 */

import { readFile } from "node:fs/promises";

// =============================================================================
// WASM Bridge (low-level)
// =============================================================================

interface WasmExports {
  kuu_parse: (json: string) => string;
  kuu_completions: (schema: string, shell: string, commandName: string) => string;
}

let cachedExports: WasmExports | null = null;

async function loadWasm(wasmPath?: string): Promise<WasmExports> {
  if (cachedExports) return cachedExports;

  const resolvedPath =
    wasmPath ??
    process.env.KUU_WASM_PATH ??
    new URL(
      "../../../_build/wasm-gc/release/build/wasm/wasm.wasm",
      import.meta.url,
    ).pathname;

  const wasmBytes = await readFile(resolvedPath);
  const { instance } = await WebAssembly.instantiate(
    wasmBytes,
    {},
    // @ts-expect-error -- WASM-GC builtins not in TS lib types yet
    { builtins: ["js-string"], importedStringConstants: "_" },
  );

  cachedExports = instance.exports as unknown as WasmExports;
  return cachedExports;
}

// =============================================================================
// JSON Protocol Types (internal — mirrors kuu WASM bridge I/O)
// =============================================================================

interface JsonOpt {
  kind: string;
  name?: string;
  shorts?: string;
  description?: string;
  default?: unknown;
  choices?: readonly string[];
  global?: boolean;
  env?: string;
  aliases?: readonly string[];
  implicit_value?: unknown;
  opts?: JsonOpt[];
  require_cmd?: boolean;
  visibility?: "visible" | "advanced" | "hidden";
  variation_toggle?: string;
  variation_true?: string;
  variation_false?: string;
  variation_reset?: string;
  variation_unset?: string;
  post?: unknown;
  // deprecated
  target?: string;
  msg?: string;
  // clone
  clone_of?: string;
}

interface JsonSchema {
  version: number;
  description?: string;
  opts: JsonOpt[];
  args: string[];
  env?: Record<string, string>;
  env_prefix?: string;
  auto_env?: boolean;
  exclusive?: string[][];
  required?: string[];
  at_least_one?: string[][];
  requires?: Array<{ source: string; target: string; msg?: string }>;
  require_cmd?: boolean;
}

// =============================================================================
// Schema DSL — Combinator Definitions
// =============================================================================

/** Common parameters shared across most combinators. */
interface CommonParams {
  description?: string;
  shorts?: string;
  global?: boolean;
  env?: string;
  aliases?: readonly string[];
  visibility?: "visible" | "advanced" | "hidden";
}

/** Variation parameters for flag/boolean/count combinators. */
interface VariationParams {
  variationToggle?: string;
  variationTrue?: string;
  variationFalse?: string;
  variationReset?: string;
  variationUnset?: string;
}

// --- Combinator definition types (branded with __kind for type inference) ---

export interface FlagDef extends CommonParams, VariationParams {
  readonly __kind: "flag";
  default?: boolean;
}

export interface StringDef extends CommonParams {
  readonly __kind: "string";
  default?: string;
  choices?: readonly string[];
  implicitValue?: string;
  post?: string;
}

export interface IntDef extends CommonParams {
  readonly __kind: "int";
  default?: number;
  implicitValue?: number;
  post?: unknown;
}

export interface FloatDef extends CommonParams {
  readonly __kind: "float";
  default?: number;
  implicitValue?: number;
  post?: unknown;
}

export interface BooleanDef extends CommonParams, VariationParams {
  readonly __kind: "boolean";
  default?: boolean;
  implicitValue?: boolean;
}

export interface CountDef extends CommonParams, VariationParams {
  readonly __kind: "count";
}

export interface AppendStringDef extends CommonParams {
  readonly __kind: "append_string";
}

export interface AppendIntDef extends CommonParams {
  readonly __kind: "append_int";
}

export interface AppendFloatDef extends CommonParams {
  readonly __kind: "append_float";
}

export interface PositionalDef {
  readonly __kind: "positional";
  description?: string;
}

export interface RestDef {
  readonly __kind: "rest";
  description?: string;
}

export interface DashdashDef {
  readonly __kind: "dashdash";
}

export interface SubDef<O extends OptRecord = OptRecord> {
  readonly __kind: "sub";
  description?: string;
  aliases?: readonly string[];
  opts: O;
  requireCmd?: boolean;
  exclusive?: string[][];
  required?: string[];
  atLeastOne?: string[][];
  requires?: Array<{ source: string; target: string; msg?: string }>;
}

// Union of all combinator defs
export type AnyDef =
  | FlagDef
  | StringDef
  | IntDef
  | FloatDef
  | BooleanDef
  | CountDef
  | AppendStringDef
  | AppendIntDef
  | AppendFloatDef
  | PositionalDef
  | RestDef
  | DashdashDef
  | SubDef<any>;

/** A record mapping option names to combinator definitions. */
export type OptRecord = Record<string, AnyDef>;

// =============================================================================
// Combinator Factory Functions
// =============================================================================

export function flag(params: Omit<FlagDef, "__kind"> = {}): FlagDef {
  return { ...params, __kind: "flag" } as FlagDef;
}

export function string(params: Omit<StringDef, "__kind"> = {}): StringDef {
  return { ...params, __kind: "string" } as StringDef;
}

export function int(params: Omit<IntDef, "__kind"> = {}): IntDef {
  return { ...params, __kind: "int" } as IntDef;
}

export function float(params: Omit<FloatDef, "__kind"> = {}): FloatDef {
  return { ...params, __kind: "float" } as FloatDef;
}

export function boolean(params: Omit<BooleanDef, "__kind"> = {}): BooleanDef {
  return { ...params, __kind: "boolean" } as BooleanDef;
}

export function count(params: Omit<CountDef, "__kind"> = {}): CountDef {
  return { ...params, __kind: "count" } as CountDef;
}

export function appendString(params: Omit<AppendStringDef, "__kind"> = {}): AppendStringDef {
  return { ...params, __kind: "append_string" } as AppendStringDef;
}

export function appendInt(params: Omit<AppendIntDef, "__kind"> = {}): AppendIntDef {
  return { ...params, __kind: "append_int" } as AppendIntDef;
}

export function appendFloat(params: Omit<AppendFloatDef, "__kind"> = {}): AppendFloatDef {
  return { ...params, __kind: "append_float" } as AppendFloatDef;
}

export function positional(params: Omit<PositionalDef, "__kind"> = {}): PositionalDef {
  return { ...params, __kind: "positional" } as PositionalDef;
}

export function rest(params: Omit<RestDef, "__kind"> = {}): RestDef {
  return { ...params, __kind: "rest" } as RestDef;
}

export function dashdash(): DashdashDef {
  return { __kind: "dashdash" } as DashdashDef;
}

export function sub<O extends OptRecord>(
  params: Omit<SubDef<O>, "__kind">,
): SubDef<O> {
  return { ...params, __kind: "sub" } as SubDef<O>;
}

// =============================================================================
// Type Inference — Combinator Def -> Result Value Type
// =============================================================================

/** Map a single combinator definition to its result value type. */
export type InferValue<D extends AnyDef> =
  D extends FlagDef ? boolean :
  D extends BooleanDef ? boolean :
  D extends CountDef ? number :
  D extends IntDef ? number :
  D extends FloatDef ? number :
  D extends StringDef ? string :
  D extends AppendStringDef ? string[] :
  D extends AppendIntDef ? number[] :
  D extends AppendFloatDef ? number[] :
  D extends PositionalDef ? string | undefined :
  D extends RestDef ? string[] :
  D extends DashdashDef ? string[] :
  D extends SubDef<infer O> ? InferSub<O> | undefined :
  never;

/** Infer the result type of a subcommand's options (non-sub opts). */
type InferSubValues<O extends OptRecord> = {
  [K in keyof O as O[K] extends SubDef<any> ? never : K]: InferValue<O[K]>;
};

/** Infer the subcommand result, including nested sub results. */
type InferSub<O extends OptRecord> = InferSubValues<O> & {
  [K in keyof O as O[K] extends SubDef<any> ? K : never]: InferValue<O[K]>;
};

/** Infer the top-level parse result type from an OptRecord. */
export type InferResult<O extends OptRecord> = InferSub<O>;

// =============================================================================
// Schema -> JSON conversion (internal)
// =============================================================================

function defToJsonOpt(name: string, def: AnyDef): JsonOpt {
  const base: JsonOpt = { kind: def.__kind, name };

  if ("description" in def && def.description) base.description = def.description;
  if ("shorts" in def && def.shorts) base.shorts = def.shorts;
  if ("global" in def && def.global) base.global = def.global;
  if ("env" in def && def.env) base.env = def.env;
  if ("aliases" in def && def.aliases?.length) base.aliases = def.aliases;
  if ("visibility" in def && def.visibility) base.visibility = def.visibility;
  if ("default" in def && def.default !== undefined) base.default = def.default;
  if ("choices" in def && def.choices?.length) base.choices = def.choices;
  if ("implicitValue" in def && def.implicitValue !== undefined) base.implicit_value = def.implicitValue;
  if ("post" in def && def.post !== undefined) base.post = def.post;

  // Variation params
  if ("variationToggle" in def && def.variationToggle) base.variation_toggle = def.variationToggle;
  if ("variationTrue" in def && def.variationTrue) base.variation_true = def.variationTrue;
  if ("variationFalse" in def && def.variationFalse) base.variation_false = def.variationFalse;
  if ("variationReset" in def && def.variationReset) base.variation_reset = def.variationReset;
  if ("variationUnset" in def && def.variationUnset) base.variation_unset = def.variationUnset;

  // Subcommand
  if (def.__kind === "sub") {
    const subDef = def as SubDef<any>;
    base.kind = "command";
    base.opts = optsToJsonArray(subDef.opts);
    if (subDef.requireCmd) base.require_cmd = true;
    if (subDef.exclusive) (base as any).exclusive = subDef.exclusive;
    if (subDef.required) (base as any).required = subDef.required;
  }

  // Dashdash has no name
  if (def.__kind === "dashdash") {
    delete base.name;
  }

  return base;
}

function optsToJsonArray(opts: OptRecord): JsonOpt[] {
  return Object.entries(opts).map(([name, def]) => defToJsonOpt(name, def));
}

// =============================================================================
// Error Types
// =============================================================================

export class KuuParseError extends Error {
  readonly helpText: string;
  readonly tip?: string;
  readonly kind?: string;

  constructor(message: string, helpText: string, tip?: string, kind?: string) {
    super(message);
    this.name = "KuuParseError";
    this.helpText = helpText;
    this.tip = tip;
    this.kind = kind;
  }
}

export class KuuHelpRequested extends Error {
  readonly helpText: string;

  constructor(helpText: string) {
    super("Help requested");
    this.name = "KuuHelpRequested";
    this.helpText = helpText;
  }
}

// =============================================================================
// Parser
// =============================================================================

export interface ParserOptions<O extends OptRecord> {
  /** Top-level description shown in help. */
  description?: string;
  /** Option/subcommand definitions. */
  opts: O;
  /** Require a subcommand. */
  requireCmd?: boolean;
  /** Mutually exclusive option groups. */
  exclusive?: string[][];
  /** Required options. */
  required?: string[];
  /** At-least-one groups. */
  atLeastOne?: string[][];
  /** Dependency constraints. */
  requires?: Array<{ source: string; target: string; msg?: string }>;
  /** Environment variable prefix. */
  envPrefix?: string;
  /** Auto-bind env variables from option names. */
  autoEnv?: boolean;
  /** Path to WASM binary (override). */
  wasmPath?: string;
}

export interface KuuParser<O extends OptRecord> {
  /**
   * Parse CLI arguments. Throws KuuParseError on parse failure,
   * KuuHelpRequested when --help is used.
   */
  parse(args: string[], env?: Record<string, string>): Promise<InferResult<O>>;

  /**
   * Generate shell completion script.
   */
  completions(shell: "bash" | "zsh" | "fish", commandName: string): Promise<string>;
}

/**
 * Create a kuu parser from a declarative schema.
 *
 * @example
 * ```ts
 * const parser = kuu.parser({
 *   opts: {
 *     verbose: kuu.count({ shorts: 'v', global: true }),
 *     port: kuu.int({ default: 8080 }),
 *     host: kuu.string({ default: 'localhost' }),
 *     serve: kuu.sub({
 *       opts: {
 *         dir: kuu.positional(),
 *       },
 *     }),
 *   },
 * });
 *
 * const result = await parser.parse(process.argv.slice(2));
 * result.verbose;  // number
 * result.serve?.dir;  // string | undefined
 * ```
 */
export function parser<O extends OptRecord>(
  options: ParserOptions<O>,
): KuuParser<O> {
  const jsonOpts = optsToJsonArray(options.opts);

  function buildSchemaJson(args: string[], env?: Record<string, string>): string {
    const schema: JsonSchema = {
      version: 1,
      opts: jsonOpts,
      args,
    };
    if (options.description) schema.description = options.description;
    if (options.requireCmd) schema.require_cmd = true;
    if (options.exclusive) schema.exclusive = options.exclusive;
    if (options.required) schema.required = options.required;
    if (options.atLeastOne) schema.at_least_one = options.atLeastOne;
    if (options.requires) schema.requires = options.requires;
    if (options.envPrefix) schema.env_prefix = options.envPrefix;
    if (options.autoEnv) schema.auto_env = true;
    if (env) schema.env = env;
    return JSON.stringify(schema);
  }

  function buildCompletionSchemaJson(): string {
    const schema: Omit<JsonSchema, "args"> = {
      version: 1,
      opts: jsonOpts,
    };
    if (options.description) schema.description = options.description;
    if (options.envPrefix) schema.env_prefix = options.envPrefix;
    if (options.autoEnv) schema.auto_env = true;
    return JSON.stringify(schema);
  }

  function extractResult(raw: any): InferResult<O> {
    const result: any = { ...raw.values };

    // Recursively extract command results
    if (raw.command) {
      result[raw.command.name] = extractCommandResult(raw.command);
    }

    return result;
  }

  function extractCommandResult(cmd: any): any {
    const result: any = { ...cmd.values };
    if (cmd.command) {
      result[cmd.command.name] = extractCommandResult(cmd.command);
    }
    return result;
  }

  return {
    async parse(args: string[], env?: Record<string, string>): Promise<InferResult<O>> {
      const wasm = await loadWasm(options.wasmPath);
      const inputJson = buildSchemaJson(args, env);
      const outputJson = wasm.kuu_parse(inputJson);
      const output = JSON.parse(outputJson);

      if (output.ok) {
        return extractResult(output);
      }

      if (output.help_requested) {
        throw new KuuHelpRequested(output.help);
      }

      throw new KuuParseError(
        output.error,
        output.help ?? "",
        output.tip,
        output.kind,
      );
    },

    async completions(shell: "bash" | "zsh" | "fish", commandName: string): Promise<string> {
      const wasm = await loadWasm(options.wasmPath);
      const schemaJson = buildCompletionSchemaJson();
      return wasm.kuu_completions(schemaJson, shell, commandName);
    },
  };
}

// =============================================================================
// Convenience namespace-like export
// =============================================================================

const kuu = {
  parser,
  flag,
  string,
  int,
  float,
  boolean,
  count,
  appendString,
  appendInt,
  appendFloat,
  positional,
  rest,
  dashdash,
  sub,
  KuuParseError,
  KuuHelpRequested,
};

export default kuu;
