# Kuu Design Document

> English | [日本語](./DESIGN-ja.md)

## What is kuu

A CLI parser engine that structurally resolves ambiguity through speculative execution and optimal interpretation. Written in MoonBit.

Each combinator speculatively tries the range it can consume, and the most reasonable interpretation is adopted. All `OptKind`s are unified as `initial + ReduceCtx reducer`. The consumption loop knows no types and holds no name resolution. All complexity is pre-expanded at the combinator layer.

### Comparison with other CLI parsers

| Aspect | Typical parsers (clap, cobra, etc.) | kuu |
|------|------|-----|
| Parse model | Look up by name, then process value (2 steps) | Each node self-decides (speculative execution + longest match) |
| `-abc` combined-shorts decomposition | Dedicated decomposition logic | Converted to ExactNode by an install node. No special branch in the main loop |
| `--color` / `--color=always` coexistence | Individual handling such as num_args | Resolved naturally by longest match in make_or_node |
| choices validation | Validation step after parsing | Instantly decided as Accept/Reject inside ExactNode |
| Ambiguity | Priority decided by definition order, or not detected | Ties among candidates are detected and reported as an ambiguous error |

### Difference from PEG (ordered choice)

PEG adopts the first matching alternative. kuu speculatively executes all candidates and picks the optimal interpretation. It is order-independent, and ambiguity (tied candidates) can also be detected.

---

## Design principles

1. **All OptKinds unified as initial + reducer** — Flag, Count, Single, Append, choices, and implicit_value all share the same structure
2. **Traverse a flat list of ExactNodes via speculative execution + longest match** — The consumption loop knows no types and holds no name resolution. Complexity is pushed out to the combinator layer
3. **Separate complexity into 4 layers inside the core** — Core → Pattern → Convention → Sugar. Each layer is unified around the single operation of generating and registering ExactNodes
4. **Opt[T] is a thin reference type** — id + name + accessor + parsed. Value storage is hidden behind the closure bundle of ValCell + Accessor
5. **Help is subordinate; the core is primary** — Do not distort the core design for the sake of display metadata (OptMeta)
6. **Think in combinations of existing parts** — Before adding a new field or type, consider whether it can be solved by combining existing types and closures
7. **try_reduce returns a TryResult** — A three-valued Accept/Reject/Error. The meaning of Reject vs Error differs before and after name resolution
8. **Compose String→T preprocessing type-safely with FilterChain** — Kleisli composition with map/validate/parse + then. Filters are pure functions
9. **Keep the space-separated form** — `--name value` is the basic form. `--name=value` is supported transparently via an install node
10. **One-way dependency: dx → core** — dx does not push requirements back into core nor distort the core design. core does not know about dx

---

## Combinators and API

### Sugar layer — user-facing combinators

Type-specialized combinators. `name~` is directly tied to generating `--name` or `<NAME>`, so it is a required parameter (no default):

- `flag()`, `string()`, `int()`, `float()`, `boolean()`, `count()` — basic types
- `file()` — file-path specialized. Three-value pattern (unspecified / flag only / value given) via `default` + `default_path` + `implicit_value`
- `append_string()`, `append_int()`, `append_float()` — array accumulation
- `custom[T : Show]()`, `append[T]()` — general-purpose types. string/int/float/boolean are sugar over custom (DR-0025)
- `cmd()`, `sub()` — subcommands
- `positional()`, `rest()` — positional arguments (the `name` is used for the `<NAME>` display in help)
- `serial()`, `never()` — no `name` parameter

### Unification: every OptKind = initial + reducer

Flags, value options, counters, and array accumulators are all unified internally into the same structure:

| Kind | initial | reducer behavior |
|------|---------|-------------------|
| flag | `false` | `_ => true` (name alone determines the value) |
| count | `0` | `current + 1` (increment per occurrence) |
| string | `default` | `Value(Some(s)) => s` (take the next argument as the value) |
| append | `[]` | `Value(Some(s)) => acc + [s]` (append to array) |
| choices | `default` | Accept if the value is in the choices, otherwise Reject |
| implicit_value | `default` | No value → implicit; value given → that value (longest match via make_or_node) |

