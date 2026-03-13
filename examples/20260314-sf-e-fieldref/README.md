# struct-first CLI パーサ PoC: E. FieldRef + AnyBind 方式

## 背景

kuu は MoonBit 製 CLI 引数パーサライブラリ。現行は「パーサ定義 → Opt[T] → .get().unwrap()」のボトムアップ方式。

新しいアイデア「struct-first」:
- アプリの struct が先にある
- CLIパーサはその struct に値を直接注入する
- 取り出し問題（.get().unwrap() の嵐）が構造的に消滅

## このアプローチ: FieldRef + AnyBind trait object 方式

**これは前回の設計議論で最も具体的に検討された方式**。型安全な FieldRef と Trait object による型消去を組み合わせる。

### コア型

```moonbit
// フィールドへの型安全参照（Lens パターン）
struct FieldRef[S, A] {
  name : String
  get : (S) -> A
  set : (S, A) -> S
}

// 型消去されたフィールドバインド
trait AnyBind[S] {
  apply(Self, S, String) -> (S, ReduceResult)
  field_name(Self) -> String
}

enum ReduceResult {
  Accept
  Reject(String)
}

// 型あり実装
struct FieldBind[S, T] {
  field : FieldRef[S, T]
  parse : (String) -> T?
  commit : (T) -> Unit    // 副作用コールバック（オプション）
}

// FieldBind に AnyBind を実装
impl[S, T] AnyBind[S] for FieldBind[S, T] with
  apply(self, s, raw) {
    match (self.parse)(raw) {
      Some(v) => {
        (self.commit)(v)
        ((self.field.set)(s, v), Accept)
      }
      None => (s, Reject("parse failed"))
    }
  }
  field_name(self) { self.field.name }
```

### Opt[S] とパーサ

```moonbit
struct Opt[S] {
  binds : Array[&AnyBind[S]]
}

fn parse[S](args : Array[String], initial : S, opts : Opt[S]) -> S? {
  let mut state = initial
  let mut i = 0
  while i < args.length() {
    match opts.find(args[i]) {
      Some(bind) => {
        let (next, result) = bind.apply(state, args[i + 1])
        match result {
          Accept => { state = next; i += 2 }
          Reject(msg) => { println("Error: " + msg); return None }
        }
      }
      None => { println("Unknown: " + args[i]); return None }
    }
  }
  Some(state)
}
```

### ユーザー側

```moonbit
struct AppConfig {
  name : String?
  age : Int
}

fn AppConfig::name_ref() -> FieldRef[AppConfig, String?] {
  {
    name: "name",
    get: fn(s) { s.name },
    set: fn(s, a) { { ..s, name: a } },
  }
}

fn AppConfig::age_ref() -> FieldRef[AppConfig, Int] {
  {
    name: "age",
    get: fn(s) { s.age },
    set: fn(s, a) { { ..s, age: a } },
  }
}

// パーサ定義
let opts = Opt::new([
  (FieldBind {
    field: AppConfig::name_ref(),
    parse: fn(s) { Some(s) },
    commit: fn(_v) { },
  } : &AnyBind[AppConfig]),
  (FieldBind {
    field: AppConfig::age_ref(),
    parse: fn(s) { @strconv.parse_int?(s) },
    commit: fn(_v) { },
  } : &AnyBind[AppConfig]),
])

let result = parse(args, AppConfig { name: None, age: 0 }, opts)
```

## 検証すべき MoonBit 技術的疑問

1. **Trait object `&AnyBind[S]`**: ジェネリック型パラメータ S 付きの trait object は動くか？
2. **`impl[S, T] AnyBind[S] for FieldBind[S, T]`**: 2つの型パラメータを持つ型への trait 実装
3. **struct update syntax**: `{ ..s, name: a }` は動くか？
4. **trait object への型キャスト**: `(FieldBind{...} : &AnyBind[AppConfig])` 構文
5. **FieldRef のクロージャ**: get/set クロージャが正しくキャプチャ・動作するか

## 将来の拡張: IntoOpt trait

```moonbit
pub(open) trait IntoOpt {
  into_opt() -> Opt[Self]
}

// ユーザーが手書き impl
impl IntoOpt for AppConfig with into_opt() {
  Opt::new([...])
}
```

将来 MoonBit にカスタム derive が来たら `derive(IntoOpt)` で自動化可能。

## 検証手順

1. `FieldRef[S, A]` の定義と struct update syntax の動作確認
2. `AnyBind[S]` trait + trait object の動作確認
3. `FieldBind[S, T]` の `AnyBind[S]` 実装
4. `parse` 関数で全体を結合
5. サブコマンド対応の検討

## 成功基準

1. MoonBit でコンパイルが通る
2. 型消去が正しく動く（異なる型の FieldBind を同じ配列に格納）
3. FieldRef による get/set が正しく動作
4. IntoOpt trait の手動実装パターンが確立

## 既存 kuu の使い方参考

`examples/20260308-mydocker/main.mbt` を参照。
パッケージ: `import { "kawaz/kuu/src/core" }` + `options("is-main": true)`

## 作業方法

/itumono-full-loop でフルオートループ。PoC なので「動くかどうか」の確認が最優先。
動かない場合は「なぜ動かないか」を DR に記録すること。
