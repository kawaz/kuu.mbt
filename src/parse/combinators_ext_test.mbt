// ======== count コンビネータ ========

///|
test "count: --verbose --verbose --verbose → 3" {
  let p = @core.Parser::new()
  let verbose = p.count(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose", "--verbose", "--verbose"], o)
  assert_eq!((verbose.getter)(0), 3)
}

///|
test "count: --verbose=5 → 5（直接数値指定）" {
  let p = @core.Parser::new()
  let verbose = p.count(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose=5"], o)
  assert_eq!((verbose.getter)(0), 5)
}

///|
test "count: -vvv → 3（ショート結合）" {
  let p = @core.Parser::new()
  let verbose = p.count(name="verbose", shorts=[{ char: 'v' }])
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["-vvv"], o)
  assert_eq!((verbose.getter)(0), 3)
}

///|
test "count: --verbose --verbose --no-verbose → 0（Negate リセット）" {
  let p = @core.Parser::new()
  let verbose = p.count(
    name="verbose",
    inversion=Some(@core.FlagInversion::No),
  )
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose", "--verbose", "--no-verbose"], o)
  assert_eq!((verbose.getter)(0), 0)
}

///|
test "count: --verbose=5 --verbose → 6（絶対値セット後の累積）" {
  let p = @core.Parser::new()
  let verbose = p.count(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose=5", "--verbose"], o)
  assert_eq!((verbose.getter)(0), 6)
}

///|
test "count: 未指定 → 0" {
  let p = @core.Parser::new()
  let verbose = p.count(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, [], o)
  assert_eq!((verbose.getter)(0), 0)
}

// ======== append コンビネータ ========

///|
test "append: --tag a --tag b --tag c → [a, b, c]" {
  let p = @core.Parser::new()
  let tag = p.append(name="tag")
  let o = @core.opts([tag.to_opts()])
  @parse.parse(p, ["--tag", "a", "--tag", "b", "--tag", "c"], o)
  assert_eq!((tag.getter)(0), ["a", "b", "c"])
}

///|
test "append: 未指定 → []" {
  let p = @core.Parser::new()
  let tag = p.append(name="tag")
  let o = @core.opts([tag.to_opts()])
  @parse.parse(p, [], o)
  assert_eq!((tag.getter)(0), ([] : Array[String]))
}

///|
test "append: --tag x → [x]（1つだけ）" {
  let p = @core.Parser::new()
  let tag = p.append(name="tag")
  let o = @core.opts([tag.to_opts()])
  @parse.parse(p, ["--tag", "x"], o)
  assert_eq!((tag.getter)(0), ["x"])
}

///|
test "append: --tag a --tag b --no-tag --tag c → [c]（Negate でリセット後に再追加）" {
  let p = @core.Parser::new()
  let tag = p.append(
    name="tag",
    inversion=Some(@core.FlagInversion::No),
  )
  let o = @core.opts([tag.to_opts()])
  @parse.parse(
    p, ["--tag", "a", "--tag", "b", "--no-tag", "--tag", "c"], o,
  )
  assert_eq!((tag.getter)(0), ["c"])
}

// ======== optional_value コンビネータ ========

///|
test "optional_value: --color → Some(auto)（デフォルト値）" {
  let p = @core.Parser::new()
  let color = p.optional_value(name="color", default_value="auto")
  let o = @core.opts([color.to_opts()])
  @parse.parse(p, ["--color"], o)
  assert_eq!((color.getter)(0), Some("auto"))
}

///|
test "optional_value: --color=always → Some(always)" {
  let p = @core.Parser::new()
  let color = p.optional_value(name="color", default_value="auto")
  let o = @core.opts([color.to_opts()])
  @parse.parse(p, ["--color=always"], o)
  assert_eq!((color.getter)(0), Some("always"))
}

///|
test "optional_value: --color --no-color → None（Negate）" {
  let p = @core.Parser::new()
  let color = p.optional_value(
    name="color",
    default_value="auto",
    inversion=Some(@core.FlagInversion::No),
  )
  let o = @core.opts([color.to_opts()])
  // --color で Some("auto") → --no-color で None
  @parse.parse(p, ["--color", "--no-color"], o)
  assert_eq!((color.getter)(0), None)
}

///|
test "optional_value: 未指定 → None" {
  let p = @core.Parser::new()
  let color = p.optional_value(name="color", default_value="auto")
  let o = @core.opts([color.to_opts()])
  @parse.parse(p, [], o)
  assert_eq!((color.getter)(0), None)
}

// ======== custom コンビネータ ========

///|
test "custom: カスタム reducer で独自ロジック" {
  let p = @core.Parser::new()
  // カスタム: 値を大文字化して格納する
  let upper = p.custom(
    name="upper",
    initial=@core.InitialValue::Val((None : String?)),
    reducer=fn(ctx) {
      match ctx.action {
        Value(Some(s)) => Some(Some(s.to_upper()))
        Negate => Some(None)
        _ => None
      }
    },
    meta=@core.OptMeta::{
      name: "upper",
      kind: @core.Kind::Option,
      help: "uppercase value",
      shorts: [],
      aliases: [],
      inversion: None,
      env: None,
      auto_env: None,
      choices: [],
      value_name: "STRING",
      required: false,
      visibility: @core.Visibility::Visible,
      global: false,
      greedy: false,
    },
  )
  let o = @core.opts([upper.to_opts()])
  @parse.parse(p, ["--upper", "hello"], o)
  assert_eq!((upper.getter)(0), Some("hello".to_upper()))
}