The reducer signature is `(ReduceCtx[T]) -> T?!ParseError`. Three return forms:
- `Some(T)`: consumption succeeded. Write to the `Ref[T]`
- `None`: does not match. Dropped during candidate selection in the consumption loop
- `raise ParseError`: the name matched but the value was invalid. Error immediately

`ReduceCtx` is a struct wrapper. Since MoonBit closures cannot take labeled/optional arguments, this is a design decision to allow future extension (adding fields) without breakage (DR-0008).

### Subcommands

```moonbit
let p = Parser::new()
let verbose = p.flag(name="verbose", global=true)  // effective in all scopes

// sub(): returns the child parser directly (DR-0026)
let serve = p.sub(name="serve", description="Start server")
let port = serve.int(name="port", default=8080)

// cmd(): setup-callback style
let deploy_cmd = p.cmd(name="deploy", setup=fn(child) {
  let target = child.string(name="target", default="")
})

let result = try? p.parse(args)
verbose.get()              // T? — global, so effective in any scope
result.child("serve")      // ParseResult? — subcommand result
port.get()                 // T? — cobra-style access
```

- Subcommands at the same level are always uniquely resolved by the consumption loop (no exclusivity machinery needed)
- Nodes with `global=true` propagate to child parsers. Order-independent (lazy synchronization)

### Positional arguments

```moonbit
let file = p.positional(name="FILE")                     // fixed-length
let paths = p.rest(name="PATHS", stop_before=["--"])     // variable-length
let extras = p.dashdash()                                 // collect everything after --
```

Serial behavior is realized by sequential consumption from the positionals array. When `is_rest=true`, the same handler is reused repeatedly. A positional's handler Rejects arguments with the `--` prefix.

### Constraints (post_hooks based)

```moonbit
p.exclusive([json_opt, csv_opt, yaml_opt])  // exclusive: at most one
p.at_least_one([json_opt, csv_opt])         // at least one required
p.required(output_opt)                      // single required
p.require_cmd()                             // subcommand required
p.requires(target_opt, source~=dep_opt)     // dependency: source is required when target is used
```

All are implemented as post_hooks. A dedicated hook-pipeline infrastructure would be YAGNI.

### Environment variable integration (DR-0041)

Each combinator's `env~` parameter specifies the environment variable name, and `Parser::parse(args, env~)` receives the env map. Priority is CLI > environment variable > default:

```moonbit
let p = Parser::new()
p.env_prefix("MYAPP")  // set a prefix
let port = p.int(name="port", default=8080, env="PORT")

// MYAPP_PORT is consulted thanks to env_prefix
let result = try? p.parse(args, env={"MYAPP_PORT": "3000"})
port.get()  // Some(3000)
```

- `Parser::env_prefix(prefix)` — prefix the environment variable name. `env="PORT"` → consulted as `MYAPP_PORT`
- Automatic subcommand nesting — `MYAPP` → `MYAPP_SERVE` → `MYAPP_SERVE_DB` (concatenate uppercased subcommand names)
- Reflected in help as `[env: MYAPP_PORT]` (with prefix)
- `Parser::auto_env(enabled)` — auto-bind by converting hyphens to underscores and uppercasing the opt name (e.g. `--port` → `PORT`). Hidden opts are excluded. An explicit `env~` takes precedence. Composable with `env_prefix`. Inherited by subcommands

### Reading values

```moonbit
opt.get()              // T? — cobra-style. Recommended
parser.get(opt)        // T? — None before parse, Some(T) after parse
result.get(opt)        // T? — delegates to parser.get(opt)
result.child("serve")  // ParseResult? — subcommand navigation
result.at(0)           // ParseResult? — positional navigation
```

