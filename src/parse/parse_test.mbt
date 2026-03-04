///|
test "単一フラグ: --verbose" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(["--verbose"], o)
  assert_eq((verbose.getter)(0), true)
}

///|
test "フラグ + 値オプション: --verbose --port 8080" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let port = p.int(name="port")
  let o = @core.opts([verbose.to_opts(), port.to_opts()])
  @parse.parse(["--verbose", "--port", "8080"], o)
  assert_eq((verbose.getter)(0), true)
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "eq形式: --port=8080" {
  let p = @core.Parser::new()
  let port = p.int(name="port")
  let o = @core.opts([port.to_opts()])
  @parse.parse(["--port=8080"], o)
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "反転フラグ: --no-verbose" {
  let p = @core.Parser::new()
  let verbose = p.flag(
    name="verbose",
    inversion=Some(@core.FlagInversion::No),
  )
  // まず true にしてから反転テスト
  (verbose.setter)(0, true)
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(["--no-verbose"], o)
  assert_eq((verbose.getter)(0), false)
}

///|
test "ショートオプション: -v (flag)" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", shorts=[{ char: 'v' }])
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(["-v"], o)
  assert_eq((verbose.getter)(0), true)
}

///|
test "Positional: ファイル名" {
  let p = @core.Parser::new()
  let file = p.positional(name="file")
  let o = @core.opts([file.to_opts()])
  @parse.parse(["test.txt"], o)
  assert_eq((file.getter)(0), Some("test.txt"))
}

///|
test "-- セパレータ: --verbose -- --not-a-flag" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let file = p.positional(name="file")
  let o = @core.opts([verbose.to_opts(), file.to_opts()])
  @parse.parse(["--verbose", "--", "--not-a-flag"], o)
  assert_eq((verbose.getter)(0), true)
  assert_eq((file.getter)(0), Some("--not-a-flag"))
}

///|
test "未知オプション: --unknown → UnknownOption エラー" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(["--unknown"], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::UnknownOption)
  }
  match result {
    Err(@core.ErrorKind::UnknownOption) => ()
    Err(other) => fail("expected UnknownOption, got \{other}")
    Ok(_) => fail("expected ParseError for unknown option")
  }
}

///|
test "値不足: --port → MissingValue エラー" {
  let p = @core.Parser::new()
  let port = p.int(name="port")
  let o = @core.opts([port.to_opts()])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(["--port"], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::UnknownOption)
  }
  match result {
    Err(@core.ErrorKind::MissingValue) => ()
    Err(other) => fail("expected MissingValue, got \{other}")
    Ok(_) => fail("expected ParseError for missing value")
  }
}

///|
test "string値オプション: --output file.txt" {
  let p = @core.Parser::new()
  let output = p.string(name="output")
  let o = @core.opts([output.to_opts()])
  @parse.parse(["--output", "file.txt"], o)
  assert_eq((output.getter)(0), Some("file.txt"))
}

///|
test "string eq形式: --output=file.txt" {
  let p = @core.Parser::new()
  let output = p.string(name="output")
  let o = @core.opts([output.to_opts()])
  @parse.parse(["--output=file.txt"], o)
  assert_eq((output.getter)(0), Some("file.txt"))
}

///|
test "複数 Positional: 順番通り" {
  let p = @core.Parser::new()
  let src = p.positional(name="src")
  let dst = p.positional(name="dst")
  let o = @core.opts([src.to_opts(), dst.to_opts()])
  @parse.parse(["a.txt", "b.txt"], o)
  assert_eq((src.getter)(0), Some("a.txt"))
  assert_eq((dst.getter)(0), Some("b.txt"))
}

///|
test "プレフィックス一致: --verb → --verbose" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(["--verb"], o)
  assert_eq((verbose.getter)(0), true)
}

///|
test "ショートオプション結合: -vp は複数フラグ" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", shorts=[{ char: 'v' }])
  let pretty = p.flag(name="pretty", shorts=[{ char: 'p' }])
  let o = @core.opts([verbose.to_opts(), pretty.to_opts()])
  @parse.parse(["-vp"], o)
  assert_eq((verbose.getter)(0), true)
  assert_eq((pretty.getter)(0), true)
}

///|
test "引数なし: パースエラーなし" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse([], o)
  assert_eq((verbose.getter)(0), false)
}

///|
test "サブコマンド基本パース: cmd1 → cmd1 が true" {
  let p = @core.Parser::new()
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([]))
  let o = @core.opts([cmd1.to_opts()])
  @parse.parse(["cmd1"], o)
  assert_eq((cmd1.getter)(0), true)
}

///|
test "サブコマンド + 子オプション: cmd1 --port 8080" {
  let p = @core.Parser::new()
  let port = p.int(name="port")
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([port.to_opts()]))
  let o = @core.opts([cmd1.to_opts()])
  @parse.parse(["cmd1", "--port", "8080"], o)
  assert_eq((cmd1.getter)(0), true)
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "プレフィックスマッチ曖昧エラー: --ver → AmbiguousMatch" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let version = p.flag(name="version")
  let o = @core.opts([verbose.to_opts(), version.to_opts()])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(["--ver"], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::UnknownOption)
  }
  match result {
    Err(@core.ErrorKind::AmbiguousMatch) => ()
    Err(other) => fail("expected AmbiguousMatch, got \{other}")
    Ok(_) => fail("expected ParseError for ambiguous match")
  }
}

