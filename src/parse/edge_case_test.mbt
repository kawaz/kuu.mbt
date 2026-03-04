///|
test "R-034: --disable-cache で EnableDisable 反転" {
  let p = @core.Parser::new()
  let cache = p.flag(name="cache", inversion=Some(@core.FlagInversion::EnableDisable))
  let o = @core.opts([cache.to_opts()])
  @parse.parse(p, ["--cache", "--disable-cache"], o)
  assert_eq!((cache.getter)(0), false)
}

///|
test "R-035: --enable-cache で EnableDisable 正方向" {
  let p = @core.Parser::new()
  let cache = p.flag(name="cache", inversion=Some(@core.FlagInversion::EnableDisable))
  let o = @core.opts([cache.to_opts()])
  @parse.parse(p, ["--enable-cache"], o)
  assert_eq!((cache.getter)(0), true)
}

///|
test "R-052a: --verbose=true → true" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose=true"], o)
  assert_eq!((verbose.getter)(0), true)
}

///|
test "R-052b: --verbose=false → false" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose=false"], o)
  assert_eq!((verbose.getter)(0), false)
}

///|
test "R-052c: --verbose=1 → true" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose=1"], o)
  assert_eq!((verbose.getter)(0), true)
}

///|
test "R-052d: --verbose=0 → false" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose=0"], o)
  assert_eq!((verbose.getter)(0), false)
}

///|
test "R-052e: --verbose=yes → true" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose=yes"], o)
  assert_eq!((verbose.getter)(0), true)
}

///|
test "R-052f: --verbose=no → false" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose=no"], o)
  assert_eq!((verbose.getter)(0), false)
}

///|
test "R-077: count 初期値を setter で設定 → 加算される" {
  let p = @core.Parser::new()
  let verbose = p.count(name="verbose")
  // Design rationale: setter → to_opts() の順で呼ぶと、store の値が保持される。
  // to_opts() は ErasedNode を生成するが reset_to_initial は呼ばない（parse() 内でも呼ばれない）。
  // これは内部実装への依存テストであり、setter で事前設定した値が current として reducer に渡ることを検証する。
  // count reducer は current + 1 で加算するため、5 + 1 + 1 = 7
  (verbose.setter)(0, 5)
  let o = @core.opts([verbose.to_opts()])
  @parse.parse(p, ["--verbose", "--verbose"], o)
  assert_eq!((verbose.getter)(0), 7)
}

///|
test "R-080: optional_value --color next で次トークン非消費" {
  let p = @core.Parser::new()
  let color = p.optional_value(name="color", default_value="auto")
  let file = p.positional(name="file")
  let o = @core.opts([color.to_opts(), file.to_opts()])
  @parse.parse(p, ["--color", "always"], o)
  // --color は値なし → default_value("auto") が使われる
  // "always" は positional として file に入る
  assert_eq!((color.getter)(0), Some("auto"))
  assert_eq!((file.getter)(0), Some("always"))
}
