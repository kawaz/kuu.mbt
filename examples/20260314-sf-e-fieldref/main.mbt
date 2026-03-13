// FieldRef + Binder 方式 PoC
// MoonBit で struct-first CLI パーサが実現可能か検証する
//
// 当初 trait AnyBind[S] を使う設計だったが、MoonBit の trait は
// 型パラメータを受け付けないため、クロージャベースの型消去に変更 (DR-001)

// =============================================================
// Step 1: FieldRef — フィールドへの型安全参照（Lens パターン）
// =============================================================

/// フィールドへの型安全参照
/// S: struct 型, A: フィールドの型
pub(all) struct FieldRef[S, A] {
  name : String
  get : (S) -> A
  set : (S, A) -> S
}

// =============================================================
// Step 2: Binder — クロージャベースの型消去バインド
// =============================================================

/// パース結果
pub(all) enum ReduceResult {
  Accept
  Reject(String)
} derive(Show, Eq)

/// 型消去された「フィールドへの値の適用」
/// T は apply クロージャの中に閉じ込められている
pub(all) struct Binder[S] {
  name : String
  apply : (S, String) -> (S, ReduceResult)
}

/// FieldRef + parser からクロージャベースの Binder を生成するファクトリ
/// これが型消去のキーポイント: T はこの関数内で消える
pub fn[S, T] make_binder(
  field : FieldRef[S, T],
  parse : (String) -> T?
) -> Binder[S] {
  {
    name: field.name,
    apply: fn(s, raw) {
      match parse(raw) {
        Some(v) => ((field.set)(s, v), Accept)
        None => (s, Reject("parse failed: " + raw))
      }
    },
  }
}

// =============================================================
// Step 3: OptDef — オプション定義（名前 → Binder のマッピング）
// =============================================================

/// オプション定義: CLI オプション名とバインダの対
pub(all) struct OptDef[S] {
  opt_name : String
  binder : Binder[S]
}

// =============================================================
// Step 4: parse — パーサ本体
// =============================================================

/// パーサ本体: args を走査して OptDef に従い state を更新
pub fn[S] parse_args(
  args : Array[String],
  initial : S,
  opts : Array[OptDef[S]]
) -> S? {
  let mut state = initial
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    let mut found = false
    for opt in opts {
      if opt.opt_name == arg {
        if i + 1 >= args.length() {
          println("Error: missing value for " + arg)
          return None
        }
        let (next, result) = (opt.binder.apply)(state, args[i + 1])
        match result {
          Accept => {
            state = next
            i = i + 2
            found = true
            break
          }
          Reject(msg) => {
            println("Error: " + msg)
            return None
          }
        }
      }
    }
    if not(found) {
      println("Unknown option: " + arg)
      return None
    }
  }
  Some(state)
}

// =============================================================
// Step 5: AppConfig — アプリケーション例
// =============================================================

/// アプリケーション設定 struct
pub(all) struct AppConfig {
  name : String
  age : Int
  verbose : Bool
} derive(Show, Eq)

/// AppConfig のデフォルト値
pub fn AppConfig::default() -> AppConfig {
  { name: "", age: 0, verbose: false }
}

/// FieldRef 定義 — struct update syntax `{ ..s, field: v }` の検証
pub fn AppConfig::name_ref() -> FieldRef[AppConfig, String] {
  {
    name: "name",
    get: fn(s) { s.name },
    set: fn(s, a) { { ..s, name: a } },
  }
}

pub fn AppConfig::age_ref() -> FieldRef[AppConfig, Int] {
  {
    name: "age",
    get: fn(s) { s.age },
    set: fn(s, a) { { ..s, age: a } },
  }
}

pub fn AppConfig::verbose_ref() -> FieldRef[AppConfig, Bool] {
  {
    name: "verbose",
    get: fn(s) { s.verbose },
    set: fn(s, a) { { ..s, verbose: a } },
  }
}

/// パーサ定義を組み立てる
/// 異なる型の FieldRef が同じ Array[OptDef[AppConfig]] に格納される — 型消去の検証
pub fn make_app_opts() -> Array[OptDef[AppConfig]] {
  [
    {
      opt_name: "--name",
      binder: make_binder(AppConfig::name_ref(), fn(s) { Some(s) }),
    },
    {
      opt_name: "--age",
      binder: make_binder(
        AppConfig::age_ref(),
        fn(s) { try { Some(@strconv.parse_int(s)) } catch { _ => None } },
      ),
    },
    {
      opt_name: "--verbose",
      binder: make_binder(
        AppConfig::verbose_ref(),
        fn(s) {
          match s {
            "true" => Some(true)
            "false" => Some(false)
            _ => None
          }
        },
      ),
    },
  ]
}

// =============================================================
// Step 6: IntoOpt trait — struct → パーサ定義の導出
// =============================================================

/// struct からパーサ定義を導出する trait
/// 将来 MoonBit にカスタム derive が来たら自動化可能
pub(open) trait IntoOpt {
  opts(Self) -> Array[OptDef[Self]]
}

/// AppConfig に IntoOpt を手動実装
impl IntoOpt for AppConfig with opts(_self) {
  make_app_opts()
}

/// IntoOpt を使った便利パース関数
pub fn[S : IntoOpt] parse_with(args : Array[String], initial : S) -> S? {
  let opts = IntoOpt::opts(initial)
  parse_args(args, initial, opts)
}

// =============================================================
// main: デモ実行
// =============================================================

fn main {
  let args = ["--name", "Alice", "--age", "30", "--verbose", "true"]

  // 方法1: 明示的にオプション定義を渡す
  let result = parse_args(args, AppConfig::default(), make_app_opts())
  match result {
    Some(config) => println("Result: " + config.to_string())
    None => println("Parse failed")
  }

  // 方法2: IntoOpt trait を使う
  let result2 = parse_with(args, AppConfig::default())
  match result2 {
    Some(config) => println("IntoOpt: " + config.to_string())
    None => println("IntoOpt parse failed")
  }
}
