// === enum or パターン PoC ===

///|
enum TestColor {
  Red
  Green
  Blue
  RGB(Int, Int, Int)
  Auto
} derive(Show, Eq)

///|
/// ヘルパー: --color <name> → TestColor (consumed=2) の ExactNode を生成
fn make_color_exact(
  opt_name : String,
  value_str : String,
  color : TestColor,
  cell : Ref[TestColor],
) -> ExactNode {
  ExactNode::{
    name: opt_name,
    needs_value: true,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != opt_name {
        return Reject
      }
      if pos + 1 >= args.length() || args[pos + 1] != value_str {
        return Reject
      }
      Accept(consumed=2, commit=fn() { cell.val = color })
    },
    reset: fn() { cell.val = Auto },
  }
}

///|
/// ヘルパー: --color rgb R G B → RGB(r,g,b) (consumed=5) の ExactNode
fn make_color_rgb_node(opt_name : String, cell : Ref[TestColor]) -> ExactNode {
  ExactNode::{
    name: opt_name,
    needs_value: true,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != opt_name {
        return Reject
      }
      if pos + 1 >= args.length() || args[pos + 1] != "rgb" {
        return Reject
      }
      if pos + 4 >= args.length() {
        return Reject
      }
      let parse_int = fn(s : String) -> Int? {
        let r : Result[Int, _] = try? @strconv.parse_int(s.view())
        match r {
          Ok(v) => Some(v)
          Err(_) => None
        }
      }
      match
        (
          parse_int(args[pos + 2]),
          parse_int(args[pos + 3]),
          parse_int(args[pos + 4]),
        ) {
        (Some(r), Some(g), Some(b)) =>
          Accept(consumed=5, commit=fn() { cell.val = RGB(r, g, b) })
        _ => Reject
      }
    },
    reset: fn() { cell.val = Auto },
  }
}

///|
/// ヘルパー: --color だけ (consumed=1) → implicit value
fn make_color_implicit_node(
  opt_name : String,
  implicit : TestColor,
  cell : Ref[TestColor],
) -> ExactNode {
  ExactNode::{
    name: opt_name,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != opt_name {
        return Reject
      }
      Accept(consumed=1, commit=fn() { cell.val = implicit })
    },
    reset: fn() { cell.val = Auto },
  }
}

///|
/// 全ノードを Parser に登録するヘルパー
fn setup_color_opt(p : Parser) -> Ref[TestColor] {
  let cell : Ref[TestColor] = { val: Auto }
  let nodes : Array[ExactNode] = [
    make_color_exact("--color", "red", Red, cell),
    make_color_exact("--color", "green", Green, cell),
    make_color_exact("--color", "blue", Blue, cell),
    make_color_rgb_node("--color", cell),
    make_color_implicit_node("--color", Red, cell),
  ]
  for node in nodes {
    p.nodes.push(node)
  }
  cell
}

///|
test "enum or: --color red" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "red"]))
  inspect(cell.val, content="Red")
}

///|
test "enum or: --color green" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "green"]))
  inspect(cell.val, content="Green")
}

///|
test "enum or: --color rgb 255 128 0" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "rgb", "255", "128", "0"]))
  inspect(cell.val, content="RGB(255, 128, 0)")
}

///|
test "enum or: --color (implicit → Red)" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color"]))
  inspect(cell.val, content="Red")
}

///|
test "enum or: no --color (default → Auto)" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse([]))
  inspect(cell.val, content="Auto")
}

///|
test "enum or: --color red wins over implicit" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "red"]))
  inspect(cell.val, content="Red")
}

///|
test "enum or: --color with other flag → implicit" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--color", "--verbose"]))
  inspect(cell.val, content="Red")
  inspect(verbose.get(), content="Some(true)")
}

///|
test "enum or: --color rgb with args then other opt" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--color", "rgb", "10", "20", "30", "--verbose"]))
  inspect(cell.val, content="RGB(10, 20, 30)")
  inspect(verbose.get(), content="Some(true)")
}

///|
test "enum or: default not used when --color specified" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "blue"]))
  inspect(cell.val, content="Blue")
}

// === string + choices + implicit_value テスト ===

///|
test "string choices+implicit: --color always" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color", "always"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string choices+implicit: --color (implicit)" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string choices+implicit: no --color (default)" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse([]))
  inspect(
    color.get(),
    content=(
      #|Some("auto")
    ),
  )
}

///|
test "string choices+implicit: --color with other flag" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--color", "--verbose"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
  inspect(verbose.get(), content="Some(true)")
}

///|
test "string choices+implicit: --color rander → implicit then unexpected" {
  let p = Parser::new()
  let _color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  let result : Result[_, _] = try? p.parse(["--color", "rander"])
  inspect(result is Err(_), content="true")
}

