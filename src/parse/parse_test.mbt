///| ブラックボックステスト — parse パッケージの公開 API テスト

// ============================================================
// 1. flag 基本: ["--verbose"] -> verbose=true
// ============================================================

///|
test "parse: flag basic" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let root = @combinators.opts([@core.Opts::Node(verbose_node)])
  @parse.parse(["--verbose"], root)
  inspect((verbose_opt.getter)(0), content="true")
}

// ============================================================
// 2. flag 未指定: [] -> verbose=false (initial)
// ============================================================

///|
test "parse: flag not specified" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let root = @combinators.opts([@core.Opts::Node(verbose_node)])
  @parse.parse([], root)
  inspect((verbose_opt.getter)(0), content="false")
}

// ============================================================
// 3. string_opt 基本: ["--name", "hello"] -> name=Some("hello")
// ============================================================

///|
test "parse: string_opt basic" {
  let parser = @core.Parser::new()
  let (name_opt, name_node) = @combinators.string_opt(parser, name="name")
  let root = @combinators.opts([@core.Opts::Node(name_node)])
  @parse.parse(["--name", "hello"], root)
  inspect((name_opt.getter)(0), content="Some(\"hello\")")
}

// ============================================================
// 4. string_opt with =: ["--name=hello"] -> name=Some("hello")
// ============================================================

///|
test "parse: string_opt with equals" {
  let parser = @core.Parser::new()
  let (name_opt, name_node) = @combinators.string_opt(parser, name="name")
  let root = @combinators.opts([@core.Opts::Node(name_node)])
  @parse.parse(["--name=hello"], root)
  inspect((name_opt.getter)(0), content="Some(\"hello\")")
}

// ============================================================
// 5. int_opt 基本: ["--port", "8080"] -> port=Some(8080)
// ============================================================

///|
test "parse: int_opt basic" {
  let parser = @core.Parser::new()
  let (port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let root = @combinators.opts([@core.Opts::Node(port_node)])
  @parse.parse(["--port", "8080"], root)
  inspect((port_opt.getter)(0), content="Some(8080)")
}

// ============================================================
// 6. int_opt 不正値: ["--port", "abc"] -> ParseError::InvalidValue
// ============================================================

///|
test "parse: int_opt invalid value" {
  let parser = @core.Parser::new()
  let (_port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let root = @combinators.opts([@core.Opts::Node(port_node)])
  let result : Result[Unit, @core.ParseError] = Ok(
    @parse.parse(["--port", "abc"], root),
  ) catch {
    e => Err(e)
  }
  inspect(
    result,
    content="Err(InvalidValue(name=\"port\", value=\"abc\", reason=\"not a valid integer\"))",
  )
}

// ============================================================
// 7. positional 基本: ["file.txt"] -> pos=Some("file.txt")
// ============================================================

///|
test "parse: positional basic" {
  let parser = @core.Parser::new()
  let (pos_opt, pos_node) = @combinators.positional(parser, name="file")
  let root = @combinators.opts([@core.Opts::Node(pos_node)])
  @parse.parse(["file.txt"], root)
  inspect((pos_opt.getter)(0), content="Some(\"file.txt\")")
}

// ============================================================
// 8. 複合: ["--verbose", "--port", "8080", "file.txt"]
// ============================================================

///|
test "parse: combined options and positional" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let (port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let (pos_opt, pos_node) = @combinators.positional(parser, name="file")
  let root = @combinators.opts([
    @core.Opts::Node(verbose_node),
    @core.Opts::Node(port_node),
    @core.Opts::Node(pos_node),
  ])
  @parse.parse(["--verbose", "--port", "8080", "file.txt"], root)
  inspect((verbose_opt.getter)(0), content="true")
  inspect((port_opt.getter)(0), content="Some(8080)")
  inspect((pos_opt.getter)(0), content="Some(\"file.txt\")")
}

// ============================================================
// 9. -- セパレータ: ["--", "--verbose"] -> verbose=false, pos=Some("--verbose")
// ============================================================

///|
test "parse: double dash separator" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let (pos_opt, pos_node) = @combinators.positional(parser, name="file")
  let root = @combinators.opts([
    @core.Opts::Node(verbose_node),
    @core.Opts::Node(pos_node),
  ])
  @parse.parse(["--", "--verbose"], root)
  inspect((verbose_opt.getter)(0), content="false")
  inspect((pos_opt.getter)(0), content="Some(\"--verbose\")")
}

// ============================================================
// 10. 未知オプション: ["--unknown"] -> ParseError::UnknownOption
// ============================================================

///|
test "parse: unknown option" {
  let parser = @core.Parser::new()
  let (_verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let root = @combinators.opts([@core.Opts::Node(verbose_node)])
  let result : Result[Unit, @core.ParseError] = Ok(
    @parse.parse(["--unknown"], root),
  ) catch {
    e => Err(e)
  }
  inspect(result, content="Err(UnknownOption(\"--unknown\"))")
}

// ============================================================
// 11. 値不足: ["--port"] -> ParseError::MissingValue
// ============================================================

///|
test "parse: missing value" {
  let parser = @core.Parser::new()
  let (_port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let root = @combinators.opts([@core.Opts::Node(port_node)])
  let result : Result[Unit, @core.ParseError] = Ok(
    @parse.parse(["--port"], root),
  ) catch {
    e => Err(e)
  }
  inspect(result, content="Err(MissingValue(\"port\"))")
}

// ============================================================
// 12. ショートオプション: ["-v"] -> verbose=true
// ============================================================

///|
test "parse: short option" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose", shorts=[
    { char: 'v' },
  ])
  let root = @combinators.opts([@core.Opts::Node(verbose_node)])
  @parse.parse(["-v"], root)
  inspect((verbose_opt.getter)(0), content="true")
}