### FilterChain — type-safe transformation pipeline via Kleisli composition (DR-0016)

A mechanism that separates `String → T` conversion (applied before the reducer) into composable, type-safe parts.

```moonbit
struct FilterChain[A, B] {
  run : (A) -> B!ParseError
}

// Kleisli composition: connect A→B and B→C into A→C
fn then[A, B, C](self : FilterChain[A, B], next : FilterChain[B, C]) -> FilterChain[A, C]
```

Three constructors:

```moonbit
Filter::map(f)       // pure transform: A → B (cannot fail)
Filter::validate(f)  // validation: A → A (ParseError on failure; type unchanged)
Filter::parse(f)     // transform + may fail: A → B (ParseError on failure)
```

**Accumulator** — separating transformation from accumulation:

```moonbit
type Accumulator[T, U] = (T, U) -> T

fn make_reducer[T, U](
  pre   : FilterChain[String, U],  // String → U conversion
  accum : Accumulator[T, U],       // merge U into T
) -> (ReduceCtx[T]) -> T?!ParseError
```

This separation realizes a "each side is a list and accumulation concatenates them" pattern that the existing append could not express:

| Kind | pre (String → U) | accum (T, U) → T |
|------|-------------------|-------------------|
| single | `parse_int` etc. | `(_, u) => u` (overwrite) |
| append | `parse_int` etc. | `(acc, u) => acc + [u]` (append) |
| join family | `split(",").then(each(parse_int))` | `(acc, xs) => acc + xs` (concatenate) |

Built-in filters (32):
- String transforms: `trim`, `to_lower`, `to_upper`, `trim_start`, `trim_end`, `replace(from, to)`, `replace_all(from, to)`
- String validation: `non_empty`, `starts_with(prefix)`, `ends_with(suffix)`, `contains(substr)`, `min_length(n)`, `max_length(n)`, `min_codepoints(n)`, `max_codepoints(n)`, `min_graphemes(n)`, `max_graphemes(n)`
- Numeric parse: `parse_int`, `parse_float`, `parse_bool`
- Numeric validation: `in_range(min, max)`, `float_in_range(min, max)`, `positive`, `non_negative`
- Numeric transform: `clamp(min, max)`
- Choice: `one_of(allowed)`
- Array: `each(inner_filter)`, `split(sep)`, `mergeable_list(base, separator)` — base-relative changes via `+/-/...` modifiers (DR-0023)
- Regular expression: `regex_match(pattern)`, `regex_replace(pattern, replacement)`, `regex_split(pattern)`

**Purity constraint (DR-0037)**: Filters (pre/post/accum) must be pure functions. Value state is managed via `Ref[T]`; filters are only responsible for input-to-output transformation. This constraint allows filter closure references to be safely shared on clone (a prerequisite for the orthogonal primitives).

### Composition pattern — orthogonal primitives (DR-0037)

Three orthogonal primitives compose into all of alias / variation / proxy:

| Primitive | Concern | Role |
|-------------|--------|------|
| `clone(opt, name)` | identity | structural copy (independent cell, shared NodeTemplate factory) |
| `link(target, source~)` | value | value forwarding via post_hook (controlled by `propagate_set~` for committed propagation) |
| `adjust(opt, ...)` | behavior | apply a filter chain via post_hook |

Composition patterns:

| Pattern | Expression | Identity | Value | Behavior |
|---------|-----|:---:|:---:|:---:|
| alias | `link(clone(opt, name), opt)` | new | forwarded | same |
| variation | `adjust(alias(opt, name), ...)` | new | forwarded | changed |
| derived | `adjust(clone(opt, name), ...)` | new | independent | changed |
| stricter | `adjust(opt, after_post=...)` | same | same | changed |

> **Note**: In the implementation, alias is not literally a composition of `link(clone(...), ...)`, but a dedicated implementation that shares the Accessor while keeping is_set independent. link performs value forwarding from source to target via a post_hook. The above patterns hold as the conceptual orthogonal decomposition.