///|
test "string choices+implicit: --no-color resets" {
  let p = Parser::new()
  let color = p.custom(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
    variations=[Reset("no")],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--color", "none", "--no-color"]))
  inspect(
    color.get(),
    content=(
      #|Some("auto")
    ),
  )
}

///|
test "string choices+implicit: --color=always (eq_split)" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color=always"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string choices+implicit: Thunk implicit_value" {
  let counter : Ref[Int] = { val: 0 }
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(
      Thunk(fn() {
        counter.val += 1
        "always"
      }),
    ),
  )
  ignore(p.parse(["--color"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
  inspect(counter.val, content="1")
}

///|
test "string choices only: --color invalid → error" {
  let p = Parser::new()
  let _color = p.string(name="color", default="auto", choices=[
    "always", "none", "auto",
  ])
  let result : Result[_, _] = try? p.parse(["--color", "invalid"])
  inspect(result is Err(_), content="true")
}

///|
test "string choices only: --color always → ok" {
  let p = Parser::new()
  let color = p.string(name="color", default="auto", choices=[
    "always", "none", "auto",
  ])
  ignore(p.parse(["--color", "always"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string implicit only: --output (implicit)" {
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  ignore(p.parse(["--output"]))
  inspect(
    output.get(),
    content=(
      #|Some("stdout")
    ),
  )
}

///|
test "string implicit only: --output file.txt" {
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  ignore(p.parse(["--output", "file.txt"]))
  inspect(
    output.get(),
    content=(
      #|Some("file.txt")
    ),
  )
}

///|
test "string choices+implicit with post filter" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
    post=Some(Filter::map(fn(s) { if s == "auto" { "none" } else { s } })),
  )
  ignore(p.parse([]))
  inspect(
    color.get(),
    content=(
      #|Some("none")
    ),
  )
}

///|
test "string choices+implicit: multiple opts with implicit default" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  let md = p.string(
    name="md",
    default="none",
    choices=["render", "source", "none"],
    implicit_value=Some(Val("render")),
  )
  ignore(p.parse(["--color"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
  inspect(
    md.get(),
    content=(
      #|Some("none")
    ),
  )
}

// ============ Variation tests ============

///|
test "variation: False flag with default=true" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[False("no")])
  ignore(p.parse(["--no-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: False flag with default=false" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", default=false, variations=[False("no")])
  ignore(p.parse(["--no-verbose"]))
  // False sets cell=false (same as default), but committed=true
  inspect(p.get(verbose), content="Some(false)")
  inspect(verbose.is_set(), content="true")
}

///|
test "variation: Reset flag resets to default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[Reset("reset")])
  // First set to true (positive), then reset
  ignore(p.parse(["--color", "--reset-color"]))
  inspect(p.get(color), content="Some(true)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: Unset flag resets value and committed" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[Unset("unset")])
  ignore(p.parse(["--color", "--unset-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="false")
}

///|
test "variation: True/False flag with enable/disable" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[True("enable"), False("disable")])
  ignore(p.parse(["--enable-color"]))
  inspect(p.get(color), content="Some(true)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: True/False flag disable" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[True("enable"), False("disable")])
  ignore(p.parse(["--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: True/False flag enable then disable" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[True("enable"), False("disable")])
  ignore(p.parse(["--enable-color", "--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: count with Reset" {
  let p = Parser::new()
  let v = p.count(name="verbose", variations=[Reset("no")])
  ignore(p.parse(["--verbose", "--verbose", "--no-verbose"]))
  inspect(p.get(v), content="Some(0)")
  inspect(v.is_set(), content="true")
}

///|
test "variation: string with Reset" {
  let p = Parser::new()
  let host = p.custom(
    name="host",
    default="localhost",
    variations=[Reset("no")],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--host", "example.com", "--no-host"]))
  inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
  inspect(host.is_set(), content="true")
}

///|
test "variation: string with Unset" {
  let p = Parser::new()
  let host = p.custom(
    name="host",
    default="localhost",
    variations=[Unset("unset")],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--host", "example.com", "--unset-host"]))
  inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
  inspect(host.is_set(), content="false")
}

///|
test "variation: int with Reset" {
  let p = Parser::new()
  let port = p.custom(
    name="port",
    default=8080,
    variations=[Reset("no")],
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["--port", "3000", "--no-port"]))
  inspect(p.get(port), content="Some(8080)")
  inspect(port.is_set(), content="true")
}

///|
test "variation: append_string with Reset" {
  let p = Parser::new()
  let tags = p.custom_append(
    name="tag",
    variations=[Reset("no")],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--tag", "a", "--tag", "b", "--no-tag"]))
  inspect(p.get(tags), content="Some([])")
  inspect(tags.is_set(), content="true")
}

///|
test "variation: append_int with Reset" {
  let p = Parser::new()
  let ids = p.custom_append(
    name="id",
    variations=[Reset("no")],
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["--id", "1", "--id", "2", "--no-id"]))
  inspect(p.get(ids), content="Some([])")
  inspect(ids.is_set(), content="true")
}

///|
test "variation: flag alias also gets variation" {
  let p = Parser::new()
  let color = p.flag(name="color", aliases=["colour"], variations=[False("no")])
  ignore(p.parse(["--no-colour"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: multiple variations" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[
    False("no"),
    True("enable"),
    False("disable"),
  ])
  ignore(p.parse(["--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: empty variations means no --no- prefix" {
  let p = Parser::new()
  let _color = p.flag(name="color", variations=[])
  let result : Result[_, _] = try? p.parse(["--no-color"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("unexpected argument"), content="true")
    _ => abort("expected ParseError for unexpected argument --no-color")
  }
}

///|
test "variation: Toggle basic" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[Toggle("toggle")])
  ignore(p.parse(["--color", "--toggle-color"]))
  // --color sets true (=!default), --toggle-color flips to false
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: Toggle double toggles back" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[Toggle("toggle")])
  ignore(p.parse(["--color", "--toggle-color", "--toggle-color"]))
  // --color → true, --toggle → false, --toggle → true
  inspect(p.get(color), content="Some(true)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: Toggle with default=true" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[Toggle("toggle")])
  ignore(p.parse(["--toggle-color"]))
  // default=true, toggle → false
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: True sets true regardless of default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[True("enable")])
  // Main (--color) with default=true sets to !default = false
  ignore(p.parse(["--color", "--enable-color"]))
  // --color → false, --enable-color → true
  inspect(p.get(color), content="Some(true)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: False sets false regardless of default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[False("disable")])
  ignore(p.parse(["--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "flag Main = not default (default=true)" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true)
  ignore(p.parse(["--color"]))
  // Main with default=true: sets to !true = false
  inspect(p.get(color), content="Some(false)")
}

///|
test "flag Main = not default (default=false)" {
  let p = Parser::new()
  let color = p.flag(name="color", default=false)
  ignore(p.parse(["--color"]))
  // Main with default=false: sets to !false = true
  inspect(p.get(color), content="Some(true)")
}

// ============ Sugar parameter tests ============

///|
test "flag variation_reset sugar" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", variation_reset=Some("no"))
  ignore(p.parse(["--verbose", "--no-verbose"]))
  inspect(verbose.get(), content="Some(false)") // Reset → default(false)
  inspect(verbose.is_set(), content="true")
}

///|
test "string variation_reset sugar" {
  let p = Parser::new()
  let fmt = p.custom(
    name="format",
    default="json",
    variations=[Reset("no")],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--format", "xml", "--no-format"]))
  inspect(
    fmt.get(),
    content=(
      #|Some("json")
    ),
  ) // Reset → default
  inspect(fmt.is_set(), content="true")
}

///|
test "sugar params append to variations" {
  let p = Parser::new()
  let verbose = p.flag(
    name="verbose",
    variations=[Toggle("toggle")],
    variation_reset=Some("no"),
  )
  // Toggle + Reset 両方が存在
  ignore(p.parse(["--toggle-verbose", "--no-verbose"]))
  inspect(verbose.get(), content="Some(false)") // Reset → default
  inspect(verbose.is_set(), content="true")
}

///|
test "flag variation_true and variation_false sugar" {
  let p = Parser::new()
  let color = p.flag(
    name="color",
    default=true,
    variation_true=Some("force"),
    variation_false=Some("no"),
  )
  ignore(p.parse(["--no-color"]))
  inspect(color.get(), content="Some(false)") // False → always false
  //
  let p2 = Parser::new()
  let color2 = p2.flag(
    name="color",
    default=true,
    variation_true=Some("force"),
    variation_false=Some("no"),
  )
  ignore(p2.parse(["--no-color", "--force-color"]))
  inspect(color2.get(), content="Some(true)") // True → always true
}

///|
test "count variation_reset sugar" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", variation_reset=Some("no"))
  ignore(p.parse(["--verbose", "--verbose", "--no-verbose"]))
  inspect(verbose.get(), content="Some(0)") // Reset → default(0)
  inspect(verbose.is_set(), content="true")
}

///|
test "append_string variation_reset sugar" {
  let p = Parser::new()
  let includes = p.custom_append(
    name="include",
    variations=[Reset("no")],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--include", "a", "--include", "b", "--no-include"]))
  inspect(includes.get(), content="Some([])") // Reset → empty
  inspect(includes.is_set(), content="true")
}

// ============ default_fn tests ============

///|
test "flag default_fn" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", default_fn=Some(fn() { true }))
  ignore(p.parse([])) // no args
  inspect(verbose.get(), content="Some(true)") // default_fn で true
  inspect(verbose.is_set(), content="false") // 明示指定なし
}

///|
test "flag default_fn overrides default" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", default_fn=Some(fn() { true }))
  ignore(p.parse(["--verbose"]))
  // Main = !initial_val = !true = false
  inspect(verbose.get(), content="Some(false)")
  inspect(verbose.is_set(), content="true")
}

///|
test "string default_fn" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    default_fn=Some(fn() { "always" }),
  )
  ignore(p.parse([])) // no args
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  ) // default_fn が優先
  inspect(color.is_set(), content="false")
}

///|
test "int default_fn" {
  let p = Parser::new()
  let port = p.int(name="port", default=80, default_fn=Some(fn() { 8080 }))
  ignore(p.parse([])) // no args
  inspect(port.get(), content="Some(8080)") // default_fn が優先
  inspect(port.is_set(), content="false")
}

///|
test "string default_fn with reset variation" {
  let p = Parser::new()
  let color = p.custom(
    name="color",
    default="auto",
    default_fn=Some(fn() { "always" }),
    variations=[Reset("no")],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--color", "never", "--no-color"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  ) // Reset → default_fn の値に戻る
  inspect(color.is_set(), content="true")
}

// --- custom[T] / custom_append[T] tests ---

///|
test "custom_string_basic" {
  let p = Parser::new()
  let name = p.custom(
    name="name",
    default="world",
    pre=Filter::map(fn(s) { s }),
  )
  p.parse(["--name", "alice"]) |> ignore
  inspect((name.accessor.get)(), content="alice")
}

///|
test "custom_string_default" {
  let p = Parser::new()
  let name = p.custom(
    name="name",
    default="world",
    pre=Filter::map(fn(s) { s }),
  )
  p.parse([]) |> ignore
  inspect((name.accessor.get)(), content="world")
}

///|
test "custom_int_basic" {
  let p = Parser::new()
  let port = p.custom(name="port", default=8080, pre=Filter::parse_int())
  p.parse(["--port", "3000"]) |> ignore
  inspect((port.accessor.get)(), content="3000")
}

///|
test "custom_int_default" {
  let p = Parser::new()
  let port = p.custom(name="port", default=8080, pre=Filter::parse_int())
  p.parse([]) |> ignore
  inspect((port.accessor.get)(), content="8080")
}

///|
test "custom_int_invalid" {
  let p = Parser::new()
  let _ = p.custom(name="port", default=8080, pre=Filter::parse_int())
  let result : Result[_, _] = try? p.parse(["--port", "abc"])
  inspect(result is Err(_), content="true")
}

///|
test "custom_double_basic" {
  let p = Parser::new()
  let rate = p.custom(name="rate", default=1.0, pre=Filter::parse_float())
  p.parse(["--rate", "3.14"]) |> ignore
  inspect((rate.accessor.get)(), content="3.14")
}

///|
test "custom_with_choices" {
  let p = Parser::new()
  let level = p.custom(
    name="level",
    default="info",
    pre=Filter::map(fn(s) { s }),
    choices=["debug", "info", "warn", "error"],
  )
  p.parse(["--level", "warn"]) |> ignore
  inspect((level.accessor.get)(), content="warn")
}

///|
test "custom_with_choices_invalid" {
  let p = Parser::new()
  let _ = p.custom(name="level", default="info", pre=Filter::map(fn(s) { s }), choices=[
    "debug", "info", "warn", "error",
  ])
  let result : Result[_, _] = try? p.parse(["--level", "trace"])
  inspect(result is Err(_), content="true")
}

///|
test "custom_with_implicit_value" {
  let p = Parser::new()
  let verbose = p.custom(
    name="verbose",
    default=0,
    pre=Filter::parse_int(),
    implicit_value=Some(Val(1)),
  )
  // implicit: --verbose のみで implicit_value=1 が使われる
  p.parse(["--verbose"]) |> ignore
  inspect((verbose.accessor.get)(), content="1")
}

///|
test "custom_with_implicit_value_explicit" {
  let p = Parser::new()
  let verbose = p.custom(
    name="verbose",
    default=0,
    pre=Filter::parse_int(),
    implicit_value=Some(Val(1)),
  )
  // explicit: --verbose 3 で明示値 3 が使われる
  p.parse(["--verbose", "3"]) |> ignore
  inspect((verbose.accessor.get)(), content="3")
}

///|
test "custom_with_choices_and_implicit" {
  let p = Parser::new()
  let color = p.custom(
    name="color",
    default="auto",
    pre=Filter::map(fn(s) { s }),
    choices=["always", "never", "auto"],
    implicit_value=Some(Val("always")),
  )
  // implicit: --color のみで implicit_value="always"
  p.parse(["--color"]) |> ignore
  inspect((color.accessor.get)(), content="always")
}

///|
test "custom_with_choices_and_implicit_explicit" {
  let p = Parser::new()
  let color = p.custom(
    name="color",
    default="auto",
    pre=Filter::map(fn(s) { s }),
    choices=["always", "never", "auto"],
    implicit_value=Some(Val("always")),
  )
  // explicit: --color never で明示値
  p.parse(["--color", "never"]) |> ignore
  inspect((color.accessor.get)(), content="never")
}

///|
test "custom_with_post" {
  let p = Parser::new()
  let name = p.custom(
    name="name",
    default="world",
    pre=Filter::map(fn(s) { s }),
    post=Some(Filter::map(fn(s : String) { s.to_upper() })),
  )
  p.parse(["--name", "alice"]) |> ignore
  inspect((name.accessor.get)(), content="ALICE")
}

///|
test "custom_append_string_basic" {
  let p = Parser::new()
  let tags = p.custom_append(name="tag", pre=Filter::map(fn(s) { s }))
  p.parse(["--tag", "a", "--tag", "b"]) |> ignore
  inspect((tags.accessor.get)(), content="[\"a\", \"b\"]")
}

///|
test "custom_append_string_empty" {
  let p = Parser::new()
  let tags = p.custom_append(name="tag", pre=Filter::map(fn(s) { s }))
  p.parse([]) |> ignore
  inspect((tags.accessor.get)(), content="[]")
}

///|
test "custom_append_int_basic" {
  let p = Parser::new()
  let nums = p.custom_append(name="num", pre=Filter::parse_int())
  p.parse(["--num", "1", "--num", "2", "--num", "3"]) |> ignore
  inspect((nums.accessor.get)(), content="[1, 2, 3]")
}

///|
test "custom_append_int_invalid" {
  let p = Parser::new()
  let _ = p.custom_append(name="num", pre=Filter::parse_int())
  let result : Result[_, _] = try? p.parse(["--num", "abc"])
  inspect(result is Err(_), content="true")
}

// ============================================================
// C2: variation_names shown in help
// ============================================================

///|
test "help shows --no-xxx for variation_false" {
  let p = Parser::new()
  let _ = p.flag(
    name="color",
    variation_false=Some("no"),
    description="Use color",
  )
  let help = p.generate_help()
  inspect(help.contains("--no-color"), content="true")
  inspect(help.contains("--color, --no-color"), content="true")
}

///|
test "help shows multiple variations" {
  let p = Parser::new()
  let _ = p.flag(
    name="color",
    variations=[True("enable"), False("disable")],
    description="Use color",
  )
  let help = p.generate_help()
  inspect(help.contains("--enable-color"), content="true")
  inspect(help.contains("--disable-color"), content="true")
  inspect(
    help.contains("--color, --enable-color, --disable-color"),
    content="true",
  )
}

///|
test "help shows variation with aliases" {
  let p = Parser::new()
  let _ = p.flag(
    name="color",
    aliases=["colour"],
    variation_false=Some("no"),
    description="Use color",
  )
  let help = p.generate_help()
  // aliases come before variations
  inspect(help.contains("--color, --colour, --no-color"), content="true")
}

///|
test "help shows variation with shorts and aliases" {
  let p = Parser::new()
  let _ = p.flag(
    name="color",
    shorts="c",
    aliases=["colour"],
    variation_false=Some("no"),
    description="Use color",
  )
  let help = p.generate_help()
  inspect(help.contains("-c, --color, --colour, --no-color"), content="true")
}

///|
test "help shows no variation when variations is empty" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose output")
  let help = p.generate_help()
  // Should show just --verbose without any variation suffix
  inspect(help.contains("--verbose"), content="true")
  // Should not contain comma after --verbose (no aliases, no variations)
  inspect(help.contains("--verbose,"), content="false")
}

///|
test "help variation_reset shows --no-xxx" {
  let p = Parser::new()
  let _ = p.custom(
    name="format",
    default="json",
    variations=[Reset("no")],
    description="Output format",
    pre=Filter::map(fn(s) { s }),
  )
  let help = p.generate_help()
  inspect(help.contains("--no-format"), content="true")
}

// ============================================================
// alias コンビネータ
// ============================================================

///|
test "alias: flag alias shares value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  ignore(p.parse(["--verb"]))
  // alias 経由で値が共有される
  inspect(verbose.get(), content="Some(true)")
  inspect(verb.get(), content="Some(true)")
}

///|
test "alias: flag alias is_set independence" {
  // alias 使用時は alias.is_set=true, target.is_set=true（両方セット）
  // alias 未使用時は alias.is_set=false
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  ignore(p.parse(["--verbose"]))
  // target 使用: target.is_set=true, alias.is_set=false
  inspect(verbose.is_set(), content="true")
  inspect(verb.is_set(), content="false")
}

///|
test "alias: flag alias sets both is_set" {
  // alias 経由で使用した場合、alias と target の両方の is_set が true になる
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  ignore(p.parse(["--verb"]))
  inspect(verbose.is_set(), content="true")
  inspect(verb.is_set(), content="true")
}

///|
test "alias: string alias shares value" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let h = p.make_alias("--h", host)
  ignore(p.parse(["--h", "example.com"]))
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(
    h.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "alias: single-dash long option" {
  // -Xcc のような単一ダッシュオプションを alias で登録
  let p = Parser::new()
  let compiler = p.string(name="compiler", default="")
  let xcc = p.make_alias("-Xcc", compiler)
  ignore(p.parse(["-Xcc", "gcc"]))
  inspect(
    compiler.get(),
    content=(
      #|Some("gcc")
    ),
  )
  inspect(xcc.is_set(), content="true")
  inspect(compiler.is_set(), content="true")
}

///|
test "alias: duplicate name detected" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  // --verbose は既に登録されているので重複
  ignore(p.make_alias("--verbose", verbose))
  let result : Result[_, _] = try? p.parse([])
  inspect(result is Err(_), content="true")
}

///|
test "alias: cmd alias shares child parser" {
  let p = Parser::new()
  let status = p.cmd(name="status", setup=fn(child) {
    ignore(child.flag(name="short"))
  })
  let st = p.make_alias("st", status)
  ignore(p.parse(["st", "--short"]))
  inspect(status.is_set(), content="true")
  inspect(st.is_set(), content="true")
  // cmd alias でも同一子パーサが使われる
  let cmd_result = status.get().unwrap()
  inspect(cmd_result.name, content="status")
}

///|
test "alias: chained alias (alias of alias)" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  let v = p.make_alias("--v", verb)
  ignore(p.parse(["--v"]))
  // 全ての alias と target の値が共有される
  inspect(verbose.get(), content="Some(true)")
  inspect(verb.get(), content="Some(true)")
  inspect(v.get(), content="Some(true)")
  // is_set: v と verbose は true（alias 経由で target も true）
  // verb は直接使っていないので false
  inspect(verbose.is_set(), content="true")
  inspect(verb.is_set(), content="false")
  inspect(v.is_set(), content="true")
}

///|
test "alias: int alias shares value" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  let pp = p.make_alias("-p", port)
  ignore(p.parse(["-p", "3000"]))
  inspect(port.get(), content="Some(3000)")
  inspect(pp.get(), content="Some(3000)")
}

///|
test "alias: append alias shares array" {
  let p = Parser::new()
  let inc = p.append_string(name="include")
  let ii = p.make_alias("-I", inc)
  ignore(p.parse(["--include", "a", "-I", "b"]))
  inspect(inc.get(), content="Some([\"a\", \"b\"])")
  inspect(ii.get(), content="Some([\"a\", \"b\"])")
}

///|
test "alias: unused alias default value" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let h = p.make_alias("--h", host)
  ignore(p.parse([]))
  inspect(
    host.get(),
    content=(
      #|Some("localhost")
    ),
  )
  inspect(
    h.get(),
    content=(
      #|Some("localhost")
    ),
  )
  inspect(host.is_set(), content="false")
  inspect(h.is_set(), content="false")
}

///|
test "alias: global alias propagates to subcommand" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let verb = p.make_alias("--verb", verbose)
  let status = p.cmd(name="status", setup=fn(_child) {  })
  ignore(p.parse(["status", "--verb"]))
  // global alias は子パーサでも使える
  inspect(verbose.get(), content="Some(true)")
  inspect(verb.get(), content="Some(true)")
  inspect(verbose.is_set(), content="true")
  inspect(verb.is_set(), content="true")
  inspect(status.is_set(), content="true")
}

///|
test "alias: eq_split with double-dash alias" {
  // --alias=value 構文が動くか
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let h = p.make_alias("--h", host)
  ignore(p.parse(["--h=example.com"]))
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(
    h.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "alias: count alias shares counter" {
  let p = Parser::new()
  let verbose = p.count(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  ignore(p.parse(["--verbose", "--verb", "--verbose"]))
  inspect(verbose.get(), content="Some(3)")
  inspect(verb.get(), content="Some(3)")
}

///|
test "alias: alias does not expand variations" {
  // alias は variation を展開しない（DR-037: variation = alias + adjust の合成）
  let p = Parser::new()
  let verbose = p.flag(name="verbose", variations=[False("no")])
  ignore(p.make_alias("--verb", verbose))
  // --no-verb は存在しないのでエラー
  let result : Result[_, _] = try? p.parse(["--no-verb"])
  inspect(result is Err(_), content="true")
}

// === H-1: --opt=--value で implicit_value にフォールバックするバグ ===

///|
test "H-1: string implicit: --output=--value (eq-split, double-dash value)" {
  // implicit_value 付きオプションで --output=--value のように
  // = 経由で -- 始まりの値を渡した場合、値が正しく取れること
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  ignore(p.parse(["--output=--value"]))
  inspect(
    output.get(),
    content=(
      #|Some("--value")
    ),
  )
}

///|
test "H-1: int implicit: --port=--not-a-port (eq-split) → parse error" {
  // int の implicit_value 付きで --port=--not-a-port は
  // = 経由で明示的に渡されたが Int パースに失敗するのでエラー
  let p = Parser::new()
  ignore(p.int(name="port", default=8080, implicit_value=Some(Val(3000))))
  let result : Result[_, _] = try? p.parse(["--port=--not-a-port"])
  inspect(result is Err(_), content="true")
}

///|
test "H-1: string implicit: --output --next (space-separated) → still implicit" {
  // スペース区切りの場合は従来通り -- 始まりの次トークンは
  // 次のオプションとして扱い、implicit にフォールバックすべき
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  let next = p.flag(name="next")
  ignore(p.parse(["--output", "--next"]))
  inspect(
    output.get(),
    content=(
      #|Some("stdout")
    ),
  )
  inspect(next.get(), content="Some(true)")
}

// ============================================================
// M-17: custom_append の variation テスト
// ============================================================

///|
test "M-17: custom_append Reset variation clears array" {
  // custom_append + Reset variation で配列がクリアされること
  let p = Parser::new()
  let tags = p.custom_append(name="tag", pre=Filter::map(fn(s) { s }), variations=[
    Reset("no"),
  ])
  ignore(p.parse(["--tag", "a", "--tag", "b", "--no-tag"]))
  inspect((tags.accessor.get)(), content="[]")
  inspect(tags.is_set(), content="true")
}

///|
test "M-17: custom_append Reset then re-add" {
  // Reset 後に再度追加すると新しい値のみ残る
  let p = Parser::new()
  let tags = p.custom_append(name="tag", pre=Filter::map(fn(s) { s }), variations=[
    Reset("no"),
  ])
  ignore(p.parse(["--tag", "a", "--no-tag", "--tag", "b"]))
  inspect((tags.accessor.get)(), content="[\"b\"]")
}

///|
test "M-17: custom_append Unset variation clears and unsets" {
  // Unset は配列クリア + is_set=false
  let p = Parser::new()
  let tags = p.custom_append(name="tag", pre=Filter::map(fn(s) { s }), variations=[
    Unset("un"),
  ])
  ignore(p.parse(["--tag", "a", "--tag", "b", "--un-tag"]))
  inspect((tags.accessor.get)(), content="[]")
  inspect(tags.is_set(), content="false")
}

// ============================================================
// M-18: count の variation テスト (Toggle/True/False)
// ============================================================

///|
test "M-18: count Toggle variation resets to 0" {
  // count の Toggle variation はカウンタを 0 にリセットする
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[Toggle("no")])
  ignore(p.parse(["--verbose", "--verbose", "--no-verbose"]))
  inspect(p.get(verbose), content="Some(0)")
  inspect(verbose.is_set(), content="true")
}

///|
test "M-18: count True variation resets to 0" {
  // count の True variation もカウンタを 0 にリセットする（Bool 特有の True は count では Reset 相当）
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[True("force")])
  ignore(p.parse(["--verbose", "--verbose", "--force-verbose"]))
  inspect(p.get(verbose), content="Some(0)")
  inspect(verbose.is_set(), content="true")
}

///|
test "M-18: count False variation resets to 0" {
  // count の False variation もカウンタを 0 にリセットする（Bool 特有の False は count では Reset 相当）
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[False("off")])
  ignore(p.parse(["--verbose", "--verbose", "--verbose", "--off-verbose"]))
  inspect(p.get(verbose), content="Some(0)")
  inspect(verbose.is_set(), content="true")
}

///|
test "M-18: count Toggle then re-count" {
  // Toggle でリセット後に再カウントで新しいカウントのみ
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[Toggle("no")])
  ignore(p.parse(["--verbose", "--verbose", "--no-verbose", "--verbose"]))
  inspect(p.get(verbose), content="Some(1)")
}

///|
test "M-18: count Unset variation resets and unsets" {
  // Unset はカウンタリセット + is_set=false
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[Unset("un")])
  ignore(p.parse(["--verbose", "--verbose", "--un-verbose"]))
  inspect(p.get(verbose), content="Some(0)")
  inspect(verbose.is_set(), content="false")
}

// ============================================================
// M-21: int の post フィルタバリデーションエラーテスト
// ============================================================

///|
test "M-21: int post validation error" {
  // int に post フィルタ (in_range) を渡して範囲外でエラー
  let p = Parser::new()
  let _ = p.int(
    name="port",
    default=8080,
    post=Some(Filter::in_range(1, 65535)),
  )
  let result : Result[_, _] = try? p.parse(["--port", "0"])
  inspect(result is Err(_), content="true")
}

///|
test "M-21: int post validation passes for valid value" {
  let p = Parser::new()
  let port = p.int(
    name="port",
    default=8080,
    post=Some(Filter::in_range(1, 65535)),
  )
  ignore(p.parse(["--port", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "M-21: int post validation error message contains out of range" {
  let p = Parser::new()
  let _ = p.int(
    name="port",
    default=8080,
    post=Some(Filter::in_range(1, 65535)),
  )
  let result : Result[ParseResult, ParseError] = try? p.parse([
    "--port", "99999",
  ])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("out of range"), content="true")
    _ => abort("expected validation error")
  }
}

///|
test "M-21: int post validation error on negative" {
  let p = Parser::new()
  let _ = p.int(
    name="port",
    default=8080,
    post=Some(Filter::in_range(1, 65535)),
  )
  let result : Result[_, _] = try? p.parse(["--port", "-1"])
  inspect(result is Err(_), content="true")
}

///|
test "M-21: int post default also validated" {
  // default 値も post フィルタを通る。default=0 で in_range(1, 65535) はエラーになる
  let p = Parser::new()
  let _ = p.int(name="port", default=0, post=Some(Filter::in_range(1, 65535)))
  let result : Result[_, _] = try? p.parse([])
  inspect(result is Err(_), content="true")
}

// === alias + implicit_value の eq_split フォールバック漏れ ===

///|
test "alias + implicit_value: eq_split via alias name (normal value)" {
  // implicit_value 付きオプションの alias で --alias=value が正しくパースされること
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Lazy::Val("stdout")),
  )
  let out = p.make_alias("--out", output)
  ignore(p.parse(["--out=file.txt"]))
  inspect(
    output.get(),
    content=(
      #|Some("file.txt")
    ),
  )
  inspect(
    out.get(),
    content=(
      #|Some("file.txt")
    ),
  )
}

///|
test "alias + implicit_value: eq_split via alias name (double-dash value)" {
  // implicit_value 付きオプションの alias で --alias=--value が正しくパースされること
  // alias で追加された名前は eq_fallback_nodes に登録されていないため、
  // make_soft_custom_value_node の "--" ガードで Reject → implicit にフォールバックしていた
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Lazy::Val("stdout")),
  )
  let out = p.make_alias("--out", output)
  ignore(p.parse(["--out=--file.txt"]))
  inspect(
    output.get(),
    content=(
      #|Some("--file.txt")
    ),
  )
  inspect(
    out.get(),
    content=(
      #|Some("--file.txt")
    ),
  )
}

///|
test "alias + implicit_value: eq_split via original name still works" {
  // 修正後も元のオプション名での eq_split は引き続き動くこと
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Lazy::Val("stdout")),
  )
  let _ = p.make_alias("--out", output)
  ignore(p.parse(["--output=file.txt"]))
  inspect(
    output.get(),
    content=(
      #|Some("file.txt")
    ),
  )
}

///|
test "alias + implicit_value: alias without eq_split uses implicit" {
  // alias を eq_split なしで使った場合は implicit_value が使われること
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Lazy::Val("stdout")),
  )
  let out = p.make_alias("--out", output)
  ignore(p.parse(["--out"]))
  inspect(
    output.get(),
    content=(
      #|Some("stdout")
    ),
  )
  inspect(
    out.get(),
    content=(
      #|Some("stdout")
    ),
  )
}

// === R2-C1: global=true の宣言順序非依存テスト ===

///|
test "R2-C1: global defined after cmd propagates to subcommand" {
  let p = Parser::new(dashdash=false)
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(_child) {  })
  // global を cmd の後に定義
  let verbose = p.flag(name="verbose", global=true)
  ignore(p.parse(["serve", "--verbose"]))
  inspect(verbose.get(), content="Some(true)")
}

///|
test "R2-C1: global alias defined after cmd propagates" {
  let p = Parser::new(dashdash=false)
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(_child) {  })
  let verbose = p.flag(name="verbose", global=true)
  let _ = p.make_alias("--verb", verbose)
  ignore(p.parse(["serve", "--verb"]))
  inspect(verbose.get(), content="Some(true)")
}

