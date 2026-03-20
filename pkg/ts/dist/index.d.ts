/**
 * @kawaz/kuu — TypeScript DX layer for kuu CLI parser.
 *
 * Provides a declarative schema DSL that maps to the kuu WASM bridge's JSON protocol.
 * Type inference ensures parse results are fully typed.
 */
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
    requires?: Array<{
        source: string;
        target: string;
        msg?: string;
    }>;
}
export type AnyDef = FlagDef | StringDef | IntDef | FloatDef | BooleanDef | CountDef | AppendStringDef | AppendIntDef | AppendFloatDef | PositionalDef | RestDef | DashdashDef | SubDef<any>;
/** A record mapping option names to combinator definitions. */
export type OptRecord = Record<string, AnyDef>;
export declare function flag(params?: Omit<FlagDef, "__kind">): FlagDef;
export declare function string(params?: Omit<StringDef, "__kind">): StringDef;
export declare function int(params?: Omit<IntDef, "__kind">): IntDef;
export declare function float(params?: Omit<FloatDef, "__kind">): FloatDef;
export declare function boolean(params?: Omit<BooleanDef, "__kind">): BooleanDef;
export declare function count(params?: Omit<CountDef, "__kind">): CountDef;
export declare function appendString(params?: Omit<AppendStringDef, "__kind">): AppendStringDef;
export declare function appendInt(params?: Omit<AppendIntDef, "__kind">): AppendIntDef;
export declare function appendFloat(params?: Omit<AppendFloatDef, "__kind">): AppendFloatDef;
export declare function positional(params?: Omit<PositionalDef, "__kind">): PositionalDef;
export declare function rest(params?: Omit<RestDef, "__kind">): RestDef;
export declare function dashdash(): DashdashDef;
export declare function sub<O extends OptRecord>(params: Omit<SubDef<O>, "__kind">): SubDef<O>;
/** Map a single combinator definition to its result value type. */
export type InferValue<D extends AnyDef> = D extends FlagDef ? boolean : D extends BooleanDef ? boolean : D extends CountDef ? number : D extends IntDef ? number : D extends FloatDef ? number : D extends StringDef ? string : D extends AppendStringDef ? string[] : D extends AppendIntDef ? number[] : D extends AppendFloatDef ? number[] : D extends PositionalDef ? string | undefined : D extends RestDef ? string[] : D extends DashdashDef ? string[] : D extends SubDef<infer O> ? InferSub<O> | undefined : never;
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
export declare class KuuParseError extends Error {
    readonly helpText: string;
    readonly tip?: string;
    readonly kind?: string;
    constructor(message: string, helpText: string, tip?: string, kind?: string);
}
export declare class KuuHelpRequested extends Error {
    readonly helpText: string;
    constructor(helpText: string);
}
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
    requires?: Array<{
        source: string;
        target: string;
        msg?: string;
    }>;
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
export declare function parser<O extends OptRecord>(options: ParserOptions<O>): KuuParser<O>;
declare const kuu: {
    parser: typeof parser;
    flag: typeof flag;
    string: typeof string;
    int: typeof int;
    float: typeof float;
    boolean: typeof boolean;
    count: typeof count;
    appendString: typeof appendString;
    appendInt: typeof appendInt;
    appendFloat: typeof appendFloat;
    positional: typeof positional;
    rest: typeof rest;
    dashdash: typeof dashdash;
    sub: typeof sub;
    KuuParseError: typeof KuuParseError;
    KuuHelpRequested: typeof KuuHelpRequested;
};
export default kuu;
//# sourceMappingURL=index.d.ts.map