#### Variation — toggle / reset patterns

All generate ExactNodes of the form `--{prefix}-{name}`:

| Variation | Meaning | Use case |
|-----------|------|------|
| `Toggle(p)` | `!current` | `--no-verbose`: invert a Bool |
| `True(p)` | always `true` | idempotent enable |
| `False(p)` | always `false` | idempotent disable |
| `Reset(p)` | `cell=default, committed=true` | restore the default (treated as explicitly set) |
| `Unset(p)` | `cell=default, committed=false` | fully restore to the unspecified state |

All combinators default to `variations=[]` (no automatic `--no-` is generated). Use sugar parameters (`variation_toggle?` etc.) for explicit specification.

#### Implemented composite combinators

- **alias** — `p.make_alias(name, target)`: shared value + independent is_set alias. Supports chained aliases (an alias of an alias propagates committed up to the root). A global alias propagates into child parsers
- **deprecated** — `p.deprecated(name, target, msg)`: alias + post_hook approach. After parsing, `deprecated_warnings()` returns `Array[(name, msg)]`. Supports recursive propagation from subcommands to the parent
- **clone** — `p.clone(name, target)`: structural copy. Has an independent ValCell while sharing the NodeTemplate factory. Holds an independent value via a save/restore pattern without affecting the target's cell
- **link** — `p.link(target, source~)`: value forwarding. After parsing, copies the source's value into the target. The `propagate_set~` knob controls committed propagation
- **adjust** — `p.adjust(target, after_post~)`: value transformation. After parsing, transforms the target's value via a FilterChain. Applied only if the target was set

---

## Multi-language engine foundation (vision)

> The following is a design vision, not a fixed decision. See each DR for details.

The core is kept as a thin parse engine based on pure functions; language-specific type-safe access is provided in each language's DX layer. The dependency direction is one-way: `dx → core`. The core does not know about dx.

### 4-layer architecture for the multi-language foundation (DR-0036 vision)

```
DX API (per language)  ← type-safe API in each language's idiom
  ↓
KuuCore (per language) ← hides JSON plumbing. Mediates callbacks. Abstracts the backend
  ↓
Bridge                 ← connection layer with core
  ├ Layer 2a: WASM transport  (V8/wasmtime. in-process)
  └ Layer 2b: Native CLI transport (kuu-cli. stdin/stdout JSON)
  ↓
Core (MoonBit)         ← Layer 1: pure parse engine
```

### Delivery formats for each language (under consideration)

The mechanism by which each language uses the core is not yet fixed. The optimal approach differs per language and also depends on the maturity of the runtime (DR-0033, DR-0046, DR-0047):

| Approach | Summary | Status |
|------|------|------|
| V8 WASM-GC | Load directly from JS/TS | PoC exists (src/wasm/). JSON schema → core → JSON result |
| wasmtime embedding | Load a WASM-GC binary from Rust, Python | wasmtime v27+ supports WASM-GC. PoC not started |
| Native CLI (kuu-cli) | stdin/stdout JSON protocol. exec from any language | PoC in progress (src/cli/). Shares the same protocol as the WASM bridge |
| Node.js subprocess | Go, Swift, etc. JSON bridge | PoC exists. Process startup overhead |
| MoonBit native → C FFI | Connect from any language via C FFI | Waiting for the MoonBit native backend to mature |
| Reimplement the core | Native implementations in each language | Quality assurance via shared test cases (concept) |

### MoonBit DX layer (DR-0042, implemented)

Struct-first approach. Two phases with Parseable trait + FieldRegistry + parse_into:

1. **register phase**: The user's struct implements the `Parseable` trait and `register(self, registry)` registers each field. The registry registers options into the core Parser while accumulating `set` closures
2. **apply phase**: After a successful parse, the accumulated `set` closures are executed in order to inject values into the user's struct. They are not applied on parse failure (transactional)