///|
test "R2-C1: multiple globals after cmd all propagate" {
  let p = Parser::new(dashdash=false)
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(_child) {  })
  let verbose = p.flag(name="verbose", global=true)
  let debug = p.flag(name="debug", global=true)
  ignore(p.parse(["serve", "--verbose", "--debug"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(debug.get(), content="Some(true)")
}

///|
test "R2-C1: global defined after nested cmd propagates to grandchild" {
  let p = Parser::new(dashdash=false)
  let _remote = p.cmd(name="remote", dashdash=false, setup=fn(remote) {
    let _add = remote.cmd(name="add", dashdash=false, setup=fn(_add) {  })
  })
  // global を cmd の後に定義 — 孫 cmd にも遅延同期で伝播するか確認
  let verbose = p.flag(name="verbose", global=true)
  ignore(p.parse(["remote", "add", "--verbose"]))
  inspect(verbose.get(), content="Some(true)")
}

// === R2-W4: implicit_value + choices 共存テスト ===

///|
test "R2-W4: implicit+choices explicit value" {
  let p = Parser::new(dashdash=false)
  let level = p.string(
    name="level",
    default="info",
    choices=["debug", "info", "warn", "error"],
    implicit_value=Some(Val("debug")),
  )
  ignore(p.parse(["--level", "warn"]))
  inspect(level.get(), content="Some(\"warn\")")
}

///|
test "R2-W4: implicit+choices implicit value" {
  let p = Parser::new(dashdash=false)
  let level = p.string(
    name="level",
    default="info",
    choices=["debug", "info", "warn", "error"],
    implicit_value=Some(Val("debug")),
  )
  ignore(p.parse(["--level"]))
  inspect(level.get(), content="Some(\"debug\")")
}

///|
test "R2-W4: implicit+choices eq-split" {
  let p = Parser::new(dashdash=false)
  let level = p.string(
    name="level",
    default="info",
    choices=["debug", "info", "warn", "error"],
    implicit_value=Some(Val("debug")),
  )
  ignore(p.parse(["--level=error"]))
  inspect(level.get(), content="Some(\"error\")")
}

///|
test "R2-W4: implicit+choices invalid choice via eq-split" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(
    name="level",
    default="info",
    choices=["debug", "info", "warn", "error"],
    implicit_value=Some(Val("debug")),
  )
  let result = try? p.parse(["--level=bad"])
  inspect(result is Err(_), content="true")
}

// === deprecated コンビネータテスト ===

///|
test "deprecated records usage when used" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let _ = p.deprecated("--out", output, msg="use --output instead")
  ignore(p.parse(["--out", "file.txt"]))
  inspect(p.deprecated_warnings().length(), content="1")
  let warn = p.deprecated_warnings()[0]
  inspect(warn.0, content="--out")
  inspect(warn.1, content="use --output instead")
}

