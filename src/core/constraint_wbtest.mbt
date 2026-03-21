// === exclusive / required / is_set テスト ===

///|
test "exclusive flags pass when only one set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.exclusive([json.as_ref(), csv.as_ref()])
  ignore(p.parse(["--json"]))
  inspect(p.get(json), content="Some(true)")
  inspect(p.get(csv), content="Some(false)")
}

///|
test "exclusive flags error when both set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.exclusive([json.as_ref(), csv.as_ref()])
  let result : Result[_, _] = try? p.parse(["--json", "--csv"])
  inspect(result is Err(_), content="true")
}

///|
test "exclusive allows none set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.exclusive([json.as_ref(), csv.as_ref()])
  ignore(p.parse([]))
  inspect(p.get(json), content="Some(false)")
}

///|
test "required option present" {
  let p = Parser::new()
  let output = p.string(name="output", default="")
  p.required(output.as_ref())
  ignore(p.parse(["--output", "file.txt"]))
  inspect(
    p.get(output),
    content=(
      #|Some("file.txt")
    ),
  )
}

///|
test "required option missing" {
  let p = Parser::new()
  let output = p.string(name="output", default="")
  p.required(output.as_ref())
  let result : Result[_, _] = try? p.parse(["--other"])
  inspect(result is Err(_), content="true")
}

///|
test "at_least_one passes when one set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  ignore(p.parse(["--json"]))
  inspect(p.get(json), content="Some(true)")
  inspect(p.get(csv), content="Some(false)")
}

///|
test "at_least_one passes when all set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  ignore(p.parse(["--json", "--csv"]))
  inspect(p.get(json), content="Some(true)")
  inspect(p.get(csv), content="Some(true)")
}

///|
test "at_least_one error when none set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => {
      inspect(info.message.contains("at least one required"), content="true")
      inspect(info.message.contains("--json"), content="true")
      inspect(info.message.contains("--csv"), content="true")
    }
    _ => abort("expected at_least_one error")
  }
}

///|
test "at_least_one with subcommand" {
  let p = Parser::new()
  let format_opt : Ref[Opt[Bool]?] = { val: None }
  let verbose_opt : Ref[Opt[Bool]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let fmt = child.flag(name="json")
    let vrb = child.flag(name="verbose")
    child.at_least_one([fmt.as_ref(), vrb.as_ref()])
    format_opt.val = Some(fmt)
    verbose_opt.val = Some(vrb)
  })
  ignore(p.parse(["serve", "--verbose"]))
  inspect(p.get(format_opt.val.unwrap()), content="Some(false)")
  inspect(p.get(verbose_opt.val.unwrap()), content="Some(true)")
}

///|
test "is_set false for default fallback" {
  let p = Parser::new(dashdash=false)
  let color = p.string(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse([]))
  inspect(color.is_set(), content="false")
  inspect(
    p.get(color),
    content=(
      #|Some("auto")
    ),
  )
}

///|
test "is_set true for explicit value" {
  let p = Parser::new(dashdash=false)
  let color = p.string(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color", "never"]))
  inspect(color.is_set(), content="true")
  inspect(
    p.get(color),
    content=(
      #|Some("never")
    ),
  )
}

///|
test "is_set true for implicit value" {
  let p = Parser::new(dashdash=false)
  let color = p.string(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color"]))
  inspect(color.is_set(), content="true")
  inspect(
    p.get(color),
    content=(
      #|Some("always")
    ),
  )
}

// === never コンビネータテスト ===

///|
test "never rejects extra positional args" {
  let p = Parser::new(dashdash=false)
  let _file = p.positional(name="file")
  p.never()
  let result : Result[_, _] = try? p.parse(["a", "b"])
  inspect(result is Err(_), content="true")
}

///|
test "never allows exact positional count" {
  let p = Parser::new(dashdash=false)
  let file = p.positional(name="file")
  p.never()
  ignore(p.parse(["hello"]))
  inspect(
    p.get(file),
    content=(
      #|Some("hello")
    ),
  )
}

///|
test "never allows zero args" {
  let p = Parser::new(dashdash=false)
  p.never()
  ignore(p.parse([]))
}

// === コンビネータ組み合わせテスト ===

///|
test "deprecated alias satisfies required on target" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let _ = p.deprecated("--out", output, msg="use --output")
  p.required(output.as_ref())
  // deprecated 別名で target の required を満たせること
  ignore(p.parse(["--out", "file.txt"]))
  inspect(output.get(), content="Some(\"file.txt\")")
}

///|
test "deprecated alias satisfies at_least_one on target" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  let _ = p.deprecated("--legacy-json", json, msg="use --json")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  // deprecated 別名で at_least_one を満たせること
  ignore(p.parse(["--legacy-json"]))
  inspect(json.get(), content="Some(true)")
}

///|
test "deprecated alias triggers exclusive with target" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  let _ = p.deprecated("--legacy-json", json, msg="use --json")
  p.exclusive([json.as_ref(), csv.as_ref()])
  // deprecated 別名 + 別オプションで exclusive エラーになること
  let result = try? p.parse(["--legacy-json", "--csv"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("mutually exclusive"), content="true")
    _ => abort("expected exclusive error")
  }
}

///|
test "at_least_one + exclusive = exactly one" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  p.exclusive([json.as_ref(), csv.as_ref()])
  // 1つだけ → OK
  ignore(p.parse(["--json"]))
  inspect(json.get(), content="Some(true)")
}

///|
test "at_least_one + exclusive rejects none" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  p.exclusive([json.as_ref(), csv.as_ref()])
  let result = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("at least one required"), content="true")
    _ => abort("expected at_least_one error")
  }
}

