# kuu.mbt

> English | [日本語](./README-ja.md)

The **MoonBit reference implementation** of [kuu](https://github.com/kawaz/kuu), a language-agnostic CLI argument definition specification.

- The spec, API contract and conformance fixtures live in [kawaz/kuu](https://github.com/kawaz/kuu)
- **Definition of a port**: passing the conformance fixtures published by kawaz/kuu — that is what "conforming to the spec" means
- Published on [mooncakes.io](https://mooncakes.io/docs/kawaz/kuu) as `kawaz/kuu`

## Layout

| Path | Contents |
|---|---|
| `src/engine/` | The generic engine: structure, evaluation, resolution — contains no builtin vocabulary |
| `src/builtins/` | Canonical builtin residents (types, filters, installers, …), implemented against the same public extension interfaces available to third parties |
| `src/kuu/` | The kuu assembly: composition, front-door API, conformance runner |

Most in-repo documentation (design records under `docs/decisions/`, findings, journals) is currently written in Japanese while the implementation is under heavy iteration.

## License

MIT © Yoshiaki Kawazu