Thanks to the `set` pattern (formerly `apply_fn`), the core-side `Ref[T]` does not leak into the DX layer.

### kuu-cli — Native CLI Transport (DR-0059, in progress)

The Native transport of Layer 2b. A single binary built with MoonBit's native target (C backend) that exposes kuu core's parsing functionality via stdin/stdout JSON protocol v1. It shares the same parsing logic and protocol with the WASM bridge (Layer 2a).

**Characteristics**:

- **Self-hosting**: kuu-cli's own CLI arguments are parsed by kuu core (the `parse`, `completions`, `validate` subcommands plus the `--help`, `--version` global options)
- **C FFI**: Since MoonBit has no stdin/argv API, stdin reading, file reading, and argv retrieval are realized via C FFI. On macOS, argv is obtained via `_NSGetArgc`/`_NSGetArgv`
- **UTF-8 ↔ UTF-16 conversion**: At the C FFI boundary, UTF-8 byte sequences and MoonBit String (UTF-16 LE) are converted in both directions
- **embed pattern support** (DR-0047): Each language's DX layer embeds the kuu-cli binary, so it looks like an ordinary library to users
- **Standalone command** (DR-0057): Directly usable from shell scripts, Makefiles, and CI/CD

### TypeScript DX layer (pkg/ts/, PoC)

A PoC implementation with a WASM-GC wrapper + Schema DSL + type inference. Declare a schema with `kuu()`, and `InferResult<O>` automatically derives the parse-result type:

- **Schema DSL**: Combinator factories such as `flag()`, `stringOpt()`, `intOpt()`, `count()`, `sub()`, `positional()`, `rest()`, `dashdash()`
- **InferResult type inference**: required → non-optional, choices `as const` → literal union type, subcommand → discriminated union
- **Direct WASM-GC loading**: Uses V8's WASM-GC builtins + js-string. Calls kuu core via the JSON protocol
- 30 tests passing. Not yet published to npm

### AST portability of Opt definitions (DR-0029, DR-0030 vision)

Opt definitions are pure data (no closures at the definition level). The vision is to serialize them to JSON and ferry them to other languages:
- Static definitions (flag, string, int, count, append, choices, implicit_value, variations, aliases): fully representable in JSON
- Dynamic parts (custom[T], post filters): represented as undefined slots to be implemented on the target language side. The type system guides completion

---

## Speculative-execution + longest-match parse model

### 4-layer structure inside the parser engine

```
Sugar:       flag(), string(), custom[T](), cmd(), ...
Convention:  expand_and_register — expand name + aliases + shorts + variations
Pattern:     make_or_node — unify composite nodes via longest match
Core:        ExactNode (try_reduce) + OC/P consumption loop + orthogonal primitives (clone, link, adjust)
```

Each layer is unified around the single operation of **generating an ExactNode and registering it with the Parser**.

#### Core layer

**ExactNode** — pair of an exact-match name and a speculative-execution function:

```moonbit
pub(all) struct ExactNode {
  name : String                          // exact-match name ("--verbose", "--no-verbose", "serve")
  needs_value : Bool                     // if true, the next argument is consumed as the value
  try_reduce : (Array[String], Int) -> TryResult  // speculative execution
  reset : () -> Unit                     // reset to the initial value
}
```

**TryResult** — three-valued judgment of speculative execution:

```moonbit
pub(all) enum TryResult {
  Accept(consumed~ : Int, commit~ : () -> Unit)  // consumable. commit() finalizes the value
  Reject                                          // does not match (try other candidates)
  Error(ParseError)                               // name matched but value invalid (error immediately)
}
```

**Important**: Accept returns the consumed count and a commit closure, but **commit does not write the value until it is called**. This is the heart of speculative execution — "trying whether it can eat" and "actually eating" are separated. commit() is only invoked once the longest-match winner is finalized.

