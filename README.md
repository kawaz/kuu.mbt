# kuu.mbt

> English | [日本語](./README-ja.md)

The **MoonBit reference implementation** of [kuu](https://github.com/kawaz/kuu), a language-agnostic CLI argument definition specification.

- The spec, API contract and conformance fixtures live in [kawaz/kuu](https://github.com/kawaz/kuu)
- **Definition of a port**: passing the conformance fixtures published by kawaz/kuu — that is what "conforming to the spec" means
- Published on [mooncakes.io](https://mooncakes.io/docs/kawaz/kuu) as `kawaz/kuu`

## Install

```bash
moon add kawaz/kuu
```

Then import the front-door package from your `moon.pkg.json`:

```json
{ "import": ["kawaz/kuu/kuu"] }
```

## Hello World

Feed a definition (JSON that matches the kuu spec) into `parse_definition`, run
`parse` over an `argv`, then read the effects out of the `Success` outcome:

```moonbit
let definition : Json = @json.parse(
  #|{
  #|  "options": [
  #|    { "name": "verbose", "type": "flag", "long": true, "short": "v" }
  #|  ]
  #|}
)

let ast = match @kuu.parse_definition(definition) {
  Ok(a) => a
  Err(_) => { println("definition rejected"); return }
}

match @kuu.parse(ast, ["--verbose"]) {
  @engine.Success(binds) =>
    for b in binds {
      println("\{b.key} = \{render_value(b.value)}")
    }
  @engine.Failure(_) => println("parse failed")
  @engine.Ambiguous(_) => println("ambiguous")
}
```

`b.value` is an `@engine.Value` sum (`String` / `Number` / `Bool`) — pattern
match it however your app wants to consume it. With the argv `["--verbose"]`
the snippet prints `verbose = true`.

## Running the conformance suite

The conformance fixtures live in the [kawaz/kuu](https://github.com/kawaz/kuu)
repo and are injected via `KUU_FIXTURES`. From a checkout that has kawaz/kuu
next to kuu.mbt, `just test` autodetects `../../kuu/main/fixtures`; otherwise:

```bash
KUU_FIXTURES=/path/to/kawaz/kuu/fixtures moon test --target native
```

The runner prints a line like `[json-conformance] decoded=317 ran_cases=733 mismatches=0`.

## Status

Reference implementation, pre-1.0. The kuu spec is not yet frozen, so the
`kawaz/kuu` MoonBit API surface (front-door `parse_definition` / `parse` /
`resolve` etc.) can still break between minor versions. Current state:
conformance suite green (decoded=317, 733 cases, 0 mismatches). Track the
overall milestone in [ROADMAP](https://github.com/kawaz/kuu/blob/main/ROADMAP.md).

## Layout

| Path | Contents |
|---|---|
| `src/engine/` | The generic engine: structure, evaluation, resolution — contains no builtin vocabulary |
| `src/builtins/` | Canonical builtin residents (types, filters, installers, …), implemented against the same public extension interfaces available to third parties |
| `src/kuu/` | The kuu assembly: composition, front-door API, conformance runner |

Most in-repo documentation (design records under `docs/decisions/`, findings, journals) is currently written in Japanese while the implementation is under heavy iteration.

## License

MIT © Yoshiaki Kawazu
