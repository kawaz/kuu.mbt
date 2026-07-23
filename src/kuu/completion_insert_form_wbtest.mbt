// completion_insert_form_wbtest.mbt — DR-117 §2.6 `insert_form` パラメータ + §5 merge 規則の
// 行応答単位検証 (COMPQ-Q1 裁定 2026-07-23)。conformance fixture
// (`definition-error/completion-script-insert-form-*.json`) は決定的 def-error 検査を担うが、
// merge 規則の応答面 (space 既定と eq 明示で `--port` がどう 1 行化されるか、単独候補は形が
// 変わらないか) は runtime 挙動なので DR §8.1 の「増えない」側 — ここで観測する。
//
// テスト補助 (ast_or_fail / response_lines / find_line / contains_spelling / spellings_of /
// string_contains) は完成度目当ての近隣 wbtest (completion_query_wbtest.mbt) の
// 定義を再利用する — 同一 package 内で可視。

// ── §2.6 wire 受理面 ─────────────────────────────────────────────────────────

///|
test "DR-117 §2.6: insert_form 省略 → 既定 \"space\" 動作 (完全経路として受理)" {
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"completions\",\"type\":\"completion_script\",\"long\":true}]}",
  )
  // insert_form 未指定 → 既定 "space"。--completions 単独出現 (space 形単独=nospace なし) を確認。
  let response = completion_query(ast, canonical_registry(), ["app"])
  match find_line(response, "--completions") {
    Some(line) =>
      assert_false(
        string_contains(line, "nospace"),
        msg="default 'space' insert_form → --completions must be nospace 無し, got: " +
          line,
      )
    None => fail("--completions must appear under default space insert_form")
  }
}

///|
test "DR-117 §2.6: insert_form=\"space\" 明示 → 既定と同挙動 (受理)" {
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"completions\",\"type\":\"completion_script\",\"long\":true,\"insert_form\":\"space\"}]}",
  )
  let response = completion_query(ast, canonical_registry(), ["app"])
  match find_line(response, "--completions") {
    Some(line) =>
      assert_false(
        string_contains(line, "nospace"),
        msg="explicit 'space' insert_form 動作は既定と同じ (nospace 無し), got: " +
          line,
      )
    None => fail("--completions must appear")
  }
}

///|
test "DR-117 §2.6: insert_form=\"eq\" 明示 → eq 形へ統合 (nospace 付き)" {
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"completions\",\"type\":\"completion_script\",\"long\":true,\"insert_form\":\"eq\"}]}",
  )
  let response = completion_query(ast, canonical_registry(), ["app"])
  // insert_form=eq → cont 側を残し spelling に "=" を付ける + nospace 立て
  match find_line(response, "--completions=") {
    Some(line) =>
      assert_true(
        string_contains(line, "nospace"),
        msg="eq insert_form → --completions= must carry nospace, got: " + line,
      )
    None =>
      fail(
        "--completions= (eq 形統合後の綴り) must appear under insert_form=eq, response: " +
        response,
      )
  }
  // 元綴り "--completions" は eq 側統合により消える
  assert_false(
    contains_spelling(response, "--completions"),
    msg="original spelling --completions must be replaced by --completions=",
  )
}

// ── §5 merge 規則 (完全な word_end/cont ペア) ─────────────────────────────────

///|
test "DR-117 §5: 既定 (space) は同一 spelling の word_end/cont ペアを 1 行に統合" {
  // number 型 long option は long_eq_sep:"allow" 既定で word_end と cont が同時に出る
  // (`fixtures/complete/eq-split-cont.json` の輪郭)。insert_form は completion_script 入口が
  // 無いので既定 "space" が使われ、word_end 側 (nospace 無し) が残る。
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"port\",\"type\":\"number\",\"long\":true}]}",
  )
  let response = completion_query(ast, canonical_registry(), ["app"])
  let sps = spellings_of(response)
  // --port は 1 件だけ (2 件併存が 1 行に畳まれる)
  let mut port_count = 0
  for sp in sps {
    if sp == "--port" {
      port_count = port_count + 1
    }
  }
  assert_eq(port_count, 1)
  // --port 行は nospace 無し (space 形が残る)
  match find_line(response, "--port") {
    Some(line) =>
      assert_false(
        string_contains(line, "nospace"),
        msg="space 既定で残る --port は nospace 無しでなければならない, got: " +
          line,
      )
    None => fail("--port must be present")
  }
  // --port= (eq 形) は space 既定では出ない
  assert_false(
    contains_spelling(response, "--port="),
    msg="--port= must not appear when insert_form is space (default)",
  )
}

