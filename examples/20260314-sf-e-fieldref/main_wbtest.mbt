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
// Binder テスト — 型消去の検証
// =============================================================

test "make_binder: String フィールドへのバインド" {
  let binder = make_binder(AppConfig::name_ref(), fn(s) { Some(s) })
  let config = AppConfig::default()
  let (updated, result) = (binder.apply)(config, "Alice")
  inspect(result, content="Accept")
  inspect(updated.name, content="Alice")
}

test "make_binder: Int フィールドへのバインド" {
  let binder = make_binder(
    AppConfig::age_ref(),
    fn(s) { try { Some(@strconv.parse_int(s)) } catch { _ => None } },
  )
  let config = AppConfig::default()
  let (updated, result) = (binder.apply)(config, "42")
  inspect(result, content="Accept")
  inspect(updated.age, content="42")
}

test "make_binder: パース失敗時は Reject" {
  let binder = make_binder(
    AppConfig::age_ref(),
    fn(s) { try { Some(@strconv.parse_int(s)) } catch { _ => None } },
  )
  let config = AppConfig::default()
  let (updated, result) = (binder.apply)(config, "not_a_number")
  inspect(result, content="Reject(\"parse failed: not_a_number\")")
  // state は変更されない
  inspect(updated.age, content="0")
}

test "make_binder: Bool フィールドへのバインド" {
  let binder = make_binder(
    AppConfig::verbose_ref(),
    fn(s) {
      match s {
        "true" => Some(true)
        "false" => Some(false)
        _ => None
      }
    },
  )
  let config = AppConfig::default()
  let (updated, result) = (binder.apply)(config, "true")
  inspect(result, content="Accept")
  inspect(updated.verbose, content="true")
}

// =============================================================
// 型消去: 異なる型の Binder を同じ配列に格納
// =============================================================

test "型消去: 異なる型の Binder を Array[Binder[AppConfig]] に格納" {
  let binders : Array[Binder[AppConfig]] = [
    make_binder(AppConfig::name_ref(), fn(s) { Some(s) }),
    make_binder(
      AppConfig::age_ref(),
      fn(s) { try { Some(@strconv.parse_int(s)) } catch { _ => None } },
    ),
    make_binder(
      AppConfig::verbose_ref(),
      fn(s) {
        match s {
          "true" => Some(true)
          _ => Some(false)
        }
      },
    ),
  ]
  inspect(binders.length(), content="3")
  // 異なる型のバインダが共存できる
  inspect(binders[0].name, content="name")
  inspect(binders[1].name, content="age")
  inspect(binders[2].name, content="verbose")
}

// =============================================================
// parse_args テスト
// =============================================================

test "parse_args: 全オプション指定" {
  let args = ["--name", "Alice", "--age", "30", "--verbose", "true"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(
    result,
    content="Some({name: \"Alice\", age: 30, verbose: true})",
  )
}

test "parse_args: 部分的なオプション指定" {
  let args = ["--name", "Bob"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(
    result,
    content="Some({name: \"Bob\", age: 0, verbose: false})",
  )
}

test "parse_args: 空引数" {
  let args : Array[String] = []
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(
    result,
    content="Some({name: \"\", age: 0, verbose: false})",
  )
}

test "parse_args: 未知のオプション" {
  let args = ["--unknown", "value"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(result, content="None")
}

test "parse_args: 値なしオプション" {
  let args = ["--name"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(result, content="None")
}

test "parse_args: Int パース失敗" {
  let args = ["--age", "abc"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(result, content="None")
}

test "parse_args: オプション順序は自由" {
  let args = ["--verbose", "true", "--age", "25", "--name", "Carol"]
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  inspect(
    result,
    content="Some({name: \"Carol\", age: 25, verbose: true})",
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
    content="Some({name: \"Dave\", age: 40, verbose: false})",
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