// ============================================================
// 13. エイリアスマッチ: ["--out", "file.txt"] -> output=Some("file.txt")
// ============================================================

///|
test "parse: alias match" {
  let parser = @core.Parser::new()
  let (output_opt, output_node) = @combinators.string_opt(
    parser,
    name="output",
    aliases=[{ name: "out", deprecated: false }],
  )
  let root = @combinators.opts([@core.Opts::Node(output_node)])
  @parse.parse(["--out", "file.txt"], root)
  inspect((output_opt.getter)(0), content="Some(\"file.txt\")")
}

// ============================================================
// 14. プレフィックスマッチ: ["--por", "8080"] -> port=Some(8080)
// ============================================================

///|
test "parse: prefix match" {
  let parser = @core.Parser::new()
  let (port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let root = @combinators.opts([@core.Opts::Node(port_node)])
  @parse.parse(["--por", "8080"], root)
  inspect((port_opt.getter)(0), content="Some(8080)")
}

// ============================================================
// 15. 反転パターン: ["--no-verbose"] -> verbose=false
// ============================================================

///|
test "parse: inversion no- pattern" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(
    parser,
    name="verbose",
    inversion=Some(@core.FlagInversion::No),
  )
  let root = @combinators.opts([@core.Opts::Node(verbose_node)])
  // まず --verbose で true にしてから --no-verbose で false にする
  @parse.parse(["--verbose", "--no-verbose"], root)
  inspect((verbose_opt.getter)(0), content="false")
}

// ============================================================
// 16. P モードでの Option 割り込み
// ============================================================

///|
test "parse: option interrupt in P mode" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let (file_opt, file_node) = @combinators.positional(parser, name="file")
  let root = @combinators.opts([
    @core.Opts::Node(verbose_node),
    @core.Opts::Node(file_node),
  ])
  // file.txt で P モードに遷移後、--verbose が割り込み
  @parse.parse(["file.txt", "--verbose"], root)
  inspect((verbose_opt.getter)(0), content="true")
  inspect((file_opt.getter)(0), content="Some(\"file.txt\")")
}

// ============================================================
// 17. 複数 positional
// ============================================================

///|
test "parse: multiple positionals" {
  let parser = @core.Parser::new()
  let (src_opt, src_node) = @combinators.positional(parser, name="src")
  let (dst_opt, dst_node) = @combinators.positional(parser, name="dst")
  let root = @combinators.opts([
    @core.Opts::Node(src_node),
    @core.Opts::Node(dst_node),
  ])
  @parse.parse(["a.txt", "b.txt"], root)
  inspect((src_opt.getter)(0), content="Some(\"a.txt\")")
  inspect((dst_opt.getter)(0), content="Some(\"b.txt\")")
}

// ============================================================
// 18. 余剰引数: positional 1つに2つの引数
// ============================================================