**Using Reject and Error correctly** changes meaning before and after name resolution (DR-0015):
- Before name resolution (e.g. positional candidate selection): type mismatch → `Reject` (try another candidate)
- After name resolution (e.g. `--port abc` with port already decided): type conversion failure on the value → `Error` (do not swallow)

#### Pattern layer

**make_or_node** — a composite node that unifies multiple child ExactNodes via longest match. It captures child nodes in a closure, so no structural change to ExactNode is needed:

```
make_or_node([
  make_soft_value_node("--color", ...),     // consumed=2 (with value)
  make_implicit_flag_node("--color", ...),  // consumed=1 (implicit value)
])
→ call try_reduce on all children → pick the candidate with the longest consumed
→ if tied, ambiguous error
```

The coexistence of choices + implicit_value is resolved naturally by longest match in make_or_node.

#### Convention layer

**expand_and_register** — expands a single combinator declaration into multiple ExactNodes and registers them:

```
flag(name="verbose", shorts="v", variation_toggle="no")
→ expand_and_register generates:
  - "--verbose" (flag_node)
  - "--no-verbose" (toggle_node: !current)
  - "-v" (short alias)
→ three independent ExactNodes are pushed onto Parser.nodes
```

Once the Convention layer has finished expansion, **the consumption loop need not contain any name-resolution logic**. `--no-verbose` is an independent ExactNode; there is no need for runtime analysis such as prefix stripping.

### Tokenizer (cross-cutting preprocessing) — install nodes

Before the consumption loop, install nodes that convert special argument forms into ordinary ExactNodes are constructed at the top of parse_raw (DR-0017). As a result, **special branches are completely eliminated from the main loop of parse_raw**:

| install node | What it transforms | Details |
|---------------|---------|------|
| `install_eq_split_node` | `--name=value` → split and delegate to existing nodes | A `consumed≥2` gate prevents false matches against implicit_value |
| `install_short_combine_node` | `-abc` → delegate each character to a node | value trial → flag trial fallback. With type info, `-vA1B1` can also be decomposed |
| `install_separator_node` | `--` → forward subsequent args to positionals | auto-registered at initialization (`dashdash=true` by default) |

**Heart of the matter**: Because each ExactNode can self-decide its consumability, the decomposition of combined short options is expressed as recursive `try_reduce` calls inside an install node (DR-0015, DR-0039). Type information (`needs_value`, consumed count) is used directly in backtracking decisions.

### OC/P 2-phase parse (DR-0034)

The consumption loop consists of two phases:

**OC Phase (Option/Command)** — traverse ExactNodes + longest match:

```
while pos < args.length:
  call try_reduce(args, pos) on every ExactNode
  → pick the Accept candidate with the largest consumed
    → multiple maxima: raise ParseError(ambiguous)
    → exactly one maximum: commit() + pos += consumed
    → zero Accepts:
      → if there is a greedy positional, try to consume it
      → otherwise accumulate into unclaimed
```

**P Phase (Positional)** — assign unclaimed arguments to positionals:

```
concatenate force_unclaimed (everything after --) + unclaimed
skip greedy positionals (already consumed in OC Phase)
consume non-greedy positionals from the front:
  → is_rest=false: consume one and advance to the next positional
  → is_rest=true: keep reusing the same handler
if anything is left over: raise ParseError("unexpected argument")
```

**Why two phases**: positionals are non-greedy by default (P Phase only). This structurally prevents the "typoed option name gets swallowed by a positional" problem. Only positionals with an explicit `greedy=true` are consumed in the OC Phase. We do not depend on heuristics such as `has_prefix("--")`.

### Scope transition (subcommands)

When a Command matches:
- The child parser's parse is recursively invoked over the remaining args (scope replacement)
- Nodes with `global=true` propagate into the child parser's nodes/global_nodes (lazy synchronization: globals added after the cmd definition are also synced at try_reduce time)
- The cmd's ExactNode returns `Accept(consumed=args.length()-pos)`, and the child consumes everything that remains

