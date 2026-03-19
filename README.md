# kuu

A CLI argument parser for MoonBit. Speculative execution with longest-match resolution eliminates ambiguity without relying on definition order.

## Features

- **Speculative execution + longest match** -- Every candidate is tried; the best interpretation wins. No order dependence, no silent ambiguity.
- **Type-safe from definition to access** -- `Opt[T]` carries the type through parsing. No downcasting, no string maps.
- **FilterChain** -- Composable `String -> T` pipeline with `map`, `validate`, `parse`, and Kleisli composition via `then`.
- **Orthogonal combinators** -- `clone`, `link`, `adjust` compose to express aliases, variations, deprecations, and derived options.
- **Structured errors** -- Contextual help, typo suggestions, usage summary, and footer in every error message.

## Quick Start

```bash
moon add kawaz/kuu
```

```moonbit
fn main {
  let p = @core.Parser::new()
  let name = p.string(name="name", default="world")
  let result = try? p.parse(@env.args())
  match result {
    Err(@core.HelpRequested(text)) => println(text)
    Err(@core.ParseError(info)) => println(info.to_string())
    Ok(_) => println("Hello, " + name.get().unwrap())
  }
}
```

```
$ hello --name kuu
Hello, kuu
```

## Examples

### Flags and options

```moonbit
let p = @core.Parser::new()
let verbose = p.flag(name="verbose", shorts="v", description="Enable verbose output")
let port = p.int(name="port", default=8080, description="Port number")
let host = p.string(name="host", default="localhost")

let _ = try? p.parse(["--verbose", "--port", "3000"])
verbose.get()  //=> Some(true)
port.get()     //=> Some(3000)
host.get()     //=> Some("localhost")
```

### Short option combining

`-vA1B2` is decomposed using type information -- flags consume no value, value options consume the next characters:

```moonbit
let p = @core.Parser::new()
let v = p.flag(name="verbose", shorts="v")
let a = p.string(name="alpha", default="", shorts="A")
let b = p.string(name="beta", default="", shorts="B")

let _ = try? p.parse(["-vA1B2"])
v.get()  //=> Some(true)
a.get()  //=> Some("1")
b.get()  //=> Some("2")
```

### Subcommands

```moonbit
let p = @core.Parser::new()
let verbose = p.flag(name="verbose", global=true)

let serve = p.sub(name="serve", description="Start server")
let port = serve.int(name="port", default=8080)

let result = try? p.parse(["serve", "--port", "3000", "--verbose"])
match result {
  Ok(r) => {
    verbose.get()      //=> Some(true)    -- global, accessible everywhere
    port.get()         //=> Some(3000)    -- scoped to "serve"
    r.child("serve")   //=> Some(...)     -- subcommand result
  }
  // ...
}
```

### Choices and implicit values

```moonbit
let p = @core.Parser::new()
let color = p.string(
  name="color",
  default="auto",
  choices=["always", "auto", "never"],
  implicit_value="always",           // --color (no value) means "always"
  description="When to use color",
)

let _ = try? p.parse(["--color"])
color.get()  //=> Some("always")

let _ = try? p.parse(["--color=never"])
color.get()  //=> Some("never")
```

### Variations

```moonbit
let p = @core.Parser::new()
let verbose = p.flag(
  name="verbose",
  shorts="v",
  variation_toggle=Some("no"),   // generates --no-verbose
)
let _ = try? p.parse(["-v", "--no-verbose"])
verbose.get()  //=> Some(false)  -- toggled back
```

### Constraints

```moonbit
let p = @core.Parser::new()
let json = p.flag(name="json")
let csv = p.flag(name="csv")
let output = p.string(name="output", default="")

p.exclusive([json.as_ref(), csv.as_ref()])   // at most one
p.required(output.as_ref())                  // must be specified
```

## FilterChain

Type-safe transformation pipeline from `String` to any target type. Three constructors -- `map` (pure), `validate` (check + keep type), `parse` (convert + may fail) -- compose via `then`:

```moonbit
let p = @core.Parser::new()

// String -> trim -> non-empty check -> Int -> range check
let port = p.custom(
  name="port",
  default=8080,
  pre=@core.Filter::trim()
    .then(@core.Filter::non_empty())
    .then(@core.Filter::parse_int())
    .then(@core.Filter::in_range(1, 65535)),
)

let _ = try? p.parse(["--port", " 443 "])
port.get()  //=> Some(443)
```

31 built-in filters: string transforms (`trim`, `to_lower`, `replace`, ...), validators (`non_empty`, `min_length`, `starts_with`, ...), numeric parsers (`parse_int`, `parse_float`, `parse_bool`), range checks (`in_range`, `positive`, `clamp`), choices (`one_of`), array operations (`split`, `each`), and regex (`regex_match`, `regex_replace`, `regex_split`).

## Error Display

Errors include four layers of context:

```
error: unexpected argument: --prot
  help: --port <PORT>  Port number [default: 8080]
  tip: a similar option exists: '--port'

Usage: [OPTIONS]

For more information, try '--help'.
```

| Layer | Content |
|-------|---------|
| error | What went wrong |
| help | The relevant option's help line |
| tip | Typo suggestion (Levenshtein-based) |
| usage + footer | How to get more help |

## License

MIT License -- Yoshiaki Kawazu ([@kawaz](https://github.com/kawaz))
