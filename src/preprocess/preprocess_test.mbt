///|
test "@file で指定されたファイルの行が展開される" {
  let p = @core.Parser::new()
  let port = p.int(name="port")
  let host = p.string(name="host")
  let o = @core.opts([port.to_opts(), host.to_opts()])
  @preprocess.expand_at_files(p, read_file=fn(path) {
    if path == "args.txt" {
      Some("--port\n8080\n--host\nlocalhost\n")
    } else {
      None
    }
  })
  @parse.parse(p, ["@args.txt"], o)
  assert_eq((port.getter)(0), Some(8080))
  assert_eq((host.getter)(0), Some("localhost"))
}

///|
test "@file 展開で空行はスキップされる" {
  let p = @core.Parser::new()
  let port = p.int(name="port")
  let o = @core.opts([port.to_opts()])
  @preprocess.expand_at_files(p, read_file=fn(path) {
    if path == "args.txt" {
      Some("\n\n--port\n\n8080\n\n")
    } else {
      None
    }
  })
  @parse.parse(p, ["@args.txt"], o)
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "@@ は @ にエスケープされる" {
  let p = @core.Parser::new()
  let file = p.positional(name="file")
  let o = @core.opts([file.to_opts()])
  @preprocess.expand_at_files(p, read_file=fn(_path) { None })
  @parse.parse(p, ["@@literal"], o)
  assert_eq((file.getter)(0), Some("@literal"))
}

///|
test "ファイルが見つからない場合は引数がそのまま残る" {
  let p = @core.Parser::new()
  let file = p.positional(name="file")
  let o = @core.opts([file.to_opts()])
  @preprocess.expand_at_files(p, read_file=fn(_path) { None })
  @parse.parse(p, ["@missing.txt"], o)
  assert_eq((file.getter)(0), Some("@missing.txt"))
}

///|
test "通常の引数はそのまま" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let port = p.int(name="port")
  let o = @core.opts([verbose.to_opts(), port.to_opts()])
  @preprocess.expand_at_files(p, read_file=fn(_path) { None })
  @parse.parse(p, ["--verbose", "--port", "8080"], o)
  assert_eq((verbose.getter)(0), true)
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "複数の @file を混在させたケース" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let port = p.int(name="port")
  let host = p.string(name="host")
  let o = @core.opts([verbose.to_opts(), port.to_opts(), host.to_opts()])
  @preprocess.expand_at_files(p, read_file=fn(path) {
    if path == "net.txt" {
      Some("--port\n8080\n--host\nlocalhost")
    } else if path == "flags.txt" {
      Some("--verbose")
    } else {
      None
    }
  })
  @parse.parse(p, ["@flags.txt", "@net.txt"], o)
  assert_eq((verbose.getter)(0), true)
  assert_eq((port.getter)(0), Some(8080))
  assert_eq((host.getter)(0), Some("localhost"))
}

///|
test "@file で1行に複数の引数を記述できる" {
  let p = @core.Parser::new()
  let port = p.int(name="port")
  let host = p.string(name="host")
  let o = @core.opts([port.to_opts(), host.to_opts()])
  @preprocess.expand_at_files(p, read_file=fn(path) {
    if path == "args.txt" {
      Some("--port 8080\n--host localhost\n")
    } else {
      None
    }
  })
  @parse.parse(p, ["@args.txt"], o)
  assert_eq((port.getter)(0), Some(8080))
  assert_eq((host.getter)(0), Some("localhost"))
}

///|
test "@file でクォート内の空白は保持される" {
  let p = @core.Parser::new()
  let message = p.string(name="message")
  let name = p.string(name="name")
  let o = @core.opts([message.to_opts(), name.to_opts()])
  @preprocess.expand_at_files(p, read_file=fn(path) {
    if path == "args.txt" {
      Some("--message \"hello world\"\n--name 'foo bar'\n")
    } else {
      None
    }
  })
  @parse.parse(p, ["@args.txt"], o)
  assert_eq((message.getter)(0), Some("hello world"))
  assert_eq((name.getter)(0), Some("foo bar"))
}

///|
test "@file でバックスラッシュエスケープが動作する" {
  let p = @core.Parser::new()
  let path_opt = p.string(name="path")
  let o = @core.opts([path_opt.to_opts()])
  @preprocess.expand_at_files(p, read_file=fn(path) {
    if path == "args.txt" {
      Some("--path /tmp/my\\ file.txt\n")
    } else {
      None
    }
  })
  @parse.parse(p, ["@args.txt"], o)
  assert_eq((path_opt.getter)(0), Some("/tmp/my file.txt"))
}

///|
test "@file で空文字引数が保持される" {
  let p = @core.Parser::new()
  expand_at_files(p, read_file=fn(path) {
    if path == "args.txt" {
      Some("--name \"\"\n--value ''\n")
    } else {
      None
    }
  })
  let result = p.preprocessors[0](["@args.txt"])
  assert_eq(result, ["--name", "", "--value", ""])
}

///|
test "@file で末尾バックスラッシュがリテラルとして扱われる" {
  let p = @core.Parser::new()
  expand_at_files(p, read_file=fn(path) {
    if path == "args.txt" {
      Some("--path foo\\")
    } else {
      None
    }
  })
  let result = p.preprocessors[0](["@args.txt"])
  assert_eq(result, ["--path", "foo\\"])
}

///|
test "@file で未閉じクォートはトークン化される" {
  let p = @core.Parser::new()
  expand_at_files(p, read_file=fn(path) {
    if path == "args.txt" {
      Some("--flag \"unclosed")
    } else {
      None
    }
  })
  let result = p.preprocessors[0](["@args.txt"])
  assert_eq(result, ["--flag", "unclosed"])
}

///|
test "@file 展開後も他のプリプロセッサが動作する（連鎖テスト）" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose")
  let o = @core.opts([verbose.to_opts()])
  // 1つ目: @file 展開 → --loud を出力
  @preprocess.expand_at_files(p, read_file=fn(path) {
    if path == "args.txt" {
      Some("--loud")
    } else {
      None
    }
  })
  // 2つ目: --loud を --verbose に書き換え
  p.add_preprocessor(fn(args) {
    let result : Array[String] = []
    for a in args {
      if a == "--loud" {
        result.push("--verbose")
      } else {
        result.push(a)
      }
    }
    result
  })
  @parse.parse(p, ["@args.txt"], o)
  assert_eq((verbose.getter)(0), true)
}