///|
test "deprecated not recorded when unused" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let _ = p.deprecated("--out", output, msg="use --output instead")
  ignore(p.parse(["--output", "file.txt"]))
  inspect(p.deprecated_warnings().length(), content="0")
}

///|
test "deprecated shares value with target" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="default")
  let out = p.deprecated("--out", output, msg="use --output instead")
  ignore(p.parse(["--out", "hello"]))
  // alias 動作: 値が共有される
  inspect(output.get(), content="Some(\"hello\")")
  inspect(out.get(), content="Some(\"hello\")")
}

///|
test "deprecated is_set independent from target" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="default")
  let out = p.deprecated("--out", output, msg="use --output instead")
  ignore(p.parse(["--out", "hello"]))
  // alias 動作: is_set は独立（deprecated 側のみ true、target は set_commit で true）
  inspect(out.is_set(), content="true")
  inspect(output.is_set(), content="true")
}

///|
test "deprecated with cmd" {
  let p = Parser::new(dashdash=false)
  let serve = p.cmd(name="serve", dashdash=false, setup=fn(_child) {  })
  let srv = p.deprecated("serve-old", serve, msg="use 'serve' instead")
  ignore(p.parse(["serve-old"]))
  // cmd の deprecated 別名も動作する
  inspect(serve.get() is Some(_), content="true")
  inspect(srv.get() is Some(_), content="true")
  inspect(p.deprecated_warnings().length(), content="1")
  inspect(p.deprecated_warnings()[0].0, content="serve-old")
}

///|
test "deprecated in subcommand propagates to parent" {
  let p = Parser::new(dashdash=false)
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(child) {
    let port = child.int(name="port", default=8080)
    let _ = child.deprecated("--p", port, msg="use --port")
  })
  ignore(p.parse(["serve", "--p", "3000"]))
  // サブコマンド内の deprecated 警告がルートから取得できること
  inspect(
    p.deprecated_warnings().length(),
    content=(
      #|1
    ),
  )
  inspect(p.deprecated_warnings()[0].0, content="--p")
  inspect(p.deprecated_warnings()[0].1, content="use --port")
}

///|
test "deprecated in nested subcommand propagates to root" {
  let p = Parser::new(dashdash=false)
  let _remote = p.cmd(name="remote", dashdash=false, setup=fn(remote) {
    let _add = remote.cmd(name="add", dashdash=false, setup=fn(add) {
      let url = add.string(name="url", default="")
      let _ = add.deprecated("--uri", url, msg="use --url")
    })
  })
  ignore(p.parse(["remote", "add", "--uri", "https://example.com"]))
  // 孫コマンド内の deprecated 警告がルートから取得できること
  inspect(
    p.deprecated_warnings().length(),
    content=(
      #|1
    ),
  )
  inspect(p.deprecated_warnings()[0].0, content="--uri")
}

///|
test "deprecated in parent and subcommand both reported" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let _ = p.deprecated("--verb", verbose, msg="use --verbose")
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(child) {
    let port = child.int(name="port", default=8080)
    let _ = child.deprecated("--p", port, msg="use --port")
  })
  ignore(p.parse(["--verb", "serve", "--p", "3000"]))
  // 親とサブコマンド両方の警告が取得できること
  inspect(
    p.deprecated_warnings().length(),
    content=(
      #|2
    ),
  )
  let names = p.deprecated_warnings().map(fn(w) { w.0 })
  inspect(names.contains("--verb"), content="true")
  inspect(
    names.contains("--p"),
    content=(
      #|true
    ),
  )
}

///|
test "deprecated multiple options" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let verbose = p.flag(name="verbose")
  let _ = p.deprecated("--out", output, msg="use --output")
  let _ = p.deprecated("--verb", verbose, msg="use --verbose")
  ignore(p.parse(["--out", "f.txt", "--verb"]))
  inspect(p.deprecated_warnings().length(), content="2")
  // 両方記録されている
  let names = p.deprecated_warnings().map(fn(w) { w.0 })
  inspect(names.contains("--out"), content="true")
  inspect(names.contains("--verb"), content="true")
}

///|
test "deprecated empty name rejected" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let _ = p.deprecated("", output, msg="bad")
  let result = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message.contains("deprecated name must not be empty"),
        content="true",
      )
    _ => abort("expected error for empty deprecated name")
  }
}

// === DR-041: env パラメータ（ヘルプ表示）テスト ===

///|
test "env name shown in help for string" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(
    name="port",
    default="8080",
    env="PORT",
    description="Server port",
  )
  let help = p.generate_help()
  inspect(help.contains("[env: PORT]"), content="true")
}

///|
test "env name shown in help for flag" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="verbose", env="VERBOSE", description="Enable verbose")
  let help = p.generate_help()
  inspect(help.contains("[env: VERBOSE]"), content="true")
}

///|
test "env name shown in help for int" {
  let p = Parser::new(dashdash=false)
  let _ = p.int(
    name="port",
    default=8080,
    env="PORT",
    description="Server port",
  )
  let help = p.generate_help()
  inspect(help.contains("[env: PORT]"), content="true")
}

///|
test "env and default both shown in help" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(
    name="host",
    default="localhost",
    env="HOST",
    description="Server host",
  )
  let help = p.generate_help()
  // env は default の前に表示される（隣接して出現）
  inspect(help.contains("[env: HOST] [default: localhost]"), content="true")
}