///|
test "at_least_one + exclusive rejects both" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  p.exclusive([json.as_ref(), csv.as_ref()])
  let result = try? p.parse(["--json", "--csv"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("mutually exclusive"), content="true")
    _ => abort("expected exclusive error")
  }
}

// === requires（dependent options）テスト ===

///|
test "requires: source set without target is error" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(output.as_ref(), source=config.as_ref())
  let result = try? p.parse(["--config", "a.json"])
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message.contains("--output") && info.message.contains("--config"),
        content="true",
      )
    _ => abort("expected requires error")
  }
}

///|
test "requires: both set is ok" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(output.as_ref(), source=config.as_ref())
  ignore(p.parse(["--config", "a.json", "--output", "out.txt"]))
  inspect(
    config.get(),
    content=(
      #|Some("a.json")
    ),
  )
  inspect(
    output.get(),
    content=(
      #|Some("out.txt")
    ),
  )
}

///|
test "requires: neither set is ok" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(output.as_ref(), source=config.as_ref())
  ignore(p.parse([]))
  inspect(config.is_set(), content="false")
  inspect(output.is_set(), content="false")
}

///|
test "requires: target set without source is ok" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(output.as_ref(), source=config.as_ref())
  ignore(p.parse(["--output", "out.txt"]))
  inspect(output.is_set(), content="true")
}

///|
test "requires: custom error message" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(
    output.as_ref(),
    source=config.as_ref(),
    msg="--config needs --output",
  )
  let result = try? p.parse(["--config", "a.json"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("--config needs --output"), content="true")
    _ => abort("expected requires error")
  }
}

// === variation + exclusive 複合テスト ===

///|
test "variation + exclusive: --no-verbose alone is ok" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  ignore(p.parse(["--no-verbose"]))
  inspect(verbose.get(), content="Some(false)")
  inspect(verbose.is_set(), content="true")
  inspect(quiet.is_set(), content="false")
}

///|
test "variation + exclusive: --no-verbose and --quiet is exclusive error" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  let result = try? p.parse(["--no-verbose", "--quiet"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("mutually exclusive"), content="true")
    _ => abort("expected exclusive error")
  }
}

///|
test "variation + exclusive: --verbose and --quiet is exclusive error" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  let result = try? p.parse(["--verbose", "--quiet"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("mutually exclusive"), content="true")
    _ => abort("expected exclusive error")
  }
}

///|
test "variation + exclusive: neither set is ok" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  ignore(p.parse([]))
  inspect(verbose.is_set(), content="false")
  inspect(quiet.is_set(), content="false")
}

///|
test "variation + at_least_one: --no-verbose satisfies at_least_one" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.at_least_one([verbose.as_ref(), quiet.as_ref()])
  ignore(p.parse(["--no-verbose"]))
  inspect(verbose.is_set(), content="true")
}

// === requires 循環依存テスト ===

///|
test "requires circular: neither set passes silently" {
  let p = Parser::new(dashdash=false)
  let a = p.string(name="a", default="")
  let b = p.string(name="b", default="")
  p.requires(a.as_ref(), source=b.as_ref())
  p.requires(b.as_ref(), source=a.as_ref())
  // 両方未指定 → source が set でないので requires 発火しない → OK
  ignore(p.parse([]))
  inspect(a.is_set(), content="false")
  inspect(b.is_set(), content="false")
}

///|
test "requires circular: one set triggers error" {
  let p = Parser::new(dashdash=false)
  let a = p.string(name="a", default="")
  let b = p.string(name="b", default="")
  p.requires(a.as_ref(), source=b.as_ref())
  p.requires(b.as_ref(), source=a.as_ref())
  // --a だけ指定 → requires(b, source=a) で b 未セットエラー
  let result : Result[_, _] = try? p.parse(["--a", "val"])
  inspect(result is Err(_), content="true")
}

// === 矛盾制約テスト ===

///|
test "required + required + exclusive is always error" {
  // required(a) + required(b) + exclusive([a, b]) は矛盾:
  // 両方 required なので両方セットが必要だが、exclusive で排他
  let p = Parser::new(dashdash=false)
  let a = p.flag(name="a")
  let b = p.flag(name="b")
  p.required(a.as_ref())
  p.required(b.as_ref())
  p.exclusive([a.as_ref(), b.as_ref()])
  // 両方指定 → exclusive エラー
  let result1 : Result[_, _] = try? p.parse(["--a", "--b"])
  inspect(result1 is Err(_), content="true")
  // 片方だけ → required エラー（b が欠けている）
  let p2 = Parser::new(dashdash=false)
  let a2 = p2.flag(name="a")
  let b2 = p2.flag(name="b")
  p2.required(a2.as_ref())
  p2.required(b2.as_ref())
  p2.exclusive([a2.as_ref(), b2.as_ref()])
  let result2 : Result[_, _] = try? p2.parse(["--a"])
  inspect(result2 is Err(_), content="true")
  // 両方なし → required エラー（a が欠けている）
  let p3 = Parser::new(dashdash=false)
  let a3 = p3.flag(name="a")
  let b3 = p3.flag(name="b")
  p3.required(a3.as_ref())
  p3.required(b3.as_ref())
  p3.exclusive([a3.as_ref(), b3.as_ref()])
  let result3 : Result[_, _] = try? p3.parse([])
  inspect(result3 is Err(_), content="true")
}

// === 空パーサーテスト ===

///|
test "empty parser rejects unexpected argument" {
  let p = Parser::new(dashdash=false)
  // オプション0個 + 引数あり → unexpected argument エラー
  let result : Result[_, _] = try? p.parse(["something"])
  inspect(result is Err(_), content="true")
}

///|
test "empty parser accepts no arguments" {
  let p = Parser::new(dashdash=false)
  // オプション0個 + 引数なし → 成功
  ignore(p.parse([]))
}