---

## Value retention and type safety

### Type erasure problem and solution

A CLI parser must manage options of different types — `Opt[Bool]`, `Opt[Int]`, `Opt[String]`, `Opt[Array[String]]`, and so on — in a single array, and must traverse them without knowing the types. MoonBit has no dynamic dispatch like Rust's `dyn Trait`, nor a root type like Java's `Object`.

**Solution: type erasure via closures + sharing of ValCell/Accessor**

Each combinator creates a `ValCell[T]` internally and obtains an `Accessor[T]` (a bundle of closures) from it. **ExactNode and Opt[T] operate on the same ValCell**:

```
inside a combinator (e.g. string):
  let valcell : ValCell[String] = ValCell::new(default)
  let acc : Accessor[String] = valcell.accessor()

  ExactNode.try_reduce closure ─→ writes via acc.set(v) (type-erased view: does not know T)
  Opt[T].accessor ──────────────→ reads via acc.get() (typed view: returns as T)
```

- **Type-erased view**: ExactNode's `try_reduce : (Array[String], Int) -> TryResult` has no type parameter. The commit closure calls `acc.set(parsed_value)`, but ExactNode itself does not know it is a `ValCell[String]`
- **Typed view**: `Opt[String].accessor.get : () -> String` reads from the same `ValCell` as a `String`

No downcast required. No intermediate data structure such as a ResultMap is needed. Type safety is guaranteed at compile time.

### Opt[T] — thin reference type

```moonbit
pub(all) struct Opt[T] {
  id : Int                    // unique ID (assigned by Parser.next_id)
  name : String               // option name ("--verbose", etc.)
  priv accessor : Accessor[T] // unified interface for reading/writing/state of the value
  parsed : Ref[Bool]          // reference to Parser.parsed (true when parsing completes)
  priv used : () -> Bool      // whether this Opt's name was used (normal=committed; alias/clone=independent)
}
```

The user retrieves the value via `opt.get() -> T?`. Before parsing it is `None`; after parsing it is `Some(T)`. `opt.is_set() -> Bool` tells whether it was explicitly specified.

Opt is a thin reference type. initial / reducer / meta are captured in closures inside the combinator and are not part of Opt itself. The internal `Accessor[T]` is the closure bundle generated from a ValCell and provides the five operations get/set/set_value/set_commit/reset (DR-0048 separates is_set into Opt.used). Since it shares the same ValCell with ExactNode's try_reduce/commit, type safety is statically guaranteed.

### ParseResult — hierarchical navigation

```moonbit
pub(all) struct ParseResult {
  kind : ParseResultKind      // One | Map_(children) | List_(positionals)
  parser : Parser             // Parser for this scope
}
```

`child(key)` accesses a subcommand's result, and `at(i)` accesses a positional result. Both are sugar over the primitives (`as_map` / `as_list`).

### Lazy[T] — values with deferred evaluation

```moonbit
pub(all) enum Lazy[T] {
  Val(T)         // immediate value
  Thunk(() -> T) // deferred evaluation (runtime-dependent initial value)
}
```

Used to express values that are evaluated only at parse time, such as the default for implicit_value or a choices + implicit combination.

### ValCell/Accessor separation (DR-0045)

ValCell[T] encapsulates the value (cell), state (committed), and default value (default_val). Accessor[T] provides the operation interface as a bundle of closures:

- **Accessor[T]**: five operations — get/set/set_value/set_commit/reset (purely value operations, DR-0048)
  - `set(v)` = `set_value(v)` + `set_commit()`: updates both the value and committed
  - `set_value(v)`: sets only the value. committed unchanged
  - `set_commit()`: sets only the committed mark. value unchanged
  - `reset()`: resets both value and committed (value = default, committed = false)
- **Opt.used**: a closure that indicates whether this Opt's name was used (DR-0048). Normally equal to `vc.committed`; for alias/clone it is an independent `opt_used` flag