///|
test "env not shown when empty" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(name="host", default="localhost", description="Host")
  let help = p.generate_help()
  inspect(help.contains("[env:"), content="false")
}

///|
test "env shown in global options section" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(
    name="verbose",
    global=true,
    env="VERBOSE",
    description="Verbose output",
  )
  let help = p.generate_help()
  inspect(help.contains("Global Options:"), content="true")
  inspect(help.contains("[env: VERBOSE]"), content="true")
}

///|
test "env with custom combinator" {
  let p = Parser::new(dashdash=false)
  let _ = p.custom(
    name="format",
    default="json",
    pre=Filter::map(fn(s) { s }),
    env="OUTPUT_FORMAT",
    description="Output format",
  )
  let help = p.generate_help()
  inspect(help.contains("[env: OUTPUT_FORMAT]"), content="true")
}

///|
test "env with append combinator" {
  let p = Parser::new(dashdash=false)
  let _ = p.append_string(
    name="include",
    env="INCLUDE_PATHS",
    description="Include paths",
  )
  let help = p.generate_help()
  inspect(help.contains("[env: INCLUDE_PATHS]"), content="true")
}

///|
test "env with count combinator" {
  let p = Parser::new(dashdash=false)
  let _ = p.count(name="verbose", env="VERBOSE", description="Verbosity level")
  let help = p.generate_help()
  inspect(help.contains("[env: VERBOSE]"), content="true")
}

///|
test "env hidden option does not leak env_name in help" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(
    name="secret-key",
    default="",
    env="SECRET_KEY",
    visibility=Hidden,
    description="Secret",
  )
  let _ = p.flag(name="verbose", description="Verbose")
  let help = p.generate_help()
  inspect(help.contains("[env: SECRET_KEY]"), content="false")
  inspect(help.contains("secret-key"), content="false")
}

// === DR-041 Phase 2: env 値取得テスト ===

///|
test "env: string gets value from env when not specified on CLI" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={ "PORT": "9000" }))
  inspect(
    port.get(),
    content=(
      #|Some("9000")
    ),
  )
}

///|
test "env: CLI arg takes precedence over env" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse(["--port", "3000"], env={ "PORT": "9000" }))
  inspect(
    port.get(),
    content=(
      #|Some("3000")
    ),
  )
}

///|
test "env: default used when neither CLI nor env specified" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={}))
  inspect(
    port.get(),
    content=(
      #|Some("8080")
    ),
  )
}

///|
test "env: flag from env" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", env="VERBOSE")
  ignore(p.parse([], env={ "VERBOSE": "true" }))
  inspect(verbose.get(), content="Some(true)")
}

///|
test "env: flag false from env" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", env="VERBOSE")
  ignore(p.parse([], env={ "VERBOSE": "false" }))
  inspect(verbose.get(), content="Some(false)")
}

///|
test "env: int from env" {
  let p = Parser::new(dashdash=false)
  let port = p.int(name="port", default=8080, env="PORT")
  ignore(p.parse([], env={ "PORT": "9000" }))
  inspect(port.get(), content="Some(9000)")
}

///|
test "env: is_set true when value from env" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={ "PORT": "9000" }))
  inspect(port.is_set(), content="true")
}

///|
test "env: is_set false when no env and no CLI" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={}))
  inspect(port.is_set(), content="false")
}

///|
test "env: required satisfied by env value" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  p.required(port.as_ref())
  ignore(p.parse([], env={ "PORT": "9000" }))
  inspect(
    port.get(),
    content=(
      #|Some("9000")
    ),
  )
}

///|
test "env: count from env" {
  let p = Parser::new(dashdash=false)
  let verbose = p.count(name="verbose", env="VERBOSE")
  ignore(p.parse([], env={ "VERBOSE": "3" }))
  inspect(verbose.get(), content="Some(3)")
}

///|
test "env: append_string from env (comma-separated)" {
  let p = Parser::new(dashdash=false)
  let includes = p.append_string(name="include", env="INCLUDES")
  ignore(p.parse([], env={ "INCLUDES": "a,b,c" }))
  inspect(
    includes.get(),
    content=(
      #|Some(["a", "b", "c"])
    ),
  )
}

///|
test "env: append_int from env (comma-separated)" {
  let p = Parser::new(dashdash=false)
  let ports = p.append_int(name="port", env="PORTS")
  ignore(p.parse([], env={ "PORTS": "80,443,8080" }))
  inspect(ports.get(), content="Some([80, 443, 8080])")
}

///|
test "env: empty env string is ignored" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={ "PORT": "" }))
  inspect(
    port.get(),
    content=(
      #|Some("8080")
    ),
  )
  inspect(port.is_set(), content="false")
}

///|
test "env: invalid flag value raises error" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="verbose", env="VERBOSE")
  let result = try? p.parse([], env={ "VERBOSE": "yes" })
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("expected true/false/1/0"), content="true")
    _ => abort("expected parse error for invalid flag env value")
  }
}

///|
test "env: invalid int value raises error" {
  let p = Parser::new(dashdash=false)
  let _ = p.int(name="port", default=8080, env="PORT")
  let result = try? p.parse([], env={ "PORT": "abc" })
  inspect(result is Err(_), content="true")
}

///|
test "env: choices validation applies to env values" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(name="format", default="json", env="FORMAT", choices=[
    "json", "yaml", "toml",
  ])
  let result = try? p.parse([], env={ "FORMAT": "xml" })
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("value must be one of"), content="true")
    _ => abort("expected choices validation error for env value")
  }
}

///|
test "env: choices validation passes for valid env value" {
  let p = Parser::new(dashdash=false)
  let format = p.string(name="format", default="json", env="FORMAT", choices=[
    "json", "yaml", "toml",
  ])
  ignore(p.parse([], env={ "FORMAT": "yaml" }))
  inspect(
    format.get(),
    content=(
      #|Some("yaml")
    ),
  )
}

///|
test "priv setter: flag setter writes cell value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  ignore(p.parse([]))
  inspect(verbose.get(), content="Some(false)")
  // priv setter で直接書き換え
  (verbose.accessor.set_value)(true)
  inspect(verbose.get(), content="Some(true)")
  // is_set は連動しない（setter の設計制約）
  inspect(verbose.is_set(), content="false")
}

///|
test "priv setter: string setter writes cell value" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  ignore(p.parse([]))
  inspect(
    host.get(),
    content=(
      #|Some("localhost")
    ),
  )
  (host.accessor.set_value)("example.com")
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "priv setter: alias shares setter with target" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let v = p.make_alias("-v", verbose)
  ignore(p.parse([]))
  // alias の setter は target と同一 cell を指す
  (v.accessor.set_value)(true)
  inspect(verbose.get(), content="Some(true)")
  inspect(v.get(), content="Some(true)")
}

///|
test "adjust: after_post transforms value when set" {
  let p = Parser::new()
  let port = p.int(name="port", default=0)
  p.adjust(port, after_post=Filter::map(fn(v) { v + 1000 }))
  ignore(p.parse(["--port", "80"]))
  inspect(port.get(), content="Some(1080)")
}

///|
test "adjust: after_post skips when not set" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  p.adjust(port, after_post=Filter::map(fn(v) { v + 1000 }))
  ignore(p.parse([]))
  // default 値には変換を掛けない
  inspect(port.get(), content="Some(8080)")
}

///|
test "adjust: after_post validation raises error" {
  let p = Parser::new()
  let port = p.int(name="port", default=0)
  p.adjust(port, after_post={
    run: fn(v) raise ParseError {
      if v > 1024 {
        v
      } else {
        raise parse_error("port must be > 1024")
      }
    },
  })
  let result : Result[_, _] = try? p.parse(["--port", "80"])
  inspect(result is Err(_), content="true")
}

///|
test "link: copies value from source to target when source is set" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  p.link(debug, source=verbose)
  ignore(p.parse(["--verbose"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(debug.get(), content="Some(true)")
}

///|
test "link: does not copy when source is not set" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  p.link(debug, source=verbose)
  ignore(p.parse([]))
  inspect(verbose.get(), content="Some(false)")
  inspect(debug.get(), content="Some(false)")
}

///|
test "link: string value forwarding" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let server = p.string(name="server", default="default-server")
  p.link(server, source=host)
  ignore(p.parse(["--host", "example.com"]))
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(
    server.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "clone: independent cell - clone set does not affect target" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let v = p.clone("--verb", verbose)
  ignore(p.parse(["--verb"]))
  assert_true(v.is_set())
  assert_false(verbose.is_set())
  inspect(v.get(), content="Some(true)")
  inspect(verbose.get(), content="Some(false)")
}

///|
test "clone: independent cell - target set does not affect clone" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let v = p.clone("--verb", verbose)
  ignore(p.parse(["--verbose"]))
  assert_true(verbose.is_set())
  assert_false(v.is_set())
  inspect(verbose.get(), content="Some(true)")
  inspect(v.get(), content="Some(false)")
}

///|
test "link: overwrites target when both source and target are set" {
  let p = Parser::new()
  let src = p.string(name="source", default="s-default")
  let tgt = p.string(name="target", default="t-default")
  p.link(tgt, source=src)
  ignore(p.parse(["--source", "from-src", "--target", "from-tgt"]))
  // source が set なので target は source の値で上書きされる
  inspect(
    tgt.get(),
    content=(
      #|Some("from-src")
    ),
  )
}

///|
test "clone: both unused" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.clone("--verb", verbose)
  ignore(p.parse([]))
  inspect(verbose.is_set(), content="false")
  inspect(verb.is_set(), content="false")
  inspect(verbose.get(), content="Some(false)")
  inspect(verb.get(), content="Some(false)")
}

///|
test "clone: both set independently" {
  let p = Parser::new()
  let port = p.int(name="port", default=80)
  let clone_port = p.clone("--port2", port)
  ignore(p.parse(["--port", "3000", "--port2", "8080"]))
  inspect(port.get(), content="Some(3000)")
  inspect(clone_port.get(), content="Some(8080)")
}

///|
test "clone: string independent cell" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let host2 = p.clone("--host2", host)
  ignore(p.parse(["--host2", "example.com"]))
  inspect(
    host.get(),
    content=(
      #|Some("localhost")
    ),
  )
  inspect(
    host2.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "adjust: multiple adjusts on same target execute in order" {
  let p = Parser::new()
  let val = p.int(name="val", default=0)
  p.adjust(val, after_post=Filter::map(fn(v) { v * 2 }))
  p.adjust(val, after_post=Filter::map(fn(v) { v + 1 }))
  ignore(p.parse(["--val", "5"]))
  // 5 * 2 = 10, 10 + 1 = 11 (登録順に実行)
  inspect(val.get(), content="Some(11)")
}

///|
test "clone + link: clone with independent forwarding" {
  let p = Parser::new()
  let src = p.flag(name="source")
  let cloned = p.clone("--cloned", src)
  let tgt = p.flag(name="target")
  p.link(tgt, source=cloned)
  ignore(p.parse(["--cloned"]))
  inspect(cloned.is_set(), content="true")
  inspect(tgt.get(), content="Some(true)")
}

///|
test "practical: deprecated alias with adjust validation" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  let _old_port = p.deprecated("--old-port", port, msg="Use --port instead")
  p.adjust(port, after_post={
    run: fn(v) raise ParseError {
      if v >= 1 && v <= 65535 {
        v
      } else {
        raise parse_error("port must be 1-65535")
      }
    },
  })
  // deprecated alias でもパースは成功し、adjust の検証も通る
  ignore(p.parse(["--old-port", "3000"]))
  inspect(port.get(), content="Some(3000)")
  let warnings = p.deprecated_warnings()
  inspect(warnings.length(), content="1")
}

