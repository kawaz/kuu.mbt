// FieldRef + Binder 方式 PoC テスト

// =============================================================
// FieldRef テスト
// =============================================================

test "FieldRef: get で値を取得" {
  let config = AppConfig::default()
  let name_ref = AppConfig::name_ref()
  inspect((name_ref.get)(config), content="")
}

test "FieldRef: set で値を更新（struct update syntax）" {
  let config = AppConfig::default()
  let name_ref = AppConfig::name_ref()
  let updated = (name_ref.set)(config, "Alice")
  inspect(updated.name, content="Alice")
  // 他フィールドは不変
  inspect(updated.age, content="0")
  inspect(updated.verbose, content="false")
}

test "FieldRef: get/set ラウンドトリップ" {
  let config = { name: "Bob", age: 25, verbose: true }
  let age_ref = AppConfig::age_ref()
  let original_age = (age_ref.get)(config)
  let updated = (age_ref.set)(config, original_age + 10)
  inspect((age_ref.get)(updated), content="35")
}

// =============================================================
// FieldRef: Lens 則テスト
// =============================================================

test "FieldRef: Lens則 set-get" {
  // get(set(s, a)) == a
  let config = AppConfig::default()
  let name_ref = AppConfig::name_ref()
  let updated = (name_ref.set)(config, "Alice")
  inspect((name_ref.get)(updated), content="Alice")
}

test "FieldRef: Lens則 set-set" {
  // set(set(s, a), b) == set(s, b)
  let config = AppConfig::default()
  let age_ref = AppConfig::age_ref()
  let step1 = (age_ref.set)(config, 10)
  let step2 = (age_ref.set)(step1, 20)
  let direct = (age_ref.set)(config, 20)
  assert_eq!(step2, direct)
}

test "FieldRef: Lens則 get-set" {
  // set(s, get(s)) == s
  let config : AppConfig = { name: "Bob", age: 25, verbose: true }
  let name_ref = AppConfig::name_ref()
  let roundtrip = (name_ref.set)(config, (name_ref.get)(config))
  assert_eq!(roundtrip, config)
}

// =============================================================
// Binder テスト — 型消去の検証
// =============================================================

test "make_binder: String フィールドへのバインド" {
  let binder = make_binder(AppConfig::name_ref(), fn(raw) { Some(raw) })
  let config = AppConfig::default()
  let result = (binder.apply)(config, "Alice")
  guard result is Ok(updated) else { fail("unexpected Err") }
  inspect(updated.name, content="Alice")
}

test "make_binder: Int フィールドへのバインド" {
  let binder = make_binder(
    AppConfig::age_ref(),
    fn(raw) { try { Some(@strconv.parse_int(raw)) } catch { _ => None } },
  )
  let config = AppConfig::default()
  let result = (binder.apply)(config, "42")
  guard result is Ok(updated) else { fail("unexpected Err") }
  inspect(updated.age, content="42")
}

test "make_binder: パース失敗時は Err" {
  let binder = make_binder(
    AppConfig::age_ref(),
    fn(raw) { try { Some(@strconv.parse_int(raw)) } catch { _ => None } },
  )
  let config = AppConfig::default()
  let result = (binder.apply)(config, "not_a_number")
  guard result is Err(msg) else { fail("unexpected Ok") }
  inspect(msg, content="parse failed: not_a_number")
}

test "make_binder: Bool フィールドへのバインド" {
  let binder = make_binder(
    AppConfig::verbose_ref(),
    fn(raw) {
      match raw {
        "true" => Some(true)
        "false" => Some(false)
        _ => None
      }
    },
  )
  let config = AppConfig::default()
  let result = (binder.apply)(config, "true")
  guard result is Ok(updated) else { fail("unexpected Err") }
  inspect(updated.verbose, content="true")
}

// =============================================================
// 型消去: 異なる型の Binder を同じ配列に格納
// =============================================================

test "型消去: 異なる型の Binder を Array[Binder[AppConfig]] に格納" {
  // Note: このテストでは Bool パーサが make_app_opts() と異なり
  // "true" 以外を全て false とする簡易版を使用している（型消去の検証が目的のため）
  let binders : Array[Binder[AppConfig]] = [
    make_binder(AppConfig::name_ref(), fn(raw) { Some(raw) }),
    make_binder(
      AppConfig::age_ref(),
      fn(raw) { try { Some(@strconv.parse_int(raw)) } catch { _ => None } },
    ),
    make_binder(
      AppConfig::verbose_ref(),
      fn(raw) {
        match raw {
          "true" => Some(true)
          _ => Some(false)
        }
      },
    ),
  ]
  // 異なる型のバインダが共存できることを検証
  inspect(binders.length(), content="3")
}

// =============================================================
// parse_args テスト
// =============================================================

test "parse_args: 全オプション指定" {
  let args = ["--name", "Alice", "--age", "30", "--verbose", "true"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(
    result,
    content="Ok({name: \"Alice\", age: 30, verbose: true})",
  )
}

test "parse_args: 部分的なオプション指定" {
  let args = ["--name", "Bob"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(
    result,
    content="Ok({name: \"Bob\", age: 0, verbose: false})",
  )
}

test "parse_args: 空引数" {
  let args : Array[String] = []
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(
    result,
    content="Ok({name: \"\", age: 0, verbose: false})",
  )
}

test "parse_args: 未知のオプション" {
  let args = ["--unknown", "value"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(result, content="Err(\"unknown option: --unknown\")")
}

test "parse_args: 値なしオプション" {
  let args = ["--name"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(result, content="Err(\"missing value for --name\")")
}

test "parse_args: Int パース失敗" {
  let args = ["--age", "abc"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(result, content="Err(\"parse failed: abc\")")
}

test "parse_args: オプション順序は自由" {
  let args = ["--verbose", "true", "--age", "25", "--name", "Carol"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(
    result,
    content="Ok({name: \"Carol\", age: 25, verbose: true})",
  )
}

test "parse_args: 同一オプション重複は後勝ち" {
  let args = ["--name", "Alice", "--name", "Bob"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(
    result,
    content="Ok({name: \"Bob\", age: 0, verbose: false})",
  )
}

// =============================================================
// IntoOpt trait テスト
// =============================================================

test "IntoOpt: parse_with で AppConfig をパース" {
  let args = ["--name", "Dave", "--age", "40"]
  let result = parse_with(args, AppConfig::default())
  inspect(
    result,
    content="Ok({name: \"Dave\", age: 40, verbose: false})",
  )
}

test "IntoOpt: opts() がオプション定義を返す" {
  let config = AppConfig::default()
  let opts = IntoOpt::opts(config)
  inspect(opts.length(), content="3")
  inspect(opts[0].opt_name, content="--name")
  inspect(opts[1].opt_name, content="--age")
  inspect(opts[2].opt_name, content="--verbose")
}

// =============================================================
// FieldRef 連続適用テスト（immutable update chain）
// =============================================================

test "FieldRef: 連続 set でイミュータブル更新チェーン" {
  let config = AppConfig::default()
  let step1 = (AppConfig::name_ref().set)(config, "Eve")
  let step2 = (AppConfig::age_ref().set)(step1, 28)
  let step3 = (AppConfig::verbose_ref().set)(step2, true)
  inspect(
    step3,
    content="{name: \"Eve\", age: 28, verbose: true}",
  )
  // 元の config は不変
  inspect(
    config,
    content="{name: \"\", age: 0, verbose: false}",
  )
}
