// FieldRef + AnyBind 方式 PoC
// MoonBit で struct-first CLI パーサが実現可能か検証する

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
// Step 2: AnyBind — 型消去されたフィールドバインド
// =============================================================

/// パース結果
pub(all) enum ReduceResult {
  Accept
  Reject(String)
} derive(Show, Eq)

/// 型消去された「フィールドへの値の適用」を表す trait
pub(all) trait AnyBind[S] {
  apply(Self, S, String) -> (S, ReduceResult)
  field_name(Self) -> String
}

// =============================================================
// Step 3: FieldBind — 具体的な型を持つバインド実装
// =============================================================

/// 型あり実装: FieldRef + パーサ + 副作用
pub(all) struct FieldBind[S, T] {
  field : FieldRef[S, T]
  parse : (String) -> T?
}

/// FieldBind に AnyBind を実装
/// 検証ポイント: 2つの型パラメータを持つ型への trait 実装が動くか
impl[S, T] AnyBind[S] for FieldBind[S, T] with apply(self, s, raw) {
  match (self.parse)(raw) {
    Some(v) => ((self.field.set)(s, v), Accept)
    None => (s, Reject("parse failed: " + raw))
  }
}

impl[S, T] AnyBind[S] for FieldBind[S, T] with field_name(self) {
  self.field.name
}

// =============================================================
// Step 4: OptDef — パーサ定義（オプション名 → バインドのマッピング）
// =============================================================

/// オプション定義: 名前とバインドの対
pub(all) struct OptDef[S] {
  opt_name : String
  bind : &AnyBind[S]
}

/// パーサ本体
pub fn parse_args[S](
  args : Array[String],
  initial : S,
  opts : Array[OptDef[S]]
) -> S? {
  let mut state = initial
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    // オプション名で検索
    let mut found = false
    for opt in opts {
      if opt.opt_name == arg {
        if i + 1 >= args.length() {
          println("Error: missing value for " + arg)
          return None
        }
        let (next, result) = opt.bind.apply(state, args[i + 1])
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
// Step 5: アプリケーション例 — AppConfig
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

/// FieldRef 定義
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
pub fn make_app_opts() -> Array[OptDef[AppConfig]] {
  [
    {
      opt_name: "--name",
      bind: FieldBind::{
        field: AppConfig::name_ref(),
        parse: fn(s) { Some(s) },
      },
    },
    {
      opt_name: "--age",
      bind: FieldBind::{
        field: AppConfig::age_ref(),
        parse: fn(s) { try { Some(@strconv.parse_int!(s)) } catch { _ => None } },
      },
    },
    {
      opt_name: "--verbose",
      bind: FieldBind::{
        field: AppConfig::verbose_ref(),
        parse: fn(s) {
          match s {
            "true" => Some(true)
            "false" => Some(false)
            _ => None
          }
        },
      },
    },
  ]
}

// =============================================================
// Step 6: IntoOpt trait — struct → パーサ定義の導出
// =============================================================

/// struct からパーサ定義を導出する trait
pub(open) trait IntoOpt {
  opts(Self) -> Array[OptDef[Self]]
}

/// AppConfig に IntoOpt を手動実装
impl IntoOpt for AppConfig with opts(_self) {
  make_app_opts()
}

/// IntoOpt を使った便利パース関数
pub fn parse_with[S : IntoOpt](args : Array[String], initial : S) -> S? {
  let opts = initial.opts()
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