///|
test "practical: link for verbose implies debug" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  // --verbose が指定されたら --debug も自動で有効にする
  p.link(debug, source=verbose)
  ignore(p.parse(["--verbose"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(debug.get(), content="Some(true)")
  inspect(verbose.is_set(), content="true")
  // debug は link で値が書き込まれるが is_set は false（パースで set されたわけではない）
  inspect(debug.is_set(), content="false")
}

///|
test "practical: clone + adjust for derived option" {
  let p = Parser::new()
  let port = p.int(name="port", default=80)
  let secure_port = p.clone("--secure-port", port)
  // secure-port には +443 のオフセットを付ける
  p.adjust(secure_port, after_post=Filter::map(fn(v) { v + 443 }))
  ignore(p.parse(["--secure-port", "100"]))
  inspect(secure_port.get(), content="Some(543)")
  // clone は独立 cell: port は影響を受けない
  inspect(port.get(), content="Some(80)")
}

// ===== ValCell / Accessor tests (DR-045) =====

///|
test "ValCell: new creates cell with default value and committed=false" {
  let vc : ValCell[Int] = ValCell::new(Val(42))
  assert_eq(vc.cell.val, 42)
  assert_eq(vc.committed.val, false)
}

///|
test "ValCell: accessor get returns cell value" {
  let vc = ValCell::new(Val(10))
  let acc = vc.accessor()
  assert_eq((acc.get)(), 10)
}

///|
test "ValCell: accessor set updates value and committed" {
  let vc = ValCell::new(Val(0))
  let acc = vc.accessor()
  (acc.set)(99)
  assert_eq((acc.get)(), 99)
  assert_eq(vc.committed.val, true)
}

///|
test "ValCell: accessor set_value updates value without committed" {
  let vc = ValCell::new(Val(0))
  let acc = vc.accessor()
  (acc.set_value)(99)
  assert_eq((acc.get)(), 99)
  assert_eq(vc.committed.val, false)
}

///|
test "ValCell: accessor reset restores default and clears committed" {
  let vc = ValCell::new(Val(42))
  let acc = vc.accessor()
  (acc.set)(100)
  assert_eq((acc.get)(), 100)
  assert_eq(vc.committed.val, true)
  (acc.reset)()
  assert_eq((acc.get)(), 42)
  assert_eq(vc.committed.val, false)
}

///|
test "ValCell: clone creates independent cell with same default" {
  let vc1 = ValCell::new(Val(5))
  let acc1 = vc1.accessor()
  (acc1.set)(10)
  let vc2 = vc1.clone()
  let acc2 = vc2.accessor()
  // vc2 is independent: default value, committed=false
  assert_eq((acc2.get)(), 5)
  assert_eq(vc2.committed.val, false)
  // vc1 is unchanged
  assert_eq((acc1.get)(), 10)
  assert_eq(vc1.committed.val, true)
}

///|
test "ValCell: multiple accessors share same cell" {
  let vc = ValCell::new(Val(0))
  let acc1 = vc.accessor()
  let acc2 = vc.accessor()
  (acc1.set)(42)
  assert_eq((acc2.get)(), 42)
  assert_eq(vc.committed.val, true)
}

///|
test "ValCell: set → reset → set cycle" {
  let vc = ValCell::new(Val(42))
  let acc = vc.accessor()
  (acc.set)(99)
  assert_eq((acc.get)(), 99)
  assert_eq(vc.committed.val, true)
  (acc.reset)()
  assert_eq((acc.get)(), 42)
  assert_eq(vc.committed.val, false)
  (acc.set)(77)
  assert_eq((acc.get)(), 77)
  assert_eq(vc.committed.val, true)
}

///|
test "ValCell: set_commit only updates committed without changing value" {
  let vc = ValCell::new(Val(42))
  let acc = vc.accessor()
  // 初期状態: committed = false
  assert_eq(vc.committed.val, false)
  assert_eq((acc.get)(), 42)
  // set_value で値を変えてから set_commit
  (acc.set_value)(99)
  assert_eq(vc.committed.val, false) // set_value は committed を変えない
  assert_eq((acc.get)(), 99)
  (acc.set_commit)()
  assert_eq(vc.committed.val, true) // set_commit で committed = true
  assert_eq((acc.get)(), 99) // 値は set_value で設定した 99 のまま
  // reset で committed と値の両方がデフォルトに戻る
  (acc.reset)()
  assert_eq(vc.committed.val, false)
  assert_eq((acc.get)(), 42) // 99 → 42 に戻ったことで reset が効いた証明
}

///|
test "ValCell: clone bidirectional independence" {
  let vc1 = ValCell::new(Val(0))
  let acc1 = vc1.accessor()
  let vc2 = vc1.clone()
  let acc2 = vc2.accessor()
  // vc1 → vc2 独立
  (acc1.set)(10)
  assert_eq((acc2.get)(), 0)
  assert_eq(vc2.committed.val, false)
  // vc2 → vc1 独立
  (acc2.set)(20)
  assert_eq((acc1.get)(), 10)
  assert_eq(vc1.committed.val, true)
}

///|
test "ValCell: set_value then set updates committed" {
  let vc = ValCell::new(Val(0))
  let acc = vc.accessor()
  // set_value: 値は変わるが committed は false
  (acc.set_value)(50)
  assert_eq((acc.get)(), 50)
  assert_eq(vc.committed.val, false)
  // set: 値も committed も更新
  (acc.set)(100)
  assert_eq((acc.get)(), 100)
  assert_eq(vc.committed.val, true)
}

///|
test "ValCell: reset on shared accessors propagates" {
  let vc = ValCell::new(Val(0))
  let acc1 = vc.accessor()
  let acc2 = vc.accessor()
  (acc1.set)(42)
  assert_eq((acc2.get)(), 42)
  assert_eq(vc.committed.val, true)
  (acc1.reset)()
  assert_eq((acc2.get)(), 0)
  assert_eq(vc.committed.val, false)
}

///|
test "link: propagate_set=true updates target is_set" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  p.link(debug, source=verbose, propagate_set=true)
  ignore(p.parse(["--verbose"]))
  assert_true(verbose.is_set())
  assert_true(debug.is_set()) // propagate_set=true なので debug.is_set() も true
  inspect(debug.get(), content="Some(true)")
}

///|
test "env: subcmd env option gets value from parent env map" {
  let p = Parser::new()
  let sub = p.sub(name="serve")
  let port = sub.int(name="port", default=8080, env="PORT")
  ignore(p.parse(["serve"], env={ "PORT": "9000" }))
  inspect(port.get(), content="Some(9000)")
  inspect(port.is_set(), content="true")
}

///|
test "env: subcmd CLI arg takes precedence over env" {
  let p = Parser::new()
  let sub = p.sub(name="serve")
  let port = sub.int(name="port", default=8080, env="PORT")
  ignore(p.parse(["serve", "--port", "3000"], env={ "PORT": "9000" }))
  inspect(port.get(), content="Some(3000)")
  inspect(port.is_set(), content="true")
}

///|
test "env: subcmd default used when neither CLI nor env specified" {
  let p = Parser::new()
  let sub = p.sub(name="serve")
  let port = sub.int(name="port", default=8080, env="PORT")
  ignore(p.parse(["serve"], env={}))
  inspect(port.get(), content="Some(8080)")
  inspect(port.is_set(), content="false")
}

///|
test "env: nested subcmd env propagation" {
  let p = Parser::new()
  let sub = p.sub(name="app")
  let inner = sub.sub(name="serve")
  let host = inner.string(name="host", default="localhost", env="HOST")
  ignore(p.parse(["app", "serve"], env={ "HOST": "example.com" }))
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(host.is_set(), content="true")
}

///|
test "alias chain: root committed propagates through chained aliases" {
  let p = Parser::new()
  let opt = p.string(name="host", default="localhost")
  let alias1 = p.make_alias("--h1", opt)
  let alias2 = p.make_alias("--h2", alias1)
  ignore(p.parse(["--h2", "example.com"]))
  // alias2 使用時: opt と alias2 の is_set が true、alias1 は false（独立 is_set）
  assert_true(opt.is_set())
  assert_true(alias2.is_set())
  assert_false(alias1.is_set())
  // 値は全て共有（alias は Accessor 共有）
  inspect(
    opt.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(
    alias1.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(
    alias2.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

// ============================================================
// Surrogate pair (Supplementary Plane) tests
// ============================================================

///|
test "levenshtein: emoji identical strings" {
  inspect(levenshtein("--😀mode", "--😀mode"), content="0")
}

///|
test "levenshtein: emoji one char diff" {
  inspect(levenshtein("--😀mode", "--😀mod"), content="1")
}

///|
test "levenshtein: emoji substitution" {
  inspect(levenshtein("--😀", "--😎"), content="1")
}

///|
test "levenshtein: ascii vs emoji" {
  inspect(levenshtein("--a", "--😀"), content="1")
}

///|
test "surrogate pair: single emoji short option" {
  let p = Parser::new()
  let opt = p.flag(name="smile", shorts="😀")
  ignore(p.parse(["-😀"]))
  inspect(p.get(opt), content="Some(true)")
}

///|
test "surrogate pair: emoji short combining two flags" {
  let p = Parser::new()
  let a = p.flag(name="smile", shorts="😀")
  let b = p.flag(name="cool", shorts="😎")
  ignore(p.parse(["-😀😎"]))
  inspect(p.get(a), content="Some(true)")
  inspect(p.get(b), content="Some(true)")
}

///|
test "surrogate pair: emoji + ascii combining" {
  let p = Parser::new()
  let v = p.flag(name="verbose", shorts="v")
  let e = p.flag(name="emoji", shorts="😀")
  ignore(p.parse(["-v😀"]))
  inspect(p.get(v), content="Some(true)")
  inspect(p.get(e), content="Some(true)")
}

///|
test "surrogate pair: emoji first then ascii combining" {
  let p = Parser::new()
  let v = p.flag(name="verbose", shorts="v")
  let e = p.flag(name="emoji", shorts="😀")
  ignore(p.parse(["-😀v"]))
  inspect(p.get(e), content="Some(true)")
  inspect(p.get(v), content="Some(true)")
}

///|
test "surrogate pair: emoji short with inline value" {
  let p = Parser::new()
  let port = p.custom(
    name="port",
    default=0,
    shorts="😀",
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["-😀3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "surrogate pair: emoji combining flag then value" {
  let p = Parser::new()
  let v = p.flag(name="verbose", shorts="v")
  let port = p.custom(
    name="port",
    default=0,
    shorts="😀",
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["-v😀3000"]))
  inspect(p.get(v), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "surrogate pair: suggest_typo with emoji option" {
  let p = Parser::new()
  let _ = p.flag(name="😀mode")
  let r : Result[ParseResult, _] = try? p.parse(["--😎mode"])
  match r {
    Err(ParseError(info)) => {
      inspect(info.message, content="unexpected argument: --😎mode")
      inspect(info.tip, content="--😀mode")
    }
    _ => fail("expected ParseError")
  }
}

// ============================================================
// Grapheme cluster (composite emoji) tests
// ============================================================

///|
test "grapheme cluster: levenshtein with flag emoji" {
  // 🇯🇵 (Regional Indicator × 2) は 1 grapheme cluster
  inspect(
    levenshtein("--\u{1F1EF}\u{1F1F5}mode", "--\u{1F1EF}\u{1F1F5}mode"),
    content="0",
  )
  inspect(
    levenshtein("--\u{1F1EF}\u{1F1F5}mode", "--\u{1F1EF}\u{1F1F5}mod"),
    content="1",
  )
}

///|
test "grapheme cluster: levenshtein with family emoji" {
  // 👨‍👩‍👧‍👦 (ZWJ sequence, 7 codepoints) は 1 grapheme cluster
  // grapheme cluster 単位なら距離1（1 cluster の置換）
  // コードポイント単位なら距離7以上になるはず
  inspect(
    levenshtein(
      "--\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}", "--\u{1F600}",
    ),
    content="1",
  )
}

///|
test "grapheme cluster: levenshtein with skin tone emoji" {
  // 👋🏽 (wave + skin tone, 2 codepoints) は 1 grapheme cluster
  // grapheme cluster 単位なら距離1（1 cluster の置換）
  // コードポイント単位なら距離2になるはず
  inspect(levenshtein("--\u{1F44B}\u{1F3FD}", "--\u{1F600}"), content="1")
}

///|
test "grapheme cluster: levenshtein flag vs flag substitution" {
  // 🇯🇵 と 🇺🇸 は各 1 grapheme cluster
  inspect(
    levenshtein("--\u{1F1EF}\u{1F1F5}", "--\u{1F1FA}\u{1F1F8}"),
    content="1",
  )
}

///|
test "grapheme cluster: long option with flag emoji" {
  let p = Parser::new()
  let opt = p.flag(name="\u{1F1EF}\u{1F1F5}mode")
  ignore(p.parse(["--\u{1F1EF}\u{1F1F5}mode"]))
  inspect(p.get(opt), content="Some(true)")
}

///|
test "grapheme cluster: long option with family emoji" {
  let p = Parser::new()
  let opt = p.string(
    name="\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}-mode",
    default="off",
  )
  ignore(
    p.parse([
      "--\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}-mode", "on",
    ]),
  )
  inspect(
    p.get(opt),
    content=(
      #|Some("on")
    ),
  )
}

///|
test "grapheme cluster: suggest_typo with flag emoji" {
  let p = Parser::new()
  let _ = p.flag(name="\u{1F1EF}\u{1F1F5}mode")
  let r : Result[ParseResult, _] = try? p.parse(["--\u{1F1EF}\u{1F1F5}mod"])
  match r {
    Err(ParseError(info)) =>
      inspect(info.tip, content="--\u{1F1EF}\u{1F1F5}mode")
    _ => fail("expected ParseError with typo suggestion")
  }
}

///|
test "grapheme cluster: eq split with flag emoji" {
  let p = Parser::new()
  let opt = p.string(name="\u{1F1EF}\u{1F1F5}mode", default="off")
  ignore(p.parse(["--\u{1F1EF}\u{1F1F5}mode=on"]))
  inspect(
    p.get(opt),
    content=(
      #|Some("on")
    ),
  )
}

// ============================================================
// Grapheme cluster short option tests (shorts Array[String] migration)
// ============================================================

///|
test "shorts grapheme cluster: flag emoji short option" {
  // 🇯🇵 (Regional Indicator × 2 = 1 grapheme cluster) を short option として使う
  let p = Parser::new()
  let opt = p.flag(name="japan", shorts="\u{1F1EF}\u{1F1F5}")
  ignore(p.parse(["-\u{1F1EF}\u{1F1F5}"]))
  inspect(p.get(opt), content="Some(true)")
}

///|
test "shorts grapheme cluster: family emoji short combining" {
  // 👨‍👩‍👧‍👦 (ZWJ seq) + v を combining
  let p = Parser::new()
  let f = p.flag(
    name="family",
    shorts="\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
  )
  let v = p.flag(name="verbose", shorts="v")
  ignore(
    p.parse(["-\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}v"]),
  )
  inspect(p.get(f), content="Some(true)")
  inspect(p.get(v), content="Some(true)")
}

///|
test "shorts grapheme cluster: skin tone short + inline value" {
  // 👋🏽 (wave + skin tone = 1 grapheme cluster) を short option として使い、inline value を取る
  let p = Parser::new()
  let port = p.custom(
    name="port",
    default=0,
    shorts="\u{1F44B}\u{1F3FD}",
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["-\u{1F44B}\u{1F3FD}3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "shorts grapheme cluster: help display" {
  let p = Parser::new()
  let _ = p.flag(
    name="japan",
    shorts="\u{1F1EF}\u{1F1F5}",
    description="Japan flag",
  )
  let help = p.generate_help()
  inspect(help.contains("-\u{1F1EF}\u{1F1F5}, --japan"), content="true")
}

///|
test "shorts grapheme cluster: multiple grapheme shorts" {
  // shorts="🇯🇵🇺🇸" = 2 grapheme clusters → -🇯🇵 と -🇺🇸 の2つの short option
  let p = Parser::new()
  let opt = p.count(name="flag", shorts="\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}")
  ignore(p.parse(["-\u{1F1EF}\u{1F1F5}"]))
  inspect(p.get(opt), content="Some(1)")
}

// === mergeable_list (DR-023) ===

///|
test "mergeable_list: overwrite — plain list replaces base" {
  // base=["x","y"], input "a,b" → ["a", "b"]（修飾子なしはフル上書き）
  let chain = Filter::mergeable_list(base=["x", "y"])
  let result : Result[Array[String], _] = try? (chain.run)("a,b")
  match result {
    Ok(v) => inspect(v, content="[\"a\", \"b\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: add — '+' prefix appends to base" {
  // base=["a","b"], input "+c" → ["a", "b", "c"]
  let chain = Filter::mergeable_list(base=["a", "b"])
  let result : Result[Array[String], _] = try? (chain.run)("+c")
  match result {
    Ok(v) => inspect(v, content="[\"a\", \"b\", \"c\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: remove — '-' prefix excludes from base" {
  // base=["a","b","c"], input "-a" → ["b", "c"]
  let chain = Filter::mergeable_list(base=["a", "b", "c"])
  let result : Result[Array[String], _] = try? (chain.run)("-a")
  match result {
    Ok(v) => inspect(v, content="[\"b\", \"c\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: mixed add/remove" {
  // base=["a","b"], input "+c,-a" → ["b", "c"]
  let chain = Filter::mergeable_list(base=["a", "b"])
  let result : Result[Array[String], _] = try? (chain.run)("+c,-a")
  match result {
    Ok(v) => inspect(v, content="[\"b\", \"c\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: custom separator" {
  // separator=":", input "a:b:c" → ["a", "b", "c"]
  let chain = Filter::mergeable_list(base=["x"], separator=":")
  let result : Result[Array[String], _] = try? (chain.run)("a:b:c")
  match result {
    Ok(v) => inspect(v, content="[\"a\", \"b\", \"c\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: add deduplicates" {
  // base=["a","b"], input "+a,+c" → ["a", "b", "c"]（a は既に存在するので no-op）
  let chain = Filter::mergeable_list(base=["a", "b"])
  let result : Result[Array[String], _] = try? (chain.run)("+a,+c")
  match result {
    Ok(v) => inspect(v, content="[\"a\", \"b\", \"c\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: remove nonexistent is no-op" {
  // base=["a","b"], input "-z" → ["a", "b"]（存在しない要素の除外は no-op）
  let chain = Filter::mergeable_list(base=["a", "b"])
  let result : Result[Array[String], _] = try? (chain.run)("-z")
  match result {
    Ok(v) => inspect(v, content="[\"a\", \"b\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: empty base with add" {
  // base=[], input "+a,+b" → ["a", "b"]
  let chain = Filter::mergeable_list()
  let result : Result[Array[String], _] = try? (chain.run)("+a,+b")
  match result {
    Ok(v) => inspect(v, content="[\"a\", \"b\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: rest expansion with '...'" {
  // base=["a","b","c"], input "x,...,-b" → ["x", "a", "c"]
  // ... expands remaining base items (not yet listed), then -b removes
  let chain = Filter::mergeable_list(base=["a", "b", "c"])
  let result : Result[Array[String], _] = try? (chain.run)("x,...,-b")
  match result {
    Ok(v) => inspect(v, content="[\"x\", \"a\", \"c\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: rest at end" {
  // base=["a","b","c"], input "x,..." → ["x", "a", "b", "c"]
  // x は base にないので ... は全 base 要素を展開
  let chain = Filter::mergeable_list(base=["a", "b", "c"])
  let result : Result[Array[String], _] = try? (chain.run)("x,...")
  match result {
    Ok(v) => inspect(v, content="[\"x\", \"a\", \"b\", \"c\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "mergeable_list: rest with reorder" {
  // base=["a","b","c"], input "c,..." → ["c", "a", "b"]
  // c が先頭、... で残り(a,b)を展開
  let chain = Filter::mergeable_list(base=["a", "b", "c"])
  let result : Result[Array[String], _] = try? (chain.run)("c,...")
  match result {
    Ok(v) => inspect(v, content="[\"c\", \"a\", \"b\"]")
    Err(_) => fail("expected Ok")
  }
}

// === file コンビネータ ===

///|
test "file: value specified" {
  let p = Parser::new()
  let config = p.file(
    name="config",
    default="",
    default_path="./config.toml",
    description="config file path",
  )
  p.parse(["--config", "/etc/app.conf"]) |> ignore
  inspect(config.get(), content="Some(\"/etc/app.conf\")")
}

///|
test "file: flag only uses default_path (implicit_value)" {
  let p = Parser::new()
  let config = p.file(
    name="config",
    default="",
    default_path="./config.toml",
    description="config file path",
  )
  p.parse(["--config"]) |> ignore
  inspect(config.get(), content="Some(\"./config.toml\")")
}

///|
test "file: not specified uses default" {
  let p = Parser::new()
  let config = p.file(
    name="config",
    default="",
    default_path="./config.toml",
    description="config file path",
  )
  p.parse([]) |> ignore
  inspect(config.get(), content="Some(\"\")")
}

///|
test "file: shorts support" {
  let p = Parser::new()
  let config = p.file(
    name="config",
    default="",
    default_path="./config.toml",
    shorts="c",
  )
  p.parse(["-c", "/path/to/file"]) |> ignore
  inspect(config.get(), content="Some(\"/path/to/file\")")
}

///|
test "file: equals syntax" {
  let p = Parser::new()
  let config = p.file(name="config", default="", default_path="./config.toml")
  p.parse(["--config=/path/to/file"]) |> ignore
  inspect(config.get(), content="Some(\"/path/to/file\")")
}

// === env Phase 3: env_prefix テスト ===

///|
test "env_prefix: basic prefix applied to env lookup" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  let port = p.int(name="port", default=8080, env="PORT")
  ignore(p.parse([], env={ "MYAPP_PORT": "9000" }))
  inspect(port.get(), content="Some(9000)")
  inspect(port.is_set(), content="true")
}

///|
test "env_prefix: unprefixed env var is not matched" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  let port = p.int(name="port", default=8080, env="PORT")
  ignore(p.parse([], env={ "PORT": "9000" }))
  // prefix が設定されているので素の PORT は無視される
  inspect(port.get(), content="Some(8080)")
  inspect(port.is_set(), content="false")
}

///|
test "env_prefix: no prefix behaves as before" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080, env="PORT")
  ignore(p.parse([], env={ "PORT": "9000" }))
  inspect(port.get(), content="Some(9000)")
  inspect(port.is_set(), content="true")
}

///|
test "env_prefix: CLI takes precedence over prefixed env" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  let port = p.int(name="port", default=8080, env="PORT")
  ignore(p.parse(["--port", "3000"], env={ "MYAPP_PORT": "9000" }))
  inspect(port.get(), content="Some(3000)")
  inspect(port.is_set(), content="true")
}

///|
test "env_prefix: opt without env is not affected" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  let port = p.int(name="port", default=8080)
  ignore(p.parse([], env={ "MYAPP_PORT": "9000" }))
  inspect(port.get(), content="Some(8080)")
  inspect(port.is_set(), content="false")
}

///|
test "env_prefix: subcmd inherits parent prefix with nesting" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  let sub = p.sub(name="serve")
  let port = sub.int(name="port", default=8080, env="PORT")
  ignore(p.parse(["serve"], env={ "MYAPP_SERVE_PORT": "9000" }))
  inspect(port.get(), content="Some(9000)")
  inspect(port.is_set(), content="true")
}

///|
test "env_prefix: nested subcmd prefix chaining" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  let app = p.sub(name="app")
  let inner = app.sub(name="serve")
  let host = inner.string(name="host", default="localhost", env="HOST")
  ignore(
    p.parse(["app", "serve"], env={ "MYAPP_APP_SERVE_HOST": "example.com" }),
  )
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(host.is_set(), content="true")
}

///|
test "env_prefix: help shows prefixed env name" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  let _ = p.string(
    name="port",
    default="8080",
    env="PORT",
    description="Server port",
  )
  let help = p.generate_help()
  inspect(help.contains("[env: MYAPP_PORT]"), content="true")
  // 素の PORT は表示されない
  inspect(help.contains("[env: PORT]"), content="false")
}

///|
test "env_prefix: flag from prefixed env" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  let verbose = p.flag(name="verbose", env="VERBOSE")
  ignore(p.parse([], env={ "MYAPP_VERBOSE": "true" }))
  inspect(verbose.get(), content="Some(true)")
  inspect(verbose.is_set(), content="true")
}

///|
test "env_prefix: append_string from prefixed env" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  let includes = p.append_string(name="include", env="INCLUDE")
  ignore(p.parse([], env={ "MYAPP_INCLUDE": "a,b,c" }))
  inspect(
    includes.get(),
    content=(
      #|Some(["a", "b", "c"])
    ),
  )
}

// === auto_env ===

///|
test "auto_env: basic — string opt auto-bound to env" {
  let p = Parser::new()
  p.auto_env(true)
  let port = p.string(name="port", default="8080")
  ignore(p.parse([], env={ "PORT": "3000" }))
  inspect(port.get(), content="Some(\"3000\")")
  inspect(port.is_set(), content="true")
}

///|
test "auto_env: explicit env takes precedence" {
  let p = Parser::new()
  p.auto_env(true)
  let port = p.string(name="port", default="8080", env="CUSTOM_PORT")
  ignore(p.parse([], env={ "CUSTOM_PORT": "3000", "PORT": "9999" }))
  // CUSTOM_PORT should be used, not auto-generated PORT
  inspect(port.get(), content="Some(\"3000\")")
}

///|
test "auto_env: env_prefix combined" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  p.auto_env(true)
  let port = p.string(name="port", default="8080")
  ignore(p.parse([], env={ "MYAPP_PORT": "3000" }))
  inspect(port.get(), content="Some(\"3000\")")
}

///|
test "auto_env: disabled by default — no auto binding" {
  let p = Parser::new()
  // auto_env not called, default is false
  let port = p.string(name="port", default="8080")
  ignore(p.parse([], env={ "PORT": "3000" }))
  // Should use default since no env binding
  inspect(port.get(), content="Some(\"8080\")")
  inspect(port.is_set(), content="false")
}

///|
test "auto_env: hidden opt excluded" {
  let p = Parser::new()
  p.auto_env(true)
  let secret = p.string(name="secret", default="none", visibility=Hidden)
  ignore(p.parse([], env={ "SECRET": "hidden_val" }))
  // hidden opt should NOT be auto-bound
  inspect(secret.get(), content="Some(\"none\")")
  inspect(secret.is_set(), content="false")
}

///|
test "auto_env: hyphenated name converts to underscore" {
  let p = Parser::new()
  p.auto_env(true)
  let port = p.string(name="server-port", default="8080")
  ignore(p.parse([], env={ "SERVER_PORT": "3000" }))
  inspect(port.get(), content="Some(\"3000\")")
}

///|
test "auto_env: flag auto-bound" {
  let p = Parser::new()
  p.auto_env(true)
  let verbose = p.flag(name="verbose")
  ignore(p.parse([], env={ "VERBOSE": "true" }))
  inspect(verbose.get(), content="Some(true)")
  inspect(verbose.is_set(), content="true")
}

///|
test "auto_env: int auto-bound" {
  let p = Parser::new()
  p.auto_env(true)
  let count = p.int(name="count", default=0)
  ignore(p.parse([], env={ "COUNT": "42" }))
  inspect(count.get(), content="Some(42)")
}

///|
test "auto_env: count combinator auto-bound" {
  let p = Parser::new()
  p.auto_env(true)
  let verbosity = p.count(name="verbosity")
  ignore(p.parse([], env={ "VERBOSITY": "3" }))
  inspect(verbosity.get(), content="Some(3)")
}

///|
test "auto_env: append_string auto-bound" {
  let p = Parser::new()
  p.auto_env(true)
  let includes = p.append_string(name="include")
  ignore(p.parse([], env={ "INCLUDE": "a,b,c" }))
  inspect(
    includes.get(),
    content=(
      #|Some(["a", "b", "c"])
    ),
  )
}

///|
test "auto_env: CLI takes precedence over auto_env" {
  let p = Parser::new()
  p.auto_env(true)
  let port = p.string(name="port", default="8080")
  ignore(p.parse(["--port", "4000"], env={ "PORT": "3000" }))
  inspect(port.get(), content="Some(\"4000\")")
}

///|
test "auto_env: help shows auto-generated env name" {
  let p = Parser::new()
  p.auto_env(true)
  let _ = p.string(name="port", default="8080", description="Server port")
  let help = p.generate_help()
  inspect(help.contains("[env: PORT]"), content="true")
}

///|
test "auto_env: help with env_prefix shows prefixed auto env" {
  let p = Parser::new()
  p.env_prefix("MYAPP")
  p.auto_env(true)
  let _ = p.string(name="port", default="8080", description="Server port")
  let help = p.generate_help()
  inspect(help.contains("[env: MYAPP_PORT]"), content="true")
}

///|
test "auto_env: subcmd inherits auto_env" {
  let p = Parser::new()
  p.auto_env(true)
  let child = p.sub(name="serve")
  let port = child.string(name="port", default="8080")
  ignore(p.parse(["serve"], env={ "PORT": "3000" }))
  inspect(port.get(), content="Some(\"3000\")")
}

///|
test "auto_env: float auto-bound" {
  let p = Parser::new()
  p.auto_env(true)
  let rate = p.float(name="rate", default=1.0)
  ignore(p.parse([], env={ "RATE": "2.5" }))
  inspect(rate.get(), content="Some(2.5)")
}

///|
test "auto_env: boolean auto-bound" {
  let p = Parser::new()
  p.auto_env(true)
  let debug = p.boolean(name="debug", default=false)
  ignore(p.parse([], env={ "DEBUG": "true" }))
  inspect(debug.get(), content="Some(true)")
}

// === Visibility enum テスト ===

///|
test "visibility: Visible option shown in help (default)" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose output")
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("--verbose"), content="true")
      inspect(text.contains("Verbose output"), content="true")
    }
    _ => fail("expected HelpRequested")
  }
}

///|
test "visibility: Hidden option not shown in help" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose output")
  let _ = p.flag(name="secret", description="Secret option", visibility=Hidden)
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("--verbose"), content="true")
      inspect(text.contains("--secret"), content="false")
      inspect(text.contains("Secret option"), content="false")
    }
    _ => fail("expected HelpRequested")
  }
}

///|
test "visibility: Hidden option still works for parsing" {
  let p = Parser::new()
  let secret = p.flag(
    name="secret",
    description="Secret option",
    visibility=Hidden,
  )
  ignore(p.parse(["--secret"]))
  inspect(secret.get(), content="Some(true)")
}

///|
test "visibility: Advanced option not shown in help" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose output")
  let _ = p.string(
    name="internal-format",
    default="json",
    description="Internal format",
    visibility=Advanced,
  )
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("--verbose"), content="true")
      inspect(text.contains("--internal-format"), content="false")
      inspect(text.contains("Internal format"), content="false")
    }
    _ => fail("expected HelpRequested")
  }
}

///|
test "visibility: Advanced option still works for parsing" {
  let p = Parser::new()
  let fmt = p.string(
    name="internal-format",
    default="json",
    description="Internal format",
    visibility=Advanced,
  )
  ignore(p.parse(["--internal-format", "yaml"]))
  inspect(fmt.get(), content="Some(\"yaml\")")
}

///|
test "visibility: Hidden option not shown in usage" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="secret", visibility=Hidden)
  let usage = p.generate_usage()
  // Hidden option should not cause [OPTIONS] to appear
  inspect(usage.contains("[OPTIONS]"), content="false")
}

///|
test "visibility: Advanced option not shown in usage" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="debug", visibility=Advanced)
  let usage = p.generate_usage()
  // Advanced option should not cause [OPTIONS] to appear
  inspect(usage.contains("[OPTIONS]"), content="false")
}

///|
test "visibility: Visible option shown in usage" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="verbose")
  let usage = p.generate_usage()
  inspect(usage.contains("[OPTIONS]"), content="true")
}

///|
test "visibility: auto_env excludes Advanced opt" {
  let p = Parser::new()
  p.auto_env(true)
  let internal = p.string(name="internal", default="none", visibility=Advanced)
  ignore(p.parse([], env={ "INTERNAL": "test_val" }))
  // Advanced opt should NOT be auto-bound (same as Hidden)
  inspect(internal.get(), content="Some(\"none\")")
  inspect(internal.is_set(), content="false")
}

///|
test "visibility: Hidden option not shown in error help line" {
  let p = Parser::new()
  let _ = p.string(name="secret", default="", visibility=Hidden)
  let result : Result[ParseResult, _] = try? p.parse(["--secrt"])
  match result {
    Err(ParseError(info)) => {
      // typo suggestion still works
      inspect(info.tip, content="--secret")
      // but help line for hidden option is not shown
      inspect(info.to_string().contains("help:"), content="false")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "visibility: derive Show/Eq for Visibility" {
  inspect(Visibility::Visible, content="Visible")
  inspect(Visibility::Advanced, content="Advanced")
  inspect(Visibility::Hidden, content="Hidden")
  inspect(Visibility::Visible == Visibility::Visible, content="true")
  inspect(Visibility::Visible == Visibility::Hidden, content="false")
  inspect(Visibility::Advanced == Visibility::Advanced, content="true")
}
