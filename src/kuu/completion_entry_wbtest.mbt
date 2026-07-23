// completion_entry_wbtest.mbt — DR-117 §8.2 玄関判定 3 シナリオ (1/2/3) + INDEX 縮退の
// 玄関経由確認 + `generate_completion_script` の shell 分岐 + 3 点変数 literal 置換の検証。
//
// §8.2 シナリオ 4/5 (INDEX 縮退・cword=0) は既に completion_query_wbtest.mbt (M1) が pipeline
// 単位で pin しているため、本ファイルでは玄関 → pipeline の一段を通す 1 ケースに留める
// (経路の存在確認)。

// ── §8.2 玄関判定シナリオ ────────────────────────────────────────────────────

///|
/// DR-117 §8.2 シナリオ 1: env `KUU_COMPLETE` と `argv[1]` の二箇所一致 → query モード成立
/// (Respond)。応答は行応答テキストで、単純 definition の flag が候補として現れる。
test "DR-117 §8.2 シナリオ 1: env × argv[1] 一致 → Respond (query モード成立)" {
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"verbose\",\"type\":\"flag\",\"long\":true}]}",
  )
  let argv = ["app", "abc-uuid-123", "zsh", "app"]
  let env = Map([("KUU_COMPLETE", "abc-uuid-123")])
  match completion_entry(ast, canonical_registry(), argv, env) {
    Respond(s) =>
      // words=["app"] + cword 省略 (INDEX 無し) → 行末補完扱い、--verbose が並ぶ
      assert_true(
        s.contains("--verbose"),
        msg="query mode response must contain --verbose",
      )
    NotCompletion =>
      fail("expected Respond, got NotCompletion (env × argv[1] 一致経路)")
  }
}

///|
/// DR-117 §8.2 シナリオ 2: env は付いているが argv[1] が UUID と不一致 → NotCompletion
/// (env 未設定時と観測等価 — DR-117 §3.2 一様性)。stdout/exit の観測面はここでは
/// 「返却値が NotCompletion であること」で担保する (判定関数が stdout/stderr/exit のどれにも
/// 触れない構造的保証があるため、観測等価は自動)。
test "DR-117 §8.2 シナリオ 2: env のみ (argv[1] 不一致) → NotCompletion" {
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"verbose\",\"type\":\"flag\",\"long\":true}]}",
  )
  let argv = ["app", "different-uuid", "zsh", "app"]
  let env = Map([("KUU_COMPLETE", "abc-uuid-123")])
  let result = completion_entry(ast, canonical_registry(), argv, env)
  assert_eq(result, NotCompletion)
}

///|
/// argv[1] が UUID 様の値だが env `KUU_COMPLETE` が無い場合も NotCompletion (§3.2)。
test "DR-117 §8.2 シナリオ 3: argv[1] のみ (env 未設定) → NotCompletion" {
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"verbose\",\"type\":\"flag\",\"long\":true}]}",
  )
  let argv = ["app", "abc-uuid-123", "zsh", "app"]
  let env : Map[String, String] = Map([])
  let result = completion_entry(ast, canonical_registry(), argv, env)
  assert_eq(result, NotCompletion)
}

///|
/// 追加防御: argv 長 < 2 (glue が argv[1] を積み忘れる異常経路) は §3.2 に従い NotCompletion。
test "argv 長が 2 未満なら NotCompletion (異常 glue に対する構造的縮退)" {
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"verbose\",\"type\":\"flag\",\"long\":true}]}",
  )
  let env = Map([("KUU_COMPLETE", "abc-uuid-123")])
  assert_eq(
    completion_entry(ast, canonical_registry(), ["app"], env),
    NotCompletion,
  )
  assert_eq(completion_entry(ast, canonical_registry(), [], env), NotCompletion)
}

// ── INDEX 縮退の玄関経由確認 ──────────────────────────────────────────────

///|
/// KUU_COMPLETE_INDEX が数値外 (`"abc"`) の時、玄関は None として通し、`completion_query` が
/// 行末補完に縮退する (DR-117 §3.3 経路の玄関経由での確認)。§3.3 の pipeline 単位検証は
/// completion_query_wbtest.mbt が既に持つため、ここは経路存在の 1 ケースに留める。
test "KUU_COMPLETE_INDEX 数値外 → 玄関で None、pipeline が行末補完に縮退" {
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"verbose\",\"type\":\"flag\",\"long\":true}]}",
  )
  let argv = ["app", "u", "zsh", "app"]
  let env = Map([("KUU_COMPLETE", "u"), ("KUU_COMPLETE_INDEX", "not-a-number")])
  match completion_entry(ast, canonical_registry(), argv, env) {
    Respond(s) =>
      assert_true(
        s.contains("--verbose"),
        msg="malformed INDEX must degrade to end-of-line completion",
      )
    NotCompletion => fail("expected Respond even with malformed INDEX")
  }
}

///|
/// KUU_COMPLETE_INDEX が空文字の時も None 縮退 (parse_nonneg_int の empty 分岐カバレッジ)。
test "KUU_COMPLETE_INDEX 空文字 → 玄関で None、行末補完に縮退" {
  let ast = ast_or_fail(
    "{\"options\":[{\"name\":\"verbose\",\"type\":\"flag\",\"long\":true}]}",
  )
  let argv = ["app", "u", "zsh", "app"]
  let env = Map([("KUU_COMPLETE", "u"), ("KUU_COMPLETE_INDEX", "")])
  match completion_entry(ast, canonical_registry(), argv, env) {
    Respond(s) =>
      assert_true(s.contains("--verbose"), msg="empty INDEX must degrade")
    NotCompletion => fail("expected Respond")
  }
}