///|
test "DR-117 §5: insert_form=\"eq\" 明示で word_end/cont ペアを eq 形へ統合" {
  // completion_script 入口で insert_form=eq を宣言 → 全 long option の merge が eq 側 (cont) を
  // 残す。--port は eq 形 "--port=" nospace 付き で emit される (1 行)。
  let ast = ast_or_fail(
    "{" +
    "\"options\":[" +
    "{\"name\":\"port\",\"type\":\"number\",\"long\":true}," +
    "{\"name\":\"completions\",\"type\":\"completion_script\",\"long\":true,\"insert_form\":\"eq\"}" +
    "]" +
    "}",
  )
  let response = completion_query(ast, canonical_registry(), ["app"])
  // --port は eq 形にリライトされ、"--port=" 1 行のみ (元の --port 行は消える)
  match find_line(response, "--port=") {
    Some(line) =>
      assert_true(
        string_contains(line, "nospace"),
        msg="eq insert_form で残る --port= は nospace 付きでなければならない, got: " +
          line,
      )
    None =>
      fail("--port= must appear under insert_form=eq, response: " + response)
  }
  assert_false(
    contains_spelling(response, "--port"),
    msg="original --port must be replaced (eq form wins)",
  )
}

// ── §5 merge 規則 (片側のみ・単独候補は形を書き換えない) ─────────────────────

///|
test "DR-117 §5: long_eq_sep:\"require\" は cont 側のみ素材で提供 → insert_form=space でも書き換えない" {
  // long_eq_sep:"require" では space-form main entry (word_end) は素材から落ち、eq-split matcher
  // (cont) だけが残る (fixture `value-sources/long-eq-sep-require.json` の輪郭)。単独候補は
  // `insert_form` の値に関わらず素材通りの形で emit (DR §5「単独候補の形を書き換えない」)。
  let ast = ast_or_fail(
    "{" +
    "\"options\":[{\"name\":\"port\",\"type\":\"number\",\"long\":true}]," +
    "\"config\":{\"long_eq_sep\":\"require\"}" +
    "}",
  )
  let response = completion_query(ast, canonical_registry(), ["app"])
  // cont 単独 → term=Continue の翻訳 (nospace 付き)、spelling は素材の "--port" のまま
  // (=` は付けない — merge は insert_form=space の要求だが単独なので書き換え不可)
  match find_line(response, "--port") {
    Some(line) =>
      assert_true(
        string_contains(line, "nospace"),
        msg="require mode の単独 cont 候補は term:Continue → nospace 付き, got: " +
          line,
      )
    None =>
      fail(
        "--port cont must appear even in require mode, response: " + response,
      )
  }
  assert_false(
    contains_spelling(response, "--port="),
    msg="single-side candidate must not be rewritten (DR-117 §5)",
  )
}

// ── §2.6 definition-error (fixture と同型の白箱検証) ──────────────────────────

///|
test "DR-117 §2.6: 未知 insert_form 値 (\"dash\") → invalid-range" {
  let json = @json.parse(
    "{\"options\":[{\"name\":\"completions-bad-form\",\"type\":\"completion_script\",\"long\":true,\"insert_form\":\"dash\"}]}",
  )
  match parse_definition(json) {
    Err(Rejected(errors)) => {
      let kinds = def_error_kinds(errors)
      assert_eq(kinds.get("completions-bad-form"), Some(@abi.InvalidRange))
    }
    _ =>
      fail(
        "insert_form enum 逸脱 (\"dash\") は definition-error でなければならない",
      )
  }
}

