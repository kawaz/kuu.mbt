///|
test "exclusive: 1つだけ設定 → OK" {
  let p = @core.Parser::new()
  let format = p.string(name="format")
  let output = p.string(name="output")
  let fo = format.to_opts()
  let oo = output.to_opts()
  @validate.exclusive(p, [fo, oo])
  let o = @core.opts([fo, oo])
  @parse.parse(p, ["--format", "json"], o)
  assert_eq((format.getter)(0), Some("json"))
  assert_eq((output.getter)(0), None)
}

///|
test "exclusive: 2つ設定 → ArgumentConflict エラー" {
  let p = @core.Parser::new()
  let format = p.string(name="format")
  let output = p.string(name="output")
  let fo = format.to_opts()
  let oo = output.to_opts()
  @validate.exclusive(p, [fo, oo])
  let o = @core.opts([fo, oo])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(p, ["--format", "json", "--output", "file.txt"], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::InvalidValue)
  }
  assert_eq(result, Err(@core.ErrorKind::ArgumentConflict))
}

///|
test "exclusive: 0個設定 → OK (required=false)" {
  let p = @core.Parser::new()
  let format = p.string(name="format")
  let output = p.string(name="output")
  let fo = format.to_opts()
  let oo = output.to_opts()
  @validate.exclusive(p, [fo, oo])
  let o = @core.opts([fo, oo])
  @parse.parse(p, [], o)
  assert_eq((format.getter)(0), None)
  assert_eq((output.getter)(0), None)
}

///|
test "exclusive(required=true): 0個 → MissingRequired エラー" {
  let p = @core.Parser::new()
  let format = p.string(name="format")
  let output = p.string(name="output")
  let fo = format.to_opts()
  let oo = output.to_opts()
  @validate.exclusive(p, [fo, oo], required=true)
  let o = @core.opts([fo, oo])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(p, [], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::InvalidValue)
  }
  assert_eq(result, Err(@core.ErrorKind::MissingRequired))
}

///|
test "exclusive(required=true): ちょうど1つ → OK" {
  let p = @core.Parser::new()
  let format = p.string(name="format")
  let output = p.string(name="output")
  let fo = format.to_opts()
  let oo = output.to_opts()
  @validate.exclusive(p, [fo, oo], required=true)
  let o = @core.opts([fo, oo])
  @parse.parse(p, ["--output", "file.txt"], o)
  assert_eq((format.getter)(0), None)
  assert_eq((output.getter)(0), Some("file.txt"))
}

///|
test "at_least_one: 0個 → MissingRequired エラー" {
  let p = @core.Parser::new()
  let format = p.string(name="format")
  let output = p.string(name="output")
  let fo = format.to_opts()
  let oo = output.to_opts()
  @validate.at_least_one(p, [fo, oo])
  let o = @core.opts([fo, oo])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(p, [], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::InvalidValue)
  }
  assert_eq(result, Err(@core.ErrorKind::MissingRequired))
}

///|
test "at_least_one: 1つ以上 → OK" {
  let p = @core.Parser::new()
  let format = p.string(name="format")
  let output = p.string(name="output")
  let fo = format.to_opts()
  let oo = output.to_opts()
  @validate.at_least_one(p, [fo, oo])
  let o = @core.opts([fo, oo])
  @parse.parse(p, ["--format", "json", "--output", "file.txt"], o)
  assert_eq((format.getter)(0), Some("json"))
  assert_eq((output.getter)(0), Some("file.txt"))
}

///|
test "check_required: required=true のオプションが未設定 → MissingRequired エラー" {
  let p = @core.Parser::new()
  let name = p.string(name="name", required=true)
  let no = name.to_opts()
  @validate.check_required(p, no)
  let o = @core.opts([no])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(p, [], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::InvalidValue)
  }
  assert_eq(result, Err(@core.ErrorKind::MissingRequired))
}

///|
test "check_required: required=true のオプションが設定済み → OK" {
  let p = @core.Parser::new()
  let name = p.string(name="name", required=true)
  let no = name.to_opts()
  @validate.check_required(p, no)
  let o = @core.opts([no])
  @parse.parse(p, ["--name", "hello"], o)
  assert_eq((name.getter)(0), Some("hello"))
}

///|
test "exclusive: 空配列は制約登録されず正常終了" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @validate.exclusive(p, [])
  @parse.parse(p, ["--verbose"], o)
  assert_eq((verbose.getter)(0), true)
}

///|
test "at_least_one: 空配列は制約登録されず正常終了" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @validate.at_least_one(p, [])
  @parse.parse(p, ["--verbose"], o)
  assert_eq((verbose.getter)(0), true)
}

///|
test "複合: exclusive + 通常のパース動作" {
  let p = @core.Parser::new()
  let json = p.flag(name="json")
  let yaml = p.flag(name="yaml")
  let verbose = p.flag(name="verbose")
  let jo = json.to_opts()
  let yo = yaml.to_opts()
  let vo = verbose.to_opts()
  @validate.exclusive(p, [jo, yo])
  let o = @core.opts([jo, yo, vo])
  @parse.parse(p, ["--json", "--verbose"], o)
  assert_eq((json.getter)(0), true)
  assert_eq((yaml.getter)(0), false)
  assert_eq((verbose.getter)(0), true)
}