Thanks to this separation, clone has its own ValCell + its own Accessor, while alias shares the target's Accessor but keeps used independent — both expressed naturally.

### Visibility — display control

```moonbit
pub(all) enum Visibility {
  Visible      // default. shown in help ✓, in completions ✓
  Advanced     // not in help ✗, in completions ✓ (for power users)
  Hidden       // not in help ✗, not in completions ✗
}
```

Specified via the `visibility~` parameter on every combinator as the `visibility` field of OptMeta. It replaces the old `hidden: Bool` and provides three-level display control. `auto_env` excludes `Hidden` (compatible with the previous hidden behavior).

### Completion candidate generation

```moonbit
pub(all) struct CompletionCandidate {
  value : String        // completion candidate string ("--verbose", "-v", "serve", etc.)
  description : String  // description (taken from OptMeta.help)
  group : String        // group ("Options", "Global Options", "Commands")
}
```

- `Parser::generate_completions()` — returns all candidates as `Array[CompletionCandidate]`. Excludes `Hidden`; includes `Advanced`
- `Parser::generate_completion_script(shell~, command_name~)` — generates a bash/zsh/fish shell completion script. Internally calls `generate_completions()` and converts to the shell-specific format

---

## Package layout

```
src/
  core/              # Layer 1: parse engine
    types.mbt         #   type definitions (Opt, Parser, ExactNode, TryResult, OptMeta, Visibility, CompletionCandidate, Variation, Lazy, ReduceCtx, FilterChain, etc.)
    parser.mbt        #   Parser::new, register_option, make_alias, deprecated, clone, link, adjust, expand_and_register, env_prefix
    options.mbt       #   custom, append, flag, string, int, float, boolean, count, file, append_string, append_int, append_float
    nodes.mbt         #   make_flag_node, make_value_node, make_or_node, make_soft_custom_value_node, etc.
    commands.mbt      #   cmd, sub
    positionals.mbt   #   positional, rest, serial, never
    dashdash.mbt      #   dashdash, append_dashdash
    constraints.mbt   #   exclusive, required, require_cmd, at_least_one, requires
    access.mbt        #   Opt::get, Parser::get, deprecated_warnings, ParseResult accessors
    parse.mbt         #   parse_raw (OC/P two-phase), install_* nodes, validate_no_duplicate_names
    help.mbt          #   generate_help, inject_help_node, help_header, help_footer, generate_completions, generate_completion_script
    filter.mbt        #   FilterChain, Filter::*, make_reducer, Accumulator, built-in filters
  wasm/              # Layer 2a: WASM transport (JSON schema → kuu core → JSON result)
  cli/               # Layer 2b: Native CLI transport (stdin/stdout JSON protocol)
  dx/                # MoonBit DX layer (Parseable trait + FieldRegistry + parse_into)
  contrib/
    timespec/        # kawaz/timespec integration filters (parse_duration, parse_timespec, parse_timespec_optional)
pkg/
  ts/                # TypeScript DX PoC (WASM-GC wrapper + Schema DSL + InferResult type inference)
```

---

## Related documents

| Document | Contents |
|-------------|------|
| [design/internals.md](design/internals.md) | Detailed implementation spec (all Parser struct fields, list of ExactNode kinds, install-node algorithms, help generation) |
| [ROADMAP.md](ROADMAP.md) | Future plans / unimplemented designs (structured errors, group, multi-source defaults, multi-language rollout, etc.) |
| [design/valcell-lifecycle.md](design/valcell-lifecycle.md) | Detailed ValCell/Accessor lifecycle |
| [design/kuu-essence.md](design/kuu-essence.md) | Essence and positioning of the project |
| [design/kuu-showcase.md](design/kuu-showcase.md) | Use-case showcase (work in progress) |
| `docs/decisions/` | Individual design decision records (DR-0001 and onward) |