///|
test "ショートオプション + 値: -p 8080" {
  let p = @core.Parser::new()
  let port = p.int(name="port", shorts=[{ char: 'p' }])
  let o = @core.opts([port.to_opts()])
  @parse.parse(["-p", "8080"], o)
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "ショートオプション値不足: -p → MissingValue" {
  let p = @core.Parser::new()
  let port = p.int(name="port", shorts=[{ char: 'p' }])
  let o = @core.opts([port.to_opts()])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(["-p"], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::UnknownOption)
  }
  match result {
    Err(@core.ErrorKind::MissingValue) => ()
    Err(other) => fail("expected MissingValue, got \{other}")
    Ok(_) => fail("expected ParseError for missing value")
  }
}

///|
test "重複オプション: --port 80 --port 443 → 後勝ち" {
  let p = @core.Parser::new()
  let port = p.int(name="port")
  let o = @core.opts([port.to_opts()])
  @parse.parse(["--port", "80", "--port", "443"], o)
  assert_eq((port.getter)(0), Some(443))
}

///|
test "--cmd1 は Command にマッチしない（UnknownOption エラー）" {
  let p = @core.Parser::new()
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([]))
  let o = @core.opts([cmd1.to_opts()])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(["--cmd1"], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::UnknownOption)
  }
  match result {
    Err(@core.ErrorKind::UnknownOption) => ()
    Err(other) => fail("expected UnknownOption, got \{other}")
    Ok(_) => fail("expected ParseError for --cmd1")
  }
}

///|
test "Positional 消費後は Command 不可: file.txt cmd1 → 両方 positional" {
  let p = @core.Parser::new()
  let file = p.positional(name="file")
  let extra = p.positional(name="extra")
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([]))
  let o = @core.opts([file.to_opts(), extra.to_opts(), cmd1.to_opts()])
  @parse.parse(["file.txt", "cmd1"], o)
  assert_eq((file.getter)(0), Some("file.txt"))
  assert_eq((extra.getter)(0), Some("cmd1"))
  assert_eq((cmd1.getter)(0), false)
}

///|
test "global オプション引き継ぎ: cmd1 --verbose" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([]))
  let o = @core.opts([verbose.to_opts(), cmd1.to_opts()])
  @parse.parse(["cmd1", "--verbose"], o)
  assert_eq((cmd1.getter)(0), true)
  assert_eq((verbose.getter)(0), true)
}

///|
test "Command エイリアス: serve → server (alias=serve) にマッチ" {
  let p = @core.Parser::new()
  let server = p.cmd(
    name="server",
    aliases=[{ name: "serve", deprecated: false }],
    children=@core.opts([]),
  )
  let o = @core.opts([server.to_opts()])
  @parse.parse(["serve"], o)
  assert_eq((server.getter)(0), true)
}

///|
test "force_positional後のオプション除外: -- の後は --port も --port も positional 扱い" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let positional1 = p.positional(name="positional1")
  let positional2 = p.positional(name="positional2")
  let o = @core.opts([verbose.to_opts(), positional1.to_opts(), positional2.to_opts()])
  @parse.parse(["--verbose", "--", "--port", "8080"], o)
  assert_eq((verbose.getter)(0), true)
  assert_eq((positional1.getter)(0), Some("--port"))
  assert_eq((positional2.getter)(0), Some("8080"))
}

///|
test "サブコマンド後親スコープ無効化: cmd1 --parent-only → UnknownOption エラー" {
  let p = @core.Parser::new()
  let parent_only = p.flag(name="parent-only")
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([]))
  let o = @core.opts([parent_only.to_opts(), cmd1.to_opts()])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(["cmd1", "--parent-only"], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::UnknownOption)
  }
  match result {
    Err(@core.ErrorKind::UnknownOption) => ()
    Err(other) => fail("expected UnknownOption, got \{other}")
    Ok(_) => fail("expected ParseError for parent-only option after subcommand")
  }
}

///|
test "Positional未登録時の余剰引数: bare token → UnexpectedArgument エラー" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(["extra-arg"], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::UnknownOption)
  }
  match result {
    Err(@core.ErrorKind::UnexpectedArgument) => ()
    Err(other) => fail("expected UnexpectedArgument, got \{other}")
    Ok(_) => fail("expected ParseError for unexpected argument")
  }
}

///|
test "中間ショートオプションが値オプション: -vp (v=フラグ, p=int) → エラー" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", shorts=[{ char: 'v' }])
  let port = p.int(name="port", shorts=[{ char: 'p' }])
  let o = @core.opts([verbose.to_opts(), port.to_opts()])
  // -vp: v はフラグ、p は値オプション。p が最後の文字で次引数がないため MissingValue エラーになる
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(["-vp"], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::UnknownOption)
  }
  match result {
    Err(_) => () // エラーになればOK（種別は問わない）
    Ok(_) => fail("expected ParseError for -vp where p requires a value")
  }
}