///|
test "parse: unexpected argument" {
  let parser = @core.Parser::new()
  let (_pos_opt, pos_node) = @combinators.positional(parser, name="file")
  let root = @combinators.opts([@core.Opts::Node(pos_node)])
  let result : Result[Unit, @core.ParseError] = Ok(
    @parse.parse(["a.txt", "b.txt"], root),
  ) catch {
    e => Err(e)
  }
  inspect(result, content="Err(UnexpectedArgument(\"b.txt\"))")
}

// ============================================================
// 19. 空引数 + positional なし
// ============================================================

///|
test "parse: empty args with options only" {
  let parser = @core.Parser::new()
  let (port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let root = @combinators.opts([@core.Opts::Node(port_node)])
  @parse.parse([], root)
  inspect((port_opt.getter)(0), content="None")
}

// ============================================================
// 20. オプション後の positional（OC → P 自然遷移）
// ============================================================

///|
test "parse: options then positionals" {
  let parser = @core.Parser::new()
  let (port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let (file_opt, file_node) = @combinators.positional(parser, name="file")
  let root = @combinators.opts([
    @core.Opts::Node(port_node),
    @core.Opts::Node(verbose_node),
    @core.Opts::Node(file_node),
  ])
  @parse.parse(["--port", "3000", "--verbose", "app.js"], root)
  inspect((port_opt.getter)(0), content="Some(3000)")
  inspect((verbose_opt.getter)(0), content="true")
  inspect((file_opt.getter)(0), content="Some(\"app.js\")")
}

// ============================================================
// 21. サブコマンド: ["serve", "--port", "3000"]
// ============================================================

///|
test "parse: subcommand" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(
    parser,
    name="verbose",
    global=true,
  )
  let (port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let (host_opt, host_node) = @combinators.string_opt(parser, name="host")
  let serve_children = @combinators.opts([
    @core.Opts::Node(port_node),
    @core.Opts::Node(host_node),
  ])
  let (serve_opt, serve_node) = @combinators.cmd(
    parser,
    name="serve",
    children=serve_children,
  )
  let root = @combinators.opts([
    @core.Opts::Node(verbose_node),
    @core.Opts::Node(serve_node),
  ])
  @parse.parse(["serve", "--port", "3000", "--verbose"], root)
  inspect((serve_opt.getter)(0), content="true")
  inspect((port_opt.getter)(0), content="Some(3000)")
  inspect((verbose_opt.getter)(0), content="true")
  inspect((host_opt.getter)(0), content="None")
}

// ============================================================
// 22. count コンビネータの E2E: ["-v", "-v", "-v"] -> 3
// ============================================================

///|
test "parse: count e2e" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.count(parser, name="verbose", shorts=[
    { char: 'v' },
  ])
  let root = @combinators.opts([@core.Opts::Node(verbose_node)])
  @parse.parse(["-v", "-v", "-v"], root)
  inspect((verbose_opt.getter)(0), content="3")
}

// ============================================================
// 23. append コンビネータの E2E: ["--tag", "a", "--tag", "b"] -> ["a", "b"]
// ============================================================

///|
test "parse: append e2e" {
  let parser = @core.Parser::new()
  let (tags_opt, tags_node) = @combinators.append(parser, name="tag")
  let root = @combinators.opts([@core.Opts::Node(tags_node)])
  @parse.parse(["--tag", "a", "--tag", "b"], root)
  inspect((tags_opt.getter)(0), content="[\"a\", \"b\"]")
}

// ============================================================
// 24. サブコマンド + グローバルオプション + positional
// ============================================================

///|
test "parse: subcommand with global and positional" {
  let parser = @core.Parser::new()
  let (debug_opt, debug_node) = @combinators.flag(
    parser,
    name="debug",
    global=true,
  )
  let (file_opt, file_node) = @combinators.positional(parser, name="file")
  let deploy_children = @combinators.opts([@core.Opts::Node(file_node)])
  let (_deploy_opt, deploy_node) = @combinators.cmd(
    parser,
    name="deploy",
    children=deploy_children,
  )
  let root = @combinators.opts([
    @core.Opts::Node(debug_node),
    @core.Opts::Node(deploy_node),
  ])
  @parse.parse(["deploy", "--debug", "app.tar.gz"], root)
  inspect((debug_opt.getter)(0), content="true")
  inspect((file_opt.getter)(0), content="Some(\"app.tar.gz\")")
}
