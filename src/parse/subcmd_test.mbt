///|
test "R-202: 多段サブコマンド root → sub1 → sub2" {
  let p = @core.Parser::new()
  let port = p.int(name="port")
  let sub2 = p.cmd(name="sub2", children=@core.opts([port.to_opts()]))
  let sub1 = p.cmd(name="sub1", children=@core.opts([sub2.to_opts()]))
  let o = @core.opts([sub1.to_opts()])
  @parse.parse(p, ["sub1", "sub2", "--port", "8080"], o)
  assert_eq!((sub1.getter)(0), true)
  assert_eq!((sub2.getter)(0), true)
  assert_eq!((port.getter)(0), Some(8080))
}

///|
test "R-204: global値オプション先行 --port 8080 cmd1" {
  let p = @core.Parser::new()
  let port = p.int(name="port", global=true)
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([]))
  let o = @core.opts([port.to_opts(), cmd1.to_opts()])
  @parse.parse(p, ["--port", "8080", "cmd1"], o)
  assert_eq!((port.getter)(0), Some(8080))
  assert_eq!((cmd1.getter)(0), true)
}

///|
test "R-205: global eq形式先行 --port=8080 cmd1" {
  let p = @core.Parser::new()
  let port = p.int(name="port", global=true)
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([]))
  let o = @core.opts([port.to_opts(), cmd1.to_opts()])
  @parse.parse(p, ["--port=8080", "cmd1"], o)
  assert_eq!((port.getter)(0), Some(8080))
  assert_eq!((cmd1.getter)(0), true)
}

///|
test "R-207: -- でサブコマンド探索停止" {
  let p = @core.Parser::new()
  let file = p.positional(name="file")
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([]))
  let o = @core.opts([file.to_opts(), cmd1.to_opts()])
  @parse.parse(p, ["--", "cmd1"], o)
  // -- 後の cmd1 はサブコマンドではなく positional として扱われる
  assert_eq!((cmd1.getter)(0), false)
  assert_eq!((file.getter)(0), Some("cmd1"))
}

///|
test "R-211: --no-verbose cmd1 でサブコマンド解決" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", global=true, inversion=Some(@core.FlagInversion::No))
  let cmd1 = p.cmd(name="cmd1", children=@core.opts([]))
  let o = @core.opts([verbose.to_opts(), cmd1.to_opts()])
  @parse.parse(p, ["--no-verbose", "cmd1"], o)
  assert_eq!((verbose.getter)(0), false)
  assert_eq!((cmd1.getter)(0), true)
}

///|
test "R-215: 多段ネスト global 継承 --verbose sub1 sub2 → verbose=true" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let sub2 = p.cmd(name="sub2", children=@core.opts([]))
  let sub1 = p.cmd(name="sub1", children=@core.opts([sub2.to_opts()]))
  let o = @core.opts([verbose.to_opts(), sub1.to_opts()])
  @parse.parse(p, ["sub1", "sub2", "--verbose"], o)
  assert_eq!((verbose.getter)(0), true)
  assert_eq!((sub1.getter)(0), true)
  assert_eq!((sub2.getter)(0), true)
}
