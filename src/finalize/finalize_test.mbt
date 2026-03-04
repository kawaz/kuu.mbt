///|
test "env: 個別環境変数名で値が適用される" {
  let p = @core.Parser::new()
  let port = p.int(name="port", env=Some("PORT"))
  let o = @core.opts([port.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "PORT" {
      Some("8080")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o)
  @parse.parse(p, [], o)
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "env: コマンドラインで設定済みなら環境変数は上書きしない" {
  let p = @core.Parser::new()
  let port = p.int(name="port", env=Some("PORT"))
  let o = @core.opts([port.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "PORT" {
      Some("9999")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o)
  @parse.parse(p, ["--port", "3000"], o)
  // コマンドラインの値が優先される
  assert_eq((port.getter)(0), Some(3000))
}

///|
test "auto_env: true で name のアッパーケースから自動取得" {
  let p = @core.Parser::new()
  let host = p.string(name="host", auto_env=Some(true))
  let o = @core.opts([host.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "HOST" {
      Some("localhost")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o)
  @parse.parse(p, [], o)
  assert_eq((host.getter)(0), Some("localhost"))
}

///|
test "env_prefix: プレフィックス付きで自動取得" {
  let p = @core.Parser::new()
  let port = p.int(name="port")
  let o = @core.opts([port.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "APP_PORT" {
      Some("4000")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o, env_prefix="APP")
  @parse.parse(p, [], o)
  assert_eq((port.getter)(0), Some(4000))
}

///|
test "環境変数が見つからない場合は何もしない" {
  let p = @core.Parser::new()
  let port = p.int(name="port", env=Some("PORT"))
  let o = @core.opts([port.to_opts()])
  p.set_env_lookup(fn(_name) { None })
  @finalize.apply_env(p, o)
  @parse.parse(p, [], o)
  // 値は初期値のまま
  assert_eq((port.getter)(0), None)
}

///|
test "env_lookup 未設定時は何もしない" {
  let p = @core.Parser::new()
  let port = p.int(name="port", env=Some("PORT"))
  let o = @core.opts([port.to_opts()])
  // set_env_lookup を呼ばない
  @finalize.apply_env(p, o)
  @parse.parse(p, [], o)
  // 値は初期値のまま
  assert_eq((port.getter)(0), None)
}

///|
test "env: フラグへの環境変数適用 (true)" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", env=Some("VERBOSE"))
  let fo = verbose.to_opts()
  let o = @core.opts([fo])
  p.set_env_lookup(fn(name) {
    if name == "VERBOSE" {
      Some("true")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o)
  @parse.parse(p, [], o)
  assert_eq((verbose.getter)(0), true)
}

///|
test "env: フラグへの環境変数適用 (false/0/no)" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", env=Some("VERBOSE"))
  let fo = verbose.to_opts()
  let o = @core.opts([fo])
  p.set_env_lookup(fn(name) {
    if name == "VERBOSE" {
      Some("0")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o)
  @parse.parse(p, [], o)
  assert_eq((verbose.getter)(0), false)
}

///|
test "auto_env + env_prefix: プレフィックス付きで自動取得" {
  let p = @core.Parser::new()
  let port = p.int(name="port", auto_env=Some(true))
  let fo = port.to_opts()
  let o = @core.opts([fo])
  p.set_env_lookup(fn(name) {
    if name == "APP_PORT" {
      Some("3000")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o, env_prefix="APP")
  @parse.parse(p, [], o)
  assert_eq((port.getter)(0), Some(3000))
}

///|
test "apply_env + check_required: 環境変数で required が満たされる" {
  let p = @core.Parser::new()
  let port = p.int(name="port", env=Some("PORT"), required=true)
  let o = @core.opts([port.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "PORT" {
      Some("8080")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o)
  @validate.check_required(p, o)
  @parse.parse(p, [], o)
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "auto_env=false + env_prefix: 明示的に無効化された場合は取得しない" {
  let p = @core.Parser::new()
  let port = p.int(name="port", auto_env=Some(false))
  let o = @core.opts([port.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "APP_PORT" {
      Some("5000")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o, env_prefix="APP")
  @parse.parse(p, [], o)
  // auto_env=false なので環境変数は適用されない
  assert_eq((port.getter)(0), None)
}

///|
test "env: フラグの不正な環境変数値でエラーが伝播する" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", env=Some("VERBOSE"))
  let o = @core.opts([verbose.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "VERBOSE" {
      Some("enabled")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o)
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(p, [], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::InvalidValue)
  }
  match result {
    Err(@core.ErrorKind::InvalidValue) => ()
    _ => fail("expected InvalidValue error for invalid boolean env value")
  }
}

///|
test "env: フラグに false を環境変数で設定すると is_set が true になる" {
  let p = @core.Parser::new()
  let verbose = p.flag(name="verbose", env=Some("VERBOSE"))
  let fo = verbose.to_opts()
  let nodes = @core.opts_to_erased_nodes(fo)
  let o = @core.opts([fo])
  p.set_env_lookup(fn(name) {
    if name == "VERBOSE" {
      Some("false")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o)
  @parse.parse(p, [], o)
  // 値は false だが、環境変数で明示的に設定されたので is_set は true
  assert_eq((verbose.getter)(0), false)
  assert_eq((nodes[0].is_set)(), true)
}

///|
test "env + env_prefix: env 指定がある場合は env_prefix を無視する" {
  let p = @core.Parser::new()
  let port = p.int(name="port", env=Some("PORT"))
  let o = @core.opts([port.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "PORT" {
      Some("8080")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o, env_prefix="APP")
  @parse.parse(p, [], o)
  // env="PORT" が完全オーバーライドなので APP_PORT ではなく PORT で取得
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "check_required → apply_env の順で呼んでも正常動作する" {
  let p = @core.Parser::new()
  let port = p.int(name="port", env=Some("PORT"), required=true)
  let o = @core.opts([port.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "PORT" {
      Some("8080")
    } else {
      None
    }
  })
  // 逆順で登録しても、env_finalizers → finalizers の順序保証で正常動作
  @validate.check_required(p, o)
  @finalize.apply_env(p, o)
  @parse.parse(p, [], o)
  assert_eq((port.getter)(0), Some(8080))
}

///|
test "env_prefix: Positional には環境変数が適用されない" {
  let p = @core.Parser::new()
  let file = p.positional(name="file")
  let o = @core.opts([file.to_opts()])
  p.set_env_lookup(fn(name) {
    if name == "APP_FILE" {
      Some("test.txt")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o, env_prefix="APP")
  @parse.parse(p, [], o)
  // Positional には env が適用されないので値は None のまま
  assert_eq((file.getter)(0), None)
}

///|
test "env: 不正な環境変数値でエラーが伝播する" {
  let p = @core.Parser::new()
  let port = p.int(name="port", env=Some("PORT"))
  let fo = port.to_opts()
  let o = @core.opts([fo])
  p.set_env_lookup(fn(name) {
    if name == "PORT" {
      Some("not_a_number")
    } else {
      None
    }
  })
  @finalize.apply_env(p, o)
  let result : Result[Unit, @core.ErrorKind] = Ok(
    @parse.parse(p, [], o),
  ) catch {
    @core.ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(@core.ErrorKind::InvalidValue)
  }
  match result {
    Err(@core.ErrorKind::InvalidValue) => ()
    _ => fail("expected InvalidValue error for non-numeric env value")
  }
}