///|
/// KUU_COMPLETE_INDEX が正整数 `"1"` (argv[3..] = ["app", "--v"] のカーソル位置 1 = "--v") →
/// prefix "--v" で絞られ、`--verbose` が生き残る。玄関 → pipeline の cword 経路の存在確認。
test "KUU_COMPLETE_INDEX 正整数 → cword 経由の prefix 絞り経路が生きる" {
  let ast = ast_or_fail(
    "{\"options\":[" +
    "{\"name\":\"verbose\",\"type\":\"flag\",\"long\":true}," +
    "{\"name\":\"quiet\",\"type\":\"flag\",\"long\":true}" +
    "]}",
  )
  // argv[3..] = ["app", "--v"], cword=1 → cursor_word = "--v"
  let argv = ["app", "u", "zsh", "app", "--v"]
  let env = Map([("KUU_COMPLETE", "u"), ("KUU_COMPLETE_INDEX", "1")])
  match completion_entry(ast, canonical_registry(), argv, env) {
    Respond(s) => {
      assert_true(s.contains("--verbose"), msg="--verbose must survive prefix")
      assert_false(
        s.contains("--quiet"),
        msg="--quiet must be filtered out by prefix '--v'",
      )
    }
    NotCompletion => fail("expected Respond")
  }
}

// ── generate_completion_script の shell 分岐 + 3 点変数 literal 置換 ─────────

///|
/// zsh / bash / fish の 3 shell で成功し、3 点変数が literal 置換される。置換後の文字列に
/// `{{...}}` が残らないことと、渡した具体値が結果に含まれることを対で確認する
/// (見落とし片面の防止 = self-written-rule-blind-spots)。
test "generate_completion_script: 3 shell で成功 + {{BINARY}}/{{PROGRAM_NAME}}/{{UUID}} が literal 置換される" {
  for shell in ["zsh", "bash", "fish"] {
    let r = generate_completion_script(
      shell, "myapp", "/usr/local/bin/myapp", "UUID-XYZ",
    )
    match r {
      Ok(s) => {
        // 置換後は変数記法が残らない
        assert_false(
          s.contains("{{BINARY}}"),
          msg=shell + ": {{BINARY}} must be replaced",
        )
        assert_false(
          s.contains("{{PROGRAM_NAME}}"),
          msg=shell + ": {{PROGRAM_NAME}} must be replaced",
        )
        assert_false(
          s.contains("{{UUID}}"),
          msg=shell + ": {{UUID}} must be replaced",
        )
        // 供給値が結果に現れる
        assert_true(
          s.contains("/usr/local/bin/myapp"),
          msg=shell + ": binary value must appear",
        )
        assert_true(
          s.contains("myapp"),
          msg=shell + ": program_name must appear",
        )
        assert_true(s.contains("UUID-XYZ"), msg=shell + ": UUID must appear")
      }
      Err(_) => fail("generate_completion_script failed for " + shell)
    }
  }
}

///|
/// 未対応 shell → `UnsupportedShell(shell)`。空文字列も未対応扱い。
test "generate_completion_script: 未対応 shell → UnsupportedShell" {
  let r1 = generate_completion_script("powershell", "myapp", "myapp", "u")
  assert_eq(r1, Err(UnsupportedShell("powershell")))
  let r2 = generate_completion_script("", "myapp", "myapp", "u")
  assert_eq(r2, Err(UnsupportedShell("")))
  let r3 = generate_completion_script("ZSH", "myapp", "myapp", "u")
  // 大文字は shell 名として受理しない (canonical 小文字のみ)
  assert_eq(r3, Err(UnsupportedShell("ZSH")))
}

///|
/// 同じ変数が複数回出現する場合も全て置換される (`replace_all` のカバレッジ = 片面漏れ防止)。
/// spec テンプレでは `{{PROGRAM_NAME}}` が zsh の `#compdef` / 関数名 / `compdef` 引数の
/// 3 箇所で使われる。
test "generate_completion_script: 同一変数の複数出現もすべて置換される" {
  let r = generate_completion_script("zsh", "toolname", "/bin/toolname", "u1")
  match r {
    Ok(s) => {
      // 少なくとも 2 箇所 (#compdef + 関数名 _toolname) は "toolname" を含む
      let mut count = 0
      let mut i = 0
      let arr = s.to_array()
      let target = "toolname".to_array()
      while i + target.length() <= arr.length() {
        let mut matched = true
        for j = 0; j < target.length(); j = j + 1 {
          if arr[i + j] != target[j] {
            matched = false
            break
          }
        }
        if matched {
          count = count + 1
          i = i + target.length()
        } else {
          i = i + 1
        }
      }
      assert_true(
        count >= 2,
        msg="program_name 'toolname' must appear at least 2 times (got " +
          count.to_string() +
          ")",
      )
    }
    Err(_) => fail("generate_completion_script must succeed for zsh")
  }
}
