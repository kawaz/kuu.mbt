/**
 * @kawaz/kuu — TypeScript DX layer for kuu CLI parser.
 *
 * Provides a declarative schema DSL that maps to the kuu WASM bridge's JSON protocol.
 * Type inference ensures parse results are fully typed.
 */
import { readFile } from "node:fs/promises";
let cachedExports = null;
async function loadWasm(wasmPath) {
    if (cachedExports)
        return cachedExports;
    const resolvedPath = wasmPath ??
        process.env.KUU_WASM_PATH ??
        new URL("../../../_build/wasm-gc/release/build/wasm/wasm.wasm", import.meta.url).pathname;
    const wasmBytes = await readFile(resolvedPath);
    const { instance } = await WebAssembly.instantiate(wasmBytes, {}, 
    // @ts-expect-error -- WASM-GC builtins not in TS lib types yet
    { builtins: ["js-string"], importedStringConstants: "_" });
    cachedExports = instance.exports;
    return cachedExports;
}
// =============================================================================
// Combinator Factory Functions
// =============================================================================
export function flag(params = {}) {
    return { ...params, __kind: "flag" };
}
export function string(params = {}) {
    return { ...params, __kind: "string" };
}
export function int(params = {}) {
    return { ...params, __kind: "int" };
}
export function float(params = {}) {
    return { ...params, __kind: "float" };
}
export function boolean(params = {}) {
    return { ...params, __kind: "boolean" };
}
export function count(params = {}) {
    return { ...params, __kind: "count" };
}
export function appendString(params = {}) {
    return { ...params, __kind: "append_string" };
}
export function appendInt(params = {}) {
    return { ...params, __kind: "append_int" };
}
export function appendFloat(params = {}) {
    return { ...params, __kind: "append_float" };
}
export function positional(params = {}) {
    return { ...params, __kind: "positional" };
}
export function rest(params = {}) {
    return { ...params, __kind: "rest" };
}
export function dashdash() {
    return { __kind: "dashdash" };
}
export function sub(params) {
    return { ...params, __kind: "sub" };
}
// =============================================================================
// Schema -> JSON conversion (internal)
// =============================================================================
function defToJsonOpt(name, def) {
    const base = { kind: def.__kind, name };
    if ("description" in def && def.description)
        base.description = def.description;
    if ("shorts" in def && def.shorts)
        base.shorts = def.shorts;
    if ("global" in def && def.global)
        base.global = def.global;
    if ("env" in def && def.env)
        base.env = def.env;
    if ("aliases" in def && def.aliases?.length)
        base.aliases = def.aliases;
    if ("visibility" in def && def.visibility)
        base.visibility = def.visibility;
    if ("default" in def && def.default !== undefined)
        base.default = def.default;
    if ("choices" in def && def.choices?.length)
        base.choices = def.choices;
    if ("implicitValue" in def && def.implicitValue !== undefined)
        base.implicit_value = def.implicitValue;
    if ("post" in def && def.post !== undefined)
        base.post = def.post;
    // Variation params
    if ("variationToggle" in def && def.variationToggle)
        base.variation_toggle = def.variationToggle;
    if ("variationTrue" in def && def.variationTrue)
        base.variation_true = def.variationTrue;
    if ("variationFalse" in def && def.variationFalse)
        base.variation_false = def.variationFalse;
    if ("variationReset" in def && def.variationReset)
        base.variation_reset = def.variationReset;
    if ("variationUnset" in def && def.variationUnset)
        base.variation_unset = def.variationUnset;
    // Subcommand
    if (def.__kind === "sub") {
        const subDef = def;
        base.kind = "command";
        base.opts = optsToJsonArray(subDef.opts);
        if (subDef.requireCmd)
            base.require_cmd = true;
        if (subDef.exclusive)
            base.exclusive = subDef.exclusive;
        if (subDef.required)
            base.required = subDef.required;
    }
    // Dashdash has no name
    if (def.__kind === "dashdash") {
        delete base.name;
    }
    return base;
}
function optsToJsonArray(opts) {
    return Object.entries(opts).map(([name, def]) => defToJsonOpt(name, def));
}
// =============================================================================
// Error Types
// =============================================================================
export class KuuParseError extends Error {
    helpText;
    tip;
    kind;
    constructor(message, helpText, tip, kind) {
        super(message);
        this.name = "KuuParseError";
        this.helpText = helpText;
        this.tip = tip;
        this.kind = kind;
    }
}
export class KuuHelpRequested extends Error {
    helpText;
    constructor(helpText) {
        super("Help requested");
        this.name = "KuuHelpRequested";
        this.helpText = helpText;
    }
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
export function parser(options) {
    const jsonOpts = optsToJsonArray(options.opts);
    function buildSchemaJson(args, env) {
        const schema = {
            version: 1,
            opts: jsonOpts,
            args,
        };
        if (options.description)
            schema.description = options.description;
        if (options.requireCmd)
            schema.require_cmd = true;
        if (options.exclusive)
            schema.exclusive = options.exclusive;
        if (options.required)
            schema.required = options.required;
        if (options.atLeastOne)
            schema.at_least_one = options.atLeastOne;
        if (options.requires)
            schema.requires = options.requires;
        if (options.envPrefix)
            schema.env_prefix = options.envPrefix;
        if (options.autoEnv)
            schema.auto_env = true;
        if (env)
            schema.env = env;
        return JSON.stringify(schema);
    }
    function buildCompletionSchemaJson() {
        const schema = {
            version: 1,
            opts: jsonOpts,
        };
        if (options.description)
            schema.description = options.description;
        if (options.envPrefix)
            schema.env_prefix = options.envPrefix;
        if (options.autoEnv)
            schema.auto_env = true;
        return JSON.stringify(schema);
    }
    function extractResult(raw) {
        const result = { ...raw.values };
        // Recursively extract command results
        if (raw.command) {
            result[raw.command.name] = extractCommandResult(raw.command);
        }
        return result;
    }
    function extractCommandResult(cmd) {
        const result = { ...cmd.values };
        if (cmd.command) {
            result[cmd.command.name] = extractCommandResult(cmd.command);
        }
        return result;
    }
    return {
        async parse(args, env) {
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
            throw new KuuParseError(output.error, output.help ?? "", output.tip, output.kind);
        },
        async completions(shell, commandName) {
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
//# sourceMappingURL=index.js.map