///|
test "DR-117 §2.6: 複数 completion_script 入口間の insert_form 明示食い違い → invalid-range × 2" {
  // conformance fixture completion-script-insert-form-conflict.json と同型 (long option +
  // subcommand positional に space/eq の食い違い)。両入口とも invalid-range 対象。
  let json = @json.parse(
    "{" +
    "\"options\":[" +
    "{\"name\":\"completions-long\",\"type\":\"completion_script\",\"long\":true,\"insert_form\":\"space\"}" +
    "]," +
    "\"commands\":[" +
    "{\"name\":\"completion\"," +
    "\"positionals\":[" +
    "{\"name\":\"completions-sub\",\"type\":\"completion_script\",\"insert_form\":\"eq\"}" +
    "]" +
    "}" +
    "]" +
    "}",
  )
  match parse_definition(json) {
    Err(Rejected(errors)) => {
      let kinds = def_error_kinds(errors)
      assert_eq(kinds.get("completions-long"), Some(@abi.InvalidRange))
      assert_eq(kinds.get("completions-sub"), Some(@abi.InvalidRange))
    }
    _ =>
      fail(
        "複数入口間の insert_form 食い違いは両入口とも invalid-range でなければならない",
      )
  }
}

///|
test "DR-117 §2.6: 全省略 → 既定 \"space\" として受理 (両入口とも入口が省略なら食い違い無し)" {
  // 全ての completion_script 入口で insert_form 省略 → 既定 "space" が適用され、error 無く受理
  // (parse_definition が Ok を返す)。
  let json = @json.parse(
    "{" +
    "\"options\":[" +
    "{\"name\":\"completions-long\",\"type\":\"completion_script\",\"long\":true}" +
    "]," +
    "\"commands\":[" +
    "{\"name\":\"completion\"," +
    "\"positionals\":[" +
    "{\"name\":\"completions-sub\",\"type\":\"completion_script\"}" +
    "]" +
    "}" +
    "]" +
    "}",
  )
  match parse_definition(json) {
    Ok(_) => ()
    _ => fail("all-omitted insert_form must be Ok (既定 space)")
  }
}

///|
test "DR-117 §2.6: 省略と明示の混在は明示値が勝つ (Ok で受理)" {
  // 1 入口は空 (omitted)、1 入口は明示 "eq"。省略は勝敗の対象外 (DR §2.6) なので競合しない → Ok。
  let json = @json.parse(
    "{" +
    "\"options\":[" +
    "{\"name\":\"completions-long\",\"type\":\"completion_script\",\"long\":true}" +
    "]," +
    "\"commands\":[" +
    "{\"name\":\"completion\"," +
    "\"positionals\":[" +
    "{\"name\":\"completions-sub\",\"type\":\"completion_script\",\"insert_form\":\"eq\"}" +
    "]" +
    "}" +
    "]" +
    "}",
  )
  match parse_definition(json) {
    Ok(ast) =>
      // AtomicAST の definition-wide reconciled 値は "eq" になる (明示が勝つ)
      assert_eq(ast.completion_insert_form, "eq")
    _ =>
      fail(
        "省略と明示の混在は Ok (定義-wide 実効値は明示 \"eq\") でなければならない",
      )
  }
}

///|
test "DR-117 §2.6: 全省略時の definition-wide 実効値は \"space\"" {
  let json = @json.parse(
    "{\"options\":[{\"name\":\"completions\",\"type\":\"completion_script\",\"long\":true}]}",
  )
  match parse_definition(json) {
    Ok(ast) => assert_eq(ast.completion_insert_form, "space")
    _ => fail("must accept")
  }
}

///|
test "DR-117 §2.6: completion_script 入口ゼロ → 実効値 \"space\" (既定)" {
  // 形態 B の def.json 直 query 想定 — completion_script 入口を持たない definition も既定
  // "space" で動く (DR §2.6 の 3 番目の bullet)。
  let json = @json.parse(
    "{\"options\":[{\"name\":\"port\",\"type\":\"number\",\"long\":true}]}",
  )
  match parse_definition(json) {
    Ok(ast) => assert_eq(ast.completion_insert_form, "space")
    _ => fail("must accept")
  }
}

///|
test "DR-117 §2.6: 非 completion_script type への insert_form 宣言 → invalid-range" {
  // schema description が pin する「completion_script type 以外への宣言も同 kind」。
  let json = @json.parse(
    "{\"options\":[{\"name\":\"port\",\"type\":\"number\",\"long\":true,\"insert_form\":\"space\"}]}",
  )
  match parse_definition(json) {
    Err(Rejected(errors)) => {
      let kinds = def_error_kinds(errors)
      assert_eq(kinds.get("port"), Some(@abi.InvalidRange))
    }
    _ => fail("insert_form on non-completion_script type must be invalid-range")
  }
